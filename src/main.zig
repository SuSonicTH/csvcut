const std = @import("std");
const CsvLine = @import("CsvLine").CsvLine;
const Options = @import("options.zig").Options;
const Filter = @import("options.zig").Filter;
const ArgumentParser = @import("arguments.zig").Parser;
const Utf8Output = @import("Utf8Output.zig");
const FormatWriter = @import("FormatWriter.zig").FormatWriter;
const FieldWidths = @import("FieldWidths.zig");
const CsvReader = @import("CsvReader.zig");
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
    const stderr = std.io.getStdErr().writer();

    var outputFile: std.fs.File = undefined;
    if (options.outputName) |outputName| {
        outputFile = std.fs.cwd().createFile(outputName, .{}) catch |err| ExitCode.couldNotOpenOutputFile.printErrorAndExit(.{ outputName, err });
    } else {
        outputFile = std.io.getStdOut();
    }
    defer outputFile.close();

    for (options.inputFiles.items) |fileName| {
        var file = std.fs.cwd().openFile(fileName, .{}) catch |err| ExitCode.couldNotOpenInputFile.printErrorAndExit(.{ fileName, err });
        defer file.close();

        if (options.lengths) |lengths| {
            //re-implement
            _ = lengths;
            return error.FieldWidthsNotReImplementedYet;
        } else {
            var csvReader = try CsvReader.init(&file, options.inputLimit, options.skipLine, .{ .separator = options.inputSeparator[0], .trim = options.trim, .quoute = if (options.inputQuoute) |quote| quote[0] else null }, allocator);
            defer csvReader.deinit();
            try proccessFile(&csvReader, outputFile);
        }
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

fn processHeader(fieldReader: anytype) !?std.ArrayList([]const u8) {
    try options.calculateFieldIndices();
    try fieldReader.setSelectedIndices(options.selectedIndices);
    fieldReader.setExcludedIndices(options.excludedIndices);
    fieldReader.setFilters(options.filters);
    fieldReader.setFiltersOut(options.filtersOut);

    if (options.fileHeader) {
        options.header = try fieldReader.readLine();
    }

    if (options.header != null and options.outputHeader) {
        var header = std.ArrayList([]const u8).init(allocator);
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

fn proccessFileDirect(fieldReader: anytype, outputFile: std.fs.File, header: ?std.ArrayList([]const u8)) !void {
    var fieldWidths = try FieldWidths.init(options.outputFormat, options.fileHeader, options.header, fieldReader, allocator);
    defer fieldWidths.deinit();

    var bufferedWriter = bigBufferedWriter(outputFile.writer());
    try OutputWriter.init(bufferedWriter.writer().any(), fieldWidths);
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
    try bufferedWriter.flush();
}

fn listHeader() !void {
    if (options.header) |header| {
        try printHeader(header);
    } else {
        //try ArgumentParser.validateArguments(&options);
        //
        //const fileName = options.inputFiles.items[0];
        //var file = std.fs.cwd().openFile(fileName, .{}) catch |err| ExitCode.couldNotOpenInputFile.printErrorAndExit(.{ fileName, err });
        //defer file.close();
        //
        //var fieldReader: FieldReader = try FieldReader.initCsvFile(&file, options.inputLimit, options.skipLine, .{ .separator = options.inputSeparator[0], .trim = options.trim, .quoute = if (options.inputQuoute) |quote| quote[0] else null }, allocator);
        //defer fieldReader.deinit();
        //
        //if (try fieldReader.readLine()) |header| {
        //    try printHeader(header);
        //} else {
        //    ExitCode.couldNotReadHeader.printErrorAndExit(.{fileName});
        //}
        return error.listHeaderNotYetImplemented;
    }
}

fn printHeader(header: [][]const u8) !void {
    const out = std.io.getStdOut();
    for (header) |field| {
        _ = try out.write(field);
        _ = try out.write("\n");
    }
}

fn proccessFileUnique(fieldReader: anytype, outputFile: std.fs.File, outputHeader: ?std.ArrayList([]const u8)) !void {
    var uniqueAgregator = UniqueAgregator.init(allocator);
    defer uniqueAgregator.deinit();

    var fieldWidths = try FieldWidths.init(options.outputFormat, options.fileHeader, options.header, fieldReader, allocator);
    defer fieldWidths.deinit();

    var bufferedWriter = std.io.bufferedWriter(outputFile.writer());
    try OutputWriter.init(bufferedWriter.writer().any(), fieldWidths);
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
    try bufferedWriter.flush();
}

fn proccessFileCount(fieldReader: anytype, outputFile: std.fs.File, outputHeader: ?std.ArrayList([]const u8)) !void {
    var countAggregator = try CountAggregator.init(allocator);

    while (try fieldReader.readLine()) |fields| {
        try countAggregator.add(&fields);
    }

    var fieldWidths = try FieldWidths.initCountAggregated(options.outputFormat, outputHeader, &countAggregator, allocator);
    defer fieldWidths.deinit();

    var bufferedWriter = std.io.bufferedWriter(outputFile.writer());
    try OutputWriter.init(bufferedWriter.writer().any(), fieldWidths);
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
    try bufferedWriter.flush();
}

test {
    std.testing.refAllDecls(@This());
}
