const std = @import("std");
const LineReader = @import("LineReader").LineReader;
const CsvLine = @import("CsvLine").CsvLine;
const Options = @import("options.zig").Options;
const Filter = @import("options.zig").Filter;
const ArgumentParser = @import("arguments.zig").Parser;
const Utf8Output = @import("Utf8Output.zig");

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

    try ArgumentParser.parse(&options, args);

    const stderr = std.io.getStdErr().writer();

    if (options.useStdin) {
        switch (options.outputFormat) {
            .markdown, .jira, .table => {
                _ = try stderr.print("the formats Markdown, Jira and Table can not be used with stdin\n", .{});
                return;
            },
            else => {},
        }
        var lineReader = try LineReader.initReader(std.io.getStdIn().reader().any(), allocator, .{});
        defer lineReader.deinit();
        try proccessFile(&lineReader, std.io.getStdOut());
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
    var lineReader = try LineReader.initFile(&file, allocator, .{});
    defer lineReader.deinit();
    try proccessFile(&lineReader, std.io.getStdOut());
}

const Fields = struct {
    fields: [][]const u8,
    count: usize,

    pub fn init(fields: *const [][]const u8) !Fields {
        var self: Fields = (try allocator.alloc(Fields, 1))[0];
        self.count = 1;

        if (options.selectionIndices) |indices| {
            self.fields = try allocator.alloc([]u8, indices.len + 1);
            for (indices, 0..) |field, i| {
                self.fields[i] = try allocator.dupe(u8, fields.*[field]);
            }
        } else {
            self.fields = try allocator.alloc([]u8, fields.len + 1);
            for (fields.*, 0..) |field, i| {
                self.fields[i] = try allocator.dupe(u8, field);
            }
        }
        return self;
    }

    pub fn get(self: *const Fields) !*const [][]const u8 {
        self.fields[self.fields.len - 1] = try std.fmt.allocPrint(allocator, "{d}", .{self.count});
        return &self.fields;
    }
};

const SelectedFields = struct {
    var selected: [][]const u8 = undefined;

    fn init() !void {
        if (options.selectionIndices) |selectionIndices| {
            selected = try allocator.alloc([]u8, selectionIndices.len);
        }
    }

    fn deinit() void {
        if (options.selectionIndices) {
            allocator.free(selected);
        }
    }

    inline fn get(fields: *const [][]const u8) *const [][]const u8 {
        if (options.selectionIndices) |indices| {
            for (indices, 0..) |field, index| {
                selected[index] = fields.*[field];
            }
            return &selected;
        } else {
            return fields;
        }
    }
};

const SkipableLineReader = struct {
    var lineNumber: usize = 0;
    var linesRead: usize = 0;

    fn reset() void {
        lineNumber = 0;
        linesRead = 0;
    }

    fn resetLinesRead() void {
        linesRead = 0;
    }

    inline fn readLine(lineReader: anytype) !?[]const u8 {
        if (options.inputLimit > 0 and options.inputLimit == linesRead) {
            return null;
        }
        if (options.skipLine != null) {
            while (options.skipLine.?.get(lineNumber) != null) {
                _ = try lineReader.readLine();
                lineNumber += 1;
                linesRead += 1;
            }
        }
        lineNumber += 1;
        linesRead += 1;
        return lineReader.readLine();
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
        if (options.selectionIndices) |indices| {
            for (indices) |field| {
                try keyBuffer.appendSlice(fields.*[field]);
                try keyBuffer.append('|');
            }
        } else {
            for (fields.*) |field| {
                try keyBuffer.appendSlice(field);
                try keyBuffer.append('|');
            }
        }
        return keyBuffer.items;
    }
};

const FormattedWriter = *const fn (*const std.io.AnyWriter, *const [][]const u8, bool) anyerror!void;

const OutputWriter = struct {
    var formattedWriter: FormattedWriter = undefined;
    var lineBuffer: std.ArrayList(u8) = undefined;
    var outputWriter: std.io.AnyWriter = undefined;
    var initialized = false;

    fn init(writer: std.io.AnyWriter) !void {
        if (!initialized) {
            formattedWriter = switch (options.outputFormat) {
                .csv => &writeOutputCsv,
                .lazyMarkdown => &writeOutputLazyMarkdown,
                .lazyJira => &writeOutputLazyJira,
                .markdown => &writeOutputMarkdown,
                .jira => &writeOutputJira,
                .table => &writeOutputTable,
                .html => &writeOutputhtml,
            };
            lineBuffer = try std.ArrayList(u8).initCapacity(allocator, 1024);
            initialized = true;
        }
        outputWriter = writer;
    }

    fn deinit() void {
        lineBuffer.deinit();
    }

    fn writeBuffered(fields: *const [][]const u8, isHeader: bool) !void {
        lineBuffer.clearRetainingCapacity();
        try formattedWriter(&lineBuffer.writer().any(), fields, isHeader);
    }

    fn getBuffer() []u8 {
        return lineBuffer.items;
    }

    fn writeDirect(fields: *const [][]const u8, isHeader: bool) !void {
        try formattedWriter(&outputWriter, fields, isHeader);
    }

    fn commitBuffer() !void {
        _ = try outputWriter.write(lineBuffer.items);
    }
};

const FieldWidths = struct {
    var widths: []usize = undefined;
    var spaces: []u8 = undefined;
    var dashes: []u8 = undefined;
    var lineDashes: []u8 = undefined;
    var maxSpace: usize = undefined;

    fn calculate(lineReader: anytype, csvLine: *CsvLine) !void {
        switch (options.outputFormat) {
            .markdown, .jira, .table => {
                if (options.fileHeader) {
                    try resetReader(lineReader);
                }

                try collectWidths(lineReader, csvLine);
                calculateMaxSpace();
                try initPaddingStrings();

                try resetReader(lineReader);
                try skipFileHeader(lineReader);
            },
            else => {},
        }
    }

    fn resetReader(lineReader: anytype) !void {
        try lineReader.reset();
        SkipableLineReader.reset();
    }

    fn collectWidths(lineReader: anytype, csvLine: *CsvLine) !void {
        var fieldWidths: std.ArrayList(usize) = try std.ArrayList(usize).initCapacity(allocator, 16);
        while (try SkipableLineReader.readLine(lineReader)) |line| {
            const fields = try csvLine.parse(line);
            if (noFilterOrfilterMatches(fields, options.filterFields)) {
                for (SelectedFields.get(&fields).*, 0..) |field, i| {
                    if (i + 1 > fieldWidths.items.len) {
                        try fieldWidths.append(0);
                    }
                    switch (options.outputFormat) {
                        .markdown => widths[i] = @max(fieldWidths.items[i], (try escapeMarkup(field, markdownSpecial)).len),
                        .jira => fieldWidths.items[i] = @max(fieldWidths.items[i], (try escapeMarkup(field, jiraSpecial)).len),
                        .table => fieldWidths.items[i] = @max(fieldWidths.items[i], field.len),
                        else => undefined,
                    }
                }
            }
        }
        widths = try fieldWidths.toOwnedSlice();
    }

    fn calculateMaxSpace() void {
        maxSpace = 0;
        for (widths) |width| {
            maxSpace = @max(maxSpace, width);
        }
    }

    fn initPaddingStrings() !void {
        spaces = try allocator.alloc(u8, maxSpace + 1); //todo: free
        @memset(spaces, ' ');

        dashes = try allocator.alloc(u8, maxSpace); //todo: free
        @memset(dashes, '-');

        lineDashes = try allocator.alloc(u8, maxSpace * 3); //todo: free
        for (0..maxSpace) |i| {
            std.mem.copyForwards(u8, lineDashes[(i * 3)..], "─");
        }
    }

    fn skipFileHeader(lineReader: anytype) !void {
        if (options.fileHeader) {
            if (try SkipableLineReader.readLine(lineReader)) |line| {
                _ = line;
            }
        }
    }
};

fn proccessFile(lineReader: *LineReader, outputFile: std.fs.File) !void {
    var csvLine = try CsvLine.init(allocator, .{ .separator = options.input_separator[0], .trim = options.trim, .quoute = if (options.input_quoute) |quote| quote[0] else null });
    defer csvLine.free();

    if (options.listHeader) {
        try listHeader(lineReader, &csvLine);
        return;
    }

    var bufferedWriter = std.io.bufferedWriter(outputFile.writer());
    try OutputWriter.init(bufferedWriter.writer().any());

    SkipableLineReader.reset();
    UniqueAgregator.init();
    try CountAggregator.init();

    if (options.fileHeader) {
        if (try SkipableLineReader.readLine(lineReader)) |line| {
            try options.setHeader(line);
        }
        SkipableLineReader.resetLinesRead();
    }

    try options.setSelectionIndices();
    try SelectedFields.init();

    try FieldWidths.calculate(lineReader, &csvLine);

    if (options.header != null and options.outputHeader) {
        if (options.count) {
            const header = try (try Fields.init(&options.header.?)).get();
            header.*[header.*.len - 1] = "Count";
            try OutputWriter.writeDirect(header, true);
        } else {
            try OutputWriter.writeDirect(SelectedFields.get(&options.header.?), true);
        }
    }

    if (options.filterFields != null) {
        try options.setFilterIndices();
    }

    var linesWritten: usize = 0;
    while (try SkipableLineReader.readLine(lineReader)) |line| {
        const fields = try csvLine.parse(line);

        if (noFilterOrfilterMatches(fields, options.filterFields)) {
            if (options.unique) {
                try OutputWriter.writeBuffered(SelectedFields.get(&fields), false);

                if (try UniqueAgregator.isNew(OutputWriter.getBuffer())) {
                    try OutputWriter.commitBuffer();
                    linesWritten += 1;
                }
            } else if (options.count) {
                try CountAggregator.add(&fields);
            } else {
                try OutputWriter.writeDirect(SelectedFields.get(&fields), false);
                linesWritten += 1;
            }
            if (options.outputLimit != 0 and linesWritten >= options.outputLimit) {
                break;
            }
        }
    }

    if (options.count) {
        var iterator = CountAggregator.countMap.iterator();
        while (iterator.next()) |entry| {
            try OutputWriter.writeDirect(try entry.value_ptr.get(), false);
            linesWritten += 1;
            if (options.outputLimit != 0 and linesWritten >= options.outputLimit) {
                break;
            }
        }
    }

    if (options.outputFormat == .table) {
        try writeTableLine(&bufferedWriter.writer().any(), FieldWidths.widths.len, "└", "┴", "┘\n");
    } else if (options.outputFormat == .html) {
        _ = try bufferedWriter.writer().write("</table></body></html>");
    }
    try bufferedWriter.flush();
}

fn listHeader(lineReader: *LineReader, csvLine: *CsvLine) !void {
    const out = std.io.getStdOut();
    if (try lineReader.readLine()) |line| {
        for (try csvLine.parse(line)) |field| {
            _ = try out.write(field);
            _ = try out.write("\n");
        }
    }
}

fn writeOutputCsv(writer: *const std.io.AnyWriter, fields: *const [][]const u8, isHeader: bool) !void {
    _ = isHeader;
    for (fields.*, 0..) |field, index| {
        if (index > 0) {
            _ = try writer.write(&options.output_separator);
        }
        if (options.output_quoute != null) {
            _ = try writer.write(&options.output_quoute.?);
        }
        _ = try writer.write(field);
        if (options.output_quoute != null) {
            _ = try writer.write(&options.output_quoute.?);
        }
    }
    _ = try writer.write("\n");
}

fn writeOutputLazyMarkdown(writer: *const std.io.AnyWriter, fields: *const [][]const u8, isHeader: bool) !void {
    for (fields.*) |field| {
        _ = try writer.write("| ");
        _ = try writer.write(try escapeMarkup(field, markdownSpecial));
        _ = try writer.write(" ");
    }
    _ = try writer.write("|\n");
    if (isHeader) {
        for (fields.*) |field| {
            _ = field;
            _ = try writer.write("| --- ");
        }
        _ = try writer.write("|\n");
    }
}

fn writeOutputMarkdown(writer: *const std.io.AnyWriter, fields: *const [][]const u8, isHeader: bool) !void {
    for (fields.*, 0..) |field, i| {
        const escaped = try escapeMarkup(field, jiraSpecial);
        const len = FieldWidths.widths[i] - escaped.len + 1;

        _ = try writer.write("| ");
        _ = try writer.write(escaped);
        _ = try writer.write(FieldWidths.spaces[0..len]);
    }
    _ = try writer.write("|\n");
    if (isHeader) {
        for (fields.*, 0..) |field, i| {
            _ = field;
            const len = if (FieldWidths.widths[i] < 3) 3 else FieldWidths.widths[i];

            _ = try writer.write("| ");
            _ = try writer.write(FieldWidths.dashes[0..len]);
            _ = try writer.write(" ");
        }
        _ = try writer.write("|\n");
    }
}

var escapeBuffer: [1024]u8 = undefined;
const markdownSpecial: []const u8 = "\\`*_{}[]<>()#+-.!|";
const jiraSpecial: []const u8 = "*_-{|^+?#";

inline fn escapeMarkup(field: []const u8, comptime specialCharacters: []const u8) ![]const u8 {
    var offset: u16 = 0;
    for (field, 0..) |c, i| {
        if (std.mem.indexOfScalar(u8, specialCharacters, c)) |pos| {
            _ = pos;
            if (offset == 0) {
                std.mem.copyForwards(u8, &escapeBuffer, field[0..i]);
            }
            escapeBuffer[i + offset] = '\\';
            offset += 1;
            escapeBuffer[i + offset] = c;
        } else if (offset > 0) {
            escapeBuffer[i + offset] = c;
        }
    }
    if (offset > 0) {
        return escapeBuffer[0 .. field.len + offset];
    }
    return field;
}

fn writeOutputLazyJira(writer: *const std.io.AnyWriter, fields: *const [][]const u8, isHeader: bool) !void {
    if (isHeader) {
        for (fields.*) |field| {
            _ = try writer.write("||");
            _ = try writer.write(try escapeMarkup(field, jiraSpecial));
            _ = try writer.write(" ");
        }
        _ = try writer.write("||\n");
    } else {
        for (fields.*) |field| {
            _ = try writer.write("| ");
            _ = try writer.write(try escapeMarkup(field, jiraSpecial));
            _ = try writer.write(" ");
        }
        _ = try writer.write("|\n");
    }
}

fn writeOutputJira(writer: *const std.io.AnyWriter, fields: *const [][]const u8, isHeader: bool) !void {
    if (isHeader) {
        for (fields.*, 0..) |field, i| {
            const escaped = try escapeMarkup(field, jiraSpecial);
            const len = FieldWidths.widths[i] - escaped.len + 1;

            _ = try writer.write("||");
            _ = try writer.write(escaped);
            _ = try writer.write(FieldWidths.spaces[0..len]);
        }
        _ = try writer.write("||\n");
    } else {
        for (fields.*, 0..) |field, i| {
            const escaped = try escapeMarkup(field, jiraSpecial);
            const len = FieldWidths.widths[i] - escaped.len + 1;

            _ = try writer.write("| ");
            _ = try writer.write(try escapeMarkup(field, jiraSpecial));
            _ = try writer.write(FieldWidths.spaces[0..len]);
        }
        _ = try writer.write("|\n");
    }
}

fn writeOutputTable(writer: *const std.io.AnyWriter, fields: *const [][]const u8, isHeader: bool) !void {
    if (isHeader) {
        try writeTableLine(writer, fields.len, "┌", "┬", "┐\n");
        for (fields.*, 0..) |field, i| {
            const len = FieldWidths.widths[i] - field.len;
            _ = try writer.write("│");
            _ = try writer.write(field);
            _ = try writer.write(FieldWidths.spaces[0..len]);
        }
        _ = try writer.write("│\n");
        try writeTableLine(writer, fields.len, "├", "┼", "┤\n");
    } else {
        //try writeTableLine(writer, fields.len);
        for (fields.*, 0..) |field, i| {
            const len = FieldWidths.widths[i] - field.len;
            _ = try writer.write("│");
            _ = try writer.write(field);
            _ = try writer.write(FieldWidths.spaces[0..len]);
        }
        _ = try writer.write("│\n");
    }
}

inline fn writeTableLine(writer: *const std.io.AnyWriter, len: usize, left: []const u8, middle: []const u8, right: []const u8) !void {
    for (0..len) |i| {
        if (i == 0) {
            _ = try writer.write(left);
        } else {
            _ = try writer.write(middle);
        }
        _ = try writer.write(FieldWidths.lineDashes[0 .. FieldWidths.widths[i] * 3]);
    }
    _ = try writer.write(right);
}

fn writeOutputhtml(writer: *const std.io.AnyWriter, fields: *const [][]const u8, isHeader: bool) !void {
    if (isHeader) {
        _ = try writer.write("<html><body><table>\n");
        _ = try writer.write("<tr>");
        for (fields.*) |field| {
            _ = try writer.write("<th>");
            _ = try writer.write(field);
            _ = try writer.write("</th>");
        }
        _ = try writer.write("</tr>\n");
    } else {
        _ = try writer.write("<tr>");
        for (fields.*) |field| {
            _ = try writer.write("<td>");
            _ = try writer.write(field);
            _ = try writer.write("</td>");
        }
        _ = try writer.write("</tr>\n");
    }
}

inline fn noFilterOrfilterMatches(fields: [][]const u8, filterFields: ?std.ArrayList(Filter)) bool {
    if (filterFields == null) {
        return true;
    }
    for (filterFields.?.items) |filter| {
        if (!std.mem.eql(u8, fields[filter.index], filter.value)) {
            return false;
        }
    }
    return true;
}

test "escapeMarkdown returns filed if no escape is needed" {
    const unescaped: []const u8 = "unescaped";
    const res = try escapeMarkup(unescaped);
    try std.testing.expectEqualStrings(unescaped, res);
    try std.testing.expectEqual(unescaped.ptr, res.ptr);
}

test "escapeMarkdown escapes special characters with backslash" {
    const unescaped: []const u8 = "unescaped* -test [1-3] #Test end";
    const res = try escapeMarkup(unescaped);
    try std.testing.expectEqualStrings("unescaped\\* \\-test \\[1\\-3\\] \\#Test end", res);
    try std.testing.expectEqual(&escapeBuffer, res.ptr);
}
