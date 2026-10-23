const std = @import("std");
const runtime = @import("runtime.zig");
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

var options: Options = undefined;

pub fn main(init: std.process.Init) !void {
    runtime.io = init.io;
    runtime.allocator = init.arena.allocator();
    runtime.environ = init.environ_map;

    _main(init) catch |err| switch (err) {
        error.OutOfMemory => ExitCode.outOfMemory.printErrorAndExit(.{}),
        else => ExitCode.genericError.printErrorAndExit(.{err}),
    };
}

fn _main(init: std.process.Init) !void {
    const timerStart = std.Io.Clock.awake.now(runtime.io);
    Utf8Output.init();
    defer Utf8Output.deinit();

    const allocator = runtime.allocator;
    const args = try init.minimal.args.toSlice(allocator);
    const arguments = try castArgs(args);
    defer allocator.free(arguments);

    options = try Options.init(allocator);
    defer options.deinit();

    if (config.readConfigFromFile(runtime.io, init.environ_map, "default.config", allocator) catch null) |defaultArguments| {
        try ArgumentParser.parse(&options, defaultArguments.items, allocator);
    }
    try ArgumentParser.parse(&options, arguments, allocator);

    if (options.listHeader) {
        try listHeader();
        return;
    }

    try ArgumentParser.validateArguments(&options);

    var outputFile: std.Io.File = undefined;
    if (options.outputName) |outputName| {
        outputFile = std.Io.Dir.cwd().createFile(runtime.io, outputName, .{}) catch |err| ExitCode.couldNotOpenOutputFile.printErrorAndExit(.{ outputName, err });
    } else {
        outputFile = std.Io.File.stdout();
    }
    defer outputFile.close(runtime.io);

    for (options.inputFiles.items) |fileName| {
        var file = std.Io.Dir.cwd().openFile(runtime.io, fileName, .{}) catch |err| ExitCode.couldNotOpenInputFile.printErrorAndExit(.{ fileName, err });
        defer file.close(runtime.io);

        var fieldReader = try initFileReader(&file);
        defer fieldReader.deinit();

        try proccessFile(&fieldReader, outputFile);
    }

    if (options.time) {
        var stderr_buffer: [1024]u8 = undefined;
        var stderr_writer = std.Io.File.stderr().writer(runtime.io, &stderr_buffer);
        var stderr = &stderr_writer.interface;

        const elapsed = timerStart.durationTo(std.Io.Clock.awake.now(runtime.io));
        const timeNeeded = @as(f32, @floatFromInt(elapsed.toNanoseconds())) / 1000000.0;
        if (timeNeeded > 1000) {
            _ = try stderr.print("time needed: {d:0.2}s\n", .{timeNeeded / 1000.0});
        } else {
            _ = try stderr.print("time needed: {d:0.2}ms\n", .{timeNeeded});
        }
        try stderr.flush();
    }
}

fn castArgs(args: []const [:0]const u8) ![][]const u8 {
    var ret = try runtime.allocator.alloc([]const u8, args.len);
    for (args, 0..) |arg, i| {
        ret[i] = arg;
    }
    return ret;
}

fn initFileReader(file: *std.Io.File) !FieldReader {
    if (options.lengths) |lengths| {
        return try FieldReader.initFixedReader(file, runtime.io, options.inputLimit, options.skipLine, lengths.items, options.trim, options.extraLineEnd, runtime.allocator);
    } else {
        return try FieldReader.initCsvReader(file, runtime.io, options.inputLimit, options.skipLine, .{ .separator = options.inputSeparator[0], .trim = options.trim, .quoute = if (options.inputQuoute) |quote| quote[0] else null }, runtime.allocator);
    }
}

const OutputWriter = struct {
    var formatWriter: FormatWriter = undefined;
    var lineBuffer: std.Io.Writer.Allocating = undefined;
    var outputWriter: *std.Io.Writer = undefined;
    var initialized = false;

    fn init(writer: *std.Io.Writer, fieldWidths: FieldWidths) !void {
        if (!initialized) {
            formatWriter = try FormatWriter.init(options, runtime.allocator, fieldWidths);
            lineBuffer = try std.Io.Writer.Allocating.initCapacity(runtime.allocator, 1024);
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
        if (isHeader) {
            try formatWriter.writeHeader(&lineBuffer.writer, fields);
        } else {
            try formatWriter.writeData(&lineBuffer.writer, fields);
        }
    }

    fn getBuffer() []u8 {
        return lineBuffer.written();
    }

    fn writeDirect(fields: *const [][]const u8, isHeader: bool) !void {
        if (isHeader) {
            try formatWriter.writeHeader(outputWriter, fields);
        } else {
            try formatWriter.writeData(outputWriter, fields);
        }
    }

    fn commitBuffer() !void {
        _ = try outputWriter.write(lineBuffer.written());
    }
};

fn proccessFile(fieldReader: anytype, outputFile: std.Io.File) !void {
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
        var header = std.array_list.Managed([]const u8).init(runtime.allocator);
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

fn proccessFileDirect(fieldReader: anytype, outputFile: std.Io.File, header: ?std.array_list.Managed([]const u8)) !void {
    var fieldWidths = try FieldWidths.init(options.outputFormat, options.fileHeader, options.header, fieldReader, runtime.allocator);
    defer fieldWidths.deinit();

    var buffer: [4096]u8 = undefined;
    var writer = outputFile.writer(runtime.io, &buffer);
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
        var file = std.Io.Dir.cwd().openFile(runtime.io, fileName, .{}) catch |err| ExitCode.couldNotOpenInputFile.printErrorAndExit(.{ fileName, err });
        defer file.close(runtime.io);

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
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(runtime.io, &stdout_buffer);
    var stdout = &stdout_writer.interface;

    for (header) |field| {
        _ = try stdout.write(field);
        _ = try stdout.write("\n");
    }
    try stdout.flush();
}

fn proccessFileUnique(fieldReader: anytype, outputFile: std.Io.File, outputHeader: ?std.array_list.Managed([]const u8)) !void {
    var uniqueAgregator = UniqueAgregator.init(runtime.allocator);
    defer uniqueAgregator.deinit();

    var fieldWidths = try FieldWidths.init(options.outputFormat, options.fileHeader, options.header, fieldReader, runtime.allocator);
    defer fieldWidths.deinit();

    var buffer: [4096]u8 = undefined;
    var writer = outputFile.writer(runtime.io, &buffer);
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

fn proccessFileCount(fieldReader: anytype, outputFile: std.Io.File, outputHeader: ?std.array_list.Managed([]const u8)) !void {
    var countAggregator = try CountAggregator.init(runtime.allocator);
    defer countAggregator.deinit();

    while (try fieldReader.readLine()) |fields| {
        try countAggregator.add(&fields);
    }

    var fieldWidths = try FieldWidths.initCountAggregated(options.outputFormat, outputHeader, &countAggregator, runtime.allocator);
    defer fieldWidths.deinit();

    var buffer: [4096]u8 = undefined;
    var writer = outputFile.writer(runtime.io, &buffer);
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
