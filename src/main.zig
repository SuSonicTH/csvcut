const std = @import("std");
const stdout = @import("stdout.zig");
const CsvLine = @import("CsvLine").CsvLine;
const Options = @import("options.zig").Options;
const Filter = @import("options.zig").Filter;
const ArgumentParser = @import("arguments.zig").Parser;
const Utf8Output = @import("Utf8Output.zig");
const FormatWriter = @import("FormatWriter.zig").FormatWriter;
const FieldWidths = @import("FieldWidths.zig");
const FieldReader = @import("FieldReader.zig");
const config = @import("config.zig");

const Aggregate = @import("Aggregate.zig");
const Fields = Aggregate.Fields;
const CountAggregator = Aggregate.CountAggregator;
const UniqueAgregator = Aggregate.UniqueAgregator;
const ExitCode = @import("exitCode.zig").ExitCode;

var allocator: std.mem.Allocator = undefined;
var options: Options = undefined;

pub fn main() !void {
    _main() catch |err| switch (err) {
        error.OutOfMemory => ExitCode.outOfMemory.printErrorAndExit(.{}),
        else => ExitCode.genericError.printErrorAndExit(.{err}),
    };
}

fn _main() !void {
    var timer = try std.time.Timer.start();
    Utf8Output.init();
    defer Utf8Output.deinit();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    const arguments = try castArgs(args);
    defer allocator.free(arguments);

    options = try Options.init(allocator);
    defer options.deinit();

    if (config.readConfigFromFile("default.config", allocator) catch null) |defaultArguments| {
        try ArgumentParser.parse(&options, defaultArguments.items, allocator);
    }
    try ArgumentParser.parse(&options, arguments, allocator);

    if (options.listHeader) {
        try listHeader();
        return;
    }

    try ArgumentParser.validateArguments(&options);

    const stderr = stdout.getErrWriter();
    defer stdout.flushErr();

    var outputFile: std.fs.File = undefined;
    if (options.outputName) |outputName| {
        outputFile = std.fs.cwd().createFile(outputName, .{}) catch |err| ExitCode.couldNotOpenOutputFile.printErrorAndExit(.{ outputName, err });
    } else {
        outputFile = std.fs.File.stdout();
    }
    defer outputFile.close();

    for (options.inputFiles.items) |fileName| {
        var file = std.fs.cwd().openFile(fileName, .{}) catch |err| ExitCode.couldNotOpenInputFile.printErrorAndExit(.{ fileName, err });
        defer file.close();

        var fieldReader = try initFileReader(&file);
        defer fieldReader.deinit();

        try proccessFile(&fieldReader, outputFile);
    }

    if (options.time) {
        const timeNeeded = @as(f32, @floatFromInt(timer.lap())) / 1000000.0;
        if (timeNeeded > 1000) {
            _ = try stderr.print("time needed: {d:0.2}s\n", .{timeNeeded / 1000.0});
        } else {
            _ = try stderr.print("time needed: {d:0.2}ms\n", .{timeNeeded});
        }
    }
}

fn castArgs(args: [][:0]u8) ![][]const u8 {
    var ret = try allocator.alloc([]const u8, args.len);
    for (args, 0..) |arg, i| {
        ret[i] = arg[0..];
    }
    return ret;
}

fn initFileReader(file: *std.fs.File) !FieldReader {
    if (options.lengths) |lengths| {
        return try FieldReader.initFixedReader(file, options.inputLimit, options.skipLine, lengths.items, options.trim, options.extraLineEnd, allocator);
    } else {
        return try FieldReader.initCsvReader(file, options.inputLimit, options.skipLine, .{ .separator = options.inputSeparator[0], .trim = options.trim, .quoute = if (options.inputQuoute) |quote| quote[0] else null }, allocator);
    }
}

const OutputWriter = struct {
    var formatWriter: FormatWriter = undefined;
    var lineBuffer: std.array_list.Managed(u8) = undefined;
    var outputWriter: *std.Io.Writer = undefined;
    var initialized = false;

    fn init(writer: *std.Io.Writer, fieldWidths: FieldWidths) !void {
        if (!initialized) {
            formatWriter = try FormatWriter.init(options, allocator, fieldWidths);
            lineBuffer = try std.array_list.Managed(u8).initCapacity(allocator, 1024);
            try formatWriter.start(writer);
            initialized = true;
        }
        outputWriter = writer;
    }

    fn end() !void {
        try formatWriter.end(outputWriter);
    }

    fn deinit() void {
        lineBuffer.deinit();
        initialized = false;
    }

    fn writeBuffered(fields: *const [][]const u8, isHeader: bool) !void {
        lineBuffer.clearRetainingCapacity();
        var buffer: [4096]u8 = undefined;
        var writer_adapter = lineBuffer.writer().adaptToNewApi(&buffer);
        var writer = &writer_adapter.new_interface;
        if (isHeader) {
            try formatWriter.writeHeader(writer, fields);
        } else {
            try formatWriter.writeData(writer, fields);
        }
        try writer.flush();
    }

    fn getBuffer() []u8 {
        return lineBuffer.items;
    }

    fn writeDirect(fields: *const [][]const u8, isHeader: bool) !void {
        if (isHeader) {
            try formatWriter.writeHeader(outputWriter, fields);
        } else {
            try formatWriter.writeData(outputWriter, fields);
        }
    }

    fn commitBuffer() !void {
        _ = try outputWriter.write(lineBuffer.items);
    }
};

fn proccessFile(fieldReader: anytype, outputFile: std.fs.File) !void {
    const header = try processHeader(fieldReader);

    if (options.count) {
        try proccessFileCount(fieldReader, outputFile, header);
    } else if (options.unique) {
        try proccessFileUnique(fieldReader, outputFile, header);
    } else {
        try proccessFileDirect(fieldReader, outputFile, header);
    }
}

fn processHeader(fieldReader: anytype) !?std.array_list.Managed([]const u8) {
    if (options.fileHeader) {
        options.header = try fieldReader.readLine();
    }

    try options.calculateFieldIndices();
    try fieldReader.setSelectedIndices(options.selectedIndices);
    fieldReader.setExcludedIndices(options.excludedIndices);
    fieldReader.setFilters(options.filters);
    fieldReader.setFiltersOut(options.filtersOut);

    if (options.header != null and options.outputHeader) {
        var header = std.array_list.Managed([]const u8).init(allocator);
        if (try fieldReader.getSelectedFields(options.header.?)) |selectedHeader| {
            for (selectedHeader) |field| {
                try header.append(field);
            }

            if (options.count) {
                try header.append("Count");
            }
        }
        return header;
    }
    return null;
}

pub fn bigBufferedWriter(underlying_stream: anytype) std.io.BufferedWriter(1024 * 16, @TypeOf(underlying_stream)) {
    return .{ .unbuffered_writer = underlying_stream };
}

fn proccessFileDirect(fieldReader: anytype, outputFile: std.fs.File, header: ?std.array_list.Managed([]const u8)) !void {
    var fieldWidths = try FieldWidths.init(options.outputFormat, options.fileHeader, options.header, fieldReader, allocator);
    defer fieldWidths.deinit();

    var buffer: [4096]u8 = undefined;
    var writer = outputFile.writer(&buffer);
    try OutputWriter.init(&writer.interface, fieldWidths);
    defer OutputWriter.deinit();

    if (header != null and options.outputHeader) {
        try OutputWriter.writeDirect(&header.?.items, true);
    }

    if (options.outputLimit != 0) {
        var linesWritten: usize = 0;
        while (try fieldReader.readLine()) |fields| {
            try OutputWriter.writeDirect(&fields, false);
            linesWritten += 1;
            if (options.outputLimit != 0 and linesWritten >= options.outputLimit) {
                break;
            }
        }
    } else {
        while (try fieldReader.readLine()) |fields| {
            try OutputWriter.writeDirect(&fields, false);
        }
    }

    try OutputWriter.end();
    try writer.interface.flush();
}

fn listHeader() !void {
    if (options.header) |header| {
        try printHeader(header);
    } else {
        const fileName = options.inputFiles.items[0];
        var file = std.fs.cwd().openFile(fileName, .{}) catch |err| ExitCode.couldNotOpenInputFile.printErrorAndExit(.{ fileName, err });
        defer file.close();

        var fieldReader = try initFileReader(&file);
        defer fieldReader.deinit();

        if (try fieldReader.readLine()) |header| {
            try printHeader(header);
        } else {
            ExitCode.couldNotReadHeader.printErrorAndExit(.{fileName});
        }
    }
}

fn printHeader(header: [][]const u8) !void {
    var writer = stdout.getWriter();
    defer stdout.flush();

    for (header) |field| {
        _ = try writer.write(field);
        _ = try writer.write("\n");
    }
}

fn proccessFileUnique(fieldReader: anytype, outputFile: std.fs.File, outputHeader: ?std.array_list.Managed([]const u8)) !void {
    var uniqueAgregator = UniqueAgregator.init(allocator);
    defer uniqueAgregator.deinit();

    var fieldWidths = try FieldWidths.init(options.outputFormat, options.fileHeader, options.header, fieldReader, allocator);
    defer fieldWidths.deinit();

    var buffer: [4096]u8 = undefined;
    var writer = outputFile.writer(&buffer);
    try OutputWriter.init(&writer.interface, fieldWidths);
    defer OutputWriter.deinit();

    if (outputHeader) |header| {
        try OutputWriter.writeDirect(&header.items, true);
    }

    var linesWritten: usize = 0;
    while (try fieldReader.readLine()) |fields| {
        try OutputWriter.writeBuffered(&fields, false);

        if (try uniqueAgregator.isNew(OutputWriter.getBuffer())) {
            try OutputWriter.commitBuffer();
            linesWritten += 1;
        }
        if (options.outputLimit != 0 and linesWritten >= options.outputLimit) {
            break;
        }
    }

    try OutputWriter.end();
    try writer.interface.flush();
}

fn proccessFileCount(fieldReader: anytype, outputFile: std.fs.File, outputHeader: ?std.array_list.Managed([]const u8)) !void {
    var countAggregator = try CountAggregator.init(allocator);

    while (try fieldReader.readLine()) |fields| {
        try countAggregator.add(&fields);
    }

    var fieldWidths = try FieldWidths.initCountAggregated(options.outputFormat, outputHeader, &countAggregator, allocator);
    defer fieldWidths.deinit();

    var buffer: [4096]u8 = undefined;
    var writer = outputFile.writer(&buffer);
    try OutputWriter.init(&writer.interface, fieldWidths);
    defer OutputWriter.deinit();

    if (outputHeader) |header| {
        try OutputWriter.writeDirect(&header.items, true);
    }

    var linesWritten: usize = 0;
    var iterator = countAggregator.countMap.iterator();
    while (iterator.next()) |entry| {
        try OutputWriter.writeDirect(try entry.value_ptr.get(), false);
        linesWritten += 1;
        if (options.outputLimit != 0 and linesWritten >= options.outputLimit) {
            break;
        }
    }

    try OutputWriter.end();
    try writer.interface.flush();
}

test {
    std.testing.refAllDecls(@This());
}
