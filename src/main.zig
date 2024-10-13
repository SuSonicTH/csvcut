const std = @import("std");
const CsvLine = @import("CsvLine").CsvLine;
const Options = @import("options.zig").Options;
const Filter = @import("options.zig").Filter;
const ArgumentParser = @import("arguments.zig").Parser;
const Utf8Output = @import("Utf8Output.zig");
const FieldReader = @import("FieldReader.zig");
const FormatWriter = @import("FormatWriter.zig").FormatWriter;
const FieldWidths = @import("FieldWidths.zig");

var allocator: std.mem.Allocator = undefined;
var options: Options = undefined;

pub fn main() !void {
    var timer = try std.time.Timer.start();
    Utf8Output.init();
    defer Utf8Output.deinit();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    options = try Options.init(allocator);
    defer options.deinit();

    try ArgumentParser.parse(&options, args, allocator);
    try ArgumentParser.checkInputFileGiven(&options);

    const stderr = std.io.getStdErr().writer();

    if (options.useStdin) {
        switch (options.outputFormat) {
            .markdown, .jira, .table => {
                _ = try stderr.print("the formats Markdown, Jira and Table can not be used with stdin\n", .{});
                return;
            },
            else => {},
        }
        if (options.lengths) |lengths| {
            var fieldReader: FieldReader = try FieldReader.initWidthReader(std.io.getStdIn().reader().any(), lengths.items, options.trim, options.inputLimit, options.skipLine, options.extraLineEnd, allocator);
            try proccessFile(&fieldReader, std.io.getStdOut());
        } else {
            var fieldReader: FieldReader = try FieldReader.initCsvReader(std.io.getStdIn().reader().any(), options.inputLimit, options.skipLine, .{ .separator = options.inputSeparator[0], .trim = options.trim, .quoute = if (options.inputQuoute) |quote| quote[0] else null }, allocator);
            try proccessFile(&fieldReader, std.io.getStdOut());
        }
    } else {
        for (options.inputFiles.items) |file| {
            try processFileByName(file);
        }
    }

    const timeNeeded = @as(f32, @floatFromInt(timer.lap())) / 1000000.0;
    if (timeNeeded > 1000) {
        _ = try stderr.print("time needed: {d:0.2}s\n", .{timeNeeded / 1000.0});
    } else {
        _ = try stderr.print("time needed: {d:0.2}ms\n", .{timeNeeded});
    }
    _ = try stderr.print("memory used: {d}b\n", .{arena.queryCapacity()});
}

fn processFileByName(fileName: []const u8) !void {
    var file = try std.fs.cwd().openFile(fileName, .{});
    defer file.close();

    if (options.lengths) |lengths| {
        var fieldReader: FieldReader = try FieldReader.initWidthFile(&file, lengths.items, options.trim, options.inputLimit, options.skipLine, options.extraLineEnd, allocator);
        try proccessFile(&fieldReader, std.io.getStdOut());
    } else {
        var fieldReader: FieldReader = try FieldReader.initCsvFile(&file, options.inputLimit, options.skipLine, .{ .separator = options.inputSeparator[0], .trim = options.trim, .quoute = if (options.inputQuoute) |quote| quote[0] else null }, allocator);
        try proccessFile(&fieldReader, std.io.getStdOut());
    }
}

const Fields = struct {
    fields: [][]const u8,
    count: usize,

    pub fn init(fields: *const [][]const u8) !Fields {
        var self: Fields = (try allocator.alloc(Fields, 1))[0];
        self.count = 1;
        self.fields = try allocator.alloc([]u8, fields.len + 1);
        for (fields.*, 0..) |field, i| {
            self.fields[i] = try allocator.dupe(u8, field);
        }
        return self;
    }

    pub fn get(self: *const Fields) !*const [][]const u8 {
        self.fields[self.fields.len - 1] = try std.fmt.allocPrint(allocator, "{d}", .{self.count});
        return &self.fields;
    }
};

const UniqueAgregator = struct {
    var uniqueSet: ?std.StringHashMap(u1) = null;
    var initialized = false;

    fn init() void {
        if (options.unique) {
            if (!initialized) {
                uniqueSet = std.StringHashMap(u1).init(allocator);
                initialized = true;
            } else {
                uniqueSet.?.clearRetainingCapacity();
            }
        }
    }

    inline fn isNew(line: []u8) !bool {
        if (!uniqueSet.?.contains(line)) {
            try uniqueSet.?.put(try allocator.dupe(u8, line), 1);
            return true;
        }
        return false;
    }
};

const CountAggregator = struct {
    var countMap: std.StringHashMap(Fields) = undefined;
    var keyBuffer: std.ArrayList(u8) = undefined;
    var initialized = false;

    fn init() !void {
        if (options.count) {
            if (!initialized) {
                countMap = std.StringHashMap(Fields).init(allocator);
                keyBuffer = try std.ArrayList(u8).initCapacity(allocator, 1024);
                initialized = true;
            } else {
                countMap.clearRetainingCapacity();
                keyBuffer.clearRetainingCapacity();
            }
        }
    }

    fn add(fields: *const [][]const u8) !void {
        if (countMap.getEntry(try getKey(fields))) |entry| {
            entry.value_ptr.*.count += 1;
        } else {
            try countMap.put(try allocator.dupe(u8, keyBuffer.items), try Fields.init(fields));
        }
    }

    fn getKey(fields: *const [][]const u8) ![]u8 {
        keyBuffer.clearRetainingCapacity();
        for (fields.*) |field| {
            try keyBuffer.appendSlice(field);
            try keyBuffer.append('|');
        }
        return keyBuffer.items;
    }
};

const FormattedWriter = *const fn (*const std.io.AnyWriter, *const [][]const u8, bool) anyerror!void;

const OutputWriter = struct {
    var formatWriter: FormatWriter = undefined;
    var lineBuffer: std.ArrayList(u8) = undefined;
    var outputWriter: std.io.AnyWriter = undefined;
    var initialized = false;

    fn init(writer: std.io.AnyWriter, fieldWidths: FieldWidths) !void {
        if (!initialized) {
            formatWriter = try FormatWriter.init(options, allocator, fieldWidths);
            lineBuffer = try std.ArrayList(u8).initCapacity(allocator, 1024);
            try formatWriter.start(&writer);
            initialized = true;
        }
        outputWriter = writer;
    }

    fn end() !void {
        try formatWriter.end(&outputWriter);
    }

    fn deinit() void {
        lineBuffer.deinit();
        initialized = false;
    }

    fn writeBuffered(fields: *const [][]const u8, isHeader: bool) !void {
        lineBuffer.clearRetainingCapacity();
        if (isHeader) {
            try formatWriter.writeHeader(&lineBuffer.writer().any(), fields);
        } else {
            try formatWriter.writeData(&lineBuffer.writer().any(), fields);
        }
    }

    fn getBuffer() []u8 {
        return lineBuffer.items;
    }

    fn writeDirect(fields: *const [][]const u8, isHeader: bool) !void {
        if (isHeader) {
            try formatWriter.writeHeader(&outputWriter, fields);
        } else {
            try formatWriter.writeData(&outputWriter, fields);
        }
    }

    fn commitBuffer() !void {
        _ = try outputWriter.write(lineBuffer.items);
    }
};

fn proccessFile(fieldReader: *FieldReader, outputFile: std.fs.File) !void {
    if (options.listHeader) {
        try listHeader(fieldReader);
        return;
    }

    UniqueAgregator.init();
    try CountAggregator.init();

    if (options.fileHeader) {
        if (try fieldReader.readLine()) |fields| {
            try options.setHeaderFields(fields);
        }
        fieldReader.resetLinesRead();
    }

    try options.calculateSelectedIndices();
    try fieldReader.setSelectedIndices(options.selectedIndices);
    try fieldReader.setExcludedIndices(options.excludedIndices);

    if (options.filterFields != null) {
        try options.setFilterIndices();
        fieldReader.setFilterFields(options.filterFields);
    }

    var fieldWidths = try FieldWidths.init(options.outputFormat, options.fileHeader, options.header, fieldReader, allocator);
    defer fieldWidths.deinit();

    var bufferedWriter = std.io.bufferedWriter(outputFile.writer());
    try OutputWriter.init(bufferedWriter.writer().any(), fieldWidths);
    defer OutputWriter.deinit();

    if (options.header != null and options.outputHeader) {
        if (options.count) {
            const selectedHeader = &(try fieldReader.getSelectedFields(options.header.?)).?;
            const header = try (try Fields.init(selectedHeader)).get();
            header.*[header.*.len - 1] = "Count";
            try OutputWriter.writeDirect(header, true);
        } else {
            try OutputWriter.writeDirect(&(try fieldReader.getSelectedFields(options.header.?)).?, true);
        }
    }

    var linesWritten: usize = 0;
    while (try fieldReader.readLine()) |fields| {
        if (options.unique) {
            try OutputWriter.writeBuffered(&fields, false);

            if (try UniqueAgregator.isNew(OutputWriter.getBuffer())) {
                try OutputWriter.commitBuffer();
                linesWritten += 1;
            }
        } else if (options.count) {
            try CountAggregator.add(&fields);
        } else {
            try OutputWriter.writeDirect(&fields, false);
            linesWritten += 1;
        }
        if (options.outputLimit != 0 and linesWritten >= options.outputLimit) {
            break;
        }
    }

    if (options.count) { //todo: need to update FieldWidths for the count column, currenlt y--count with --format table segfaults
        var iterator = CountAggregator.countMap.iterator();
        while (iterator.next()) |entry| {
            try OutputWriter.writeDirect(try entry.value_ptr.get(), false);
            linesWritten += 1;
            if (options.outputLimit != 0 and linesWritten >= options.outputLimit) {
                break;
            }
        }
    }

    try OutputWriter.end();
    try bufferedWriter.flush();
}

fn listHeader(fieldReader: *FieldReader) !void {
    const out = std.io.getStdOut();
    if (try fieldReader.readLine()) |fields| {
        for (fields) |field| {
            _ = try out.write(field);
            _ = try out.write("\n");
        }
    }
}
