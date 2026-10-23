const std = @import("std");
const runtime = @import("runtime.zig");
const Options = @import("options.zig").Options;
const ArgumentParser = @import("arguments.zig").Parser;
const Utf8Output = @import("Utf8Output.zig");
const FormatWriter = @import("FormatWriter.zig").FormatWriter;
const FieldWidths = @import("FieldWidths.zig");
const FieldReader = @import("FieldReader.zig");
const config = @import("config.zig");

const Aggregate = @import("Aggregate.zig");
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
        error.WriteFailed => ExitCode.couldNotWriteOutput.printErrorAndExit(.{err}),
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
        try ArgumentParser.parseConfig(&options, defaultArguments.items, allocator);
    }
    try ArgumentParser.parse(&options, arguments, allocator);

    try ArgumentParser.validateArguments(&options);

    if (options.listHeader) {
        try listHeader();
        return;
    }

    if (options.outputName) |outputName| {
        for (options.inputFiles.items) |inputName| {
            if (sameFileName(outputName, inputName)) {
                ExitCode.outputIsInput.printErrorAndExit(.{outputName});
            }
        }
    }

    var outputFile: std.Io.File = undefined;
    if (options.outputName) |outputName| {
        outputFile = std.Io.Dir.cwd().createFile(runtime.io, outputName, .{}) catch |err| ExitCode.couldNotOpenOutputFile.printErrorAndExit(.{ outputName, err });
    } else {
        outputFile = std.Io.File.stdout();
    }
    defer if (options.outputName != null) outputFile.close(runtime.io);

    for (options.inputFiles.items) |fileName| {
        var file = std.Io.Dir.cwd().openFile(runtime.io, fileName, .{}) catch |err| ExitCode.couldNotOpenInputFile.printErrorAndExit(.{ fileName, err });
        defer file.close(runtime.io);

        var fieldReader = initFileReader(&file) catch |err| ExitCode.couldNotReadInputFile.printErrorAndExit(.{ fileName, err });
        defer fieldReader.deinit();

        proccessFile(&fieldReader, outputFile) catch |err| switch (err) {
            error.FoundEndOfLineAfterOpeningQuote => ExitCode.invalidCsvInput.printErrorAndExit(.{fileName}),
            error.NoColumnsSelected => ExitCode.noColumnsSelected.printErrorAndExit(.{}),
            else => return err,
        };
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

fn sameFileName(a: []const u8, b: []const u8) bool {
    if (std.mem.eql(u8, a, b)) {
        return true;
    }
    const cwd = std.Io.Dir.cwd();
    const aPath = cwd.realPathFileAlloc(runtime.io, a, runtime.allocator) catch return false;
    const bPath = cwd.realPathFileAlloc(runtime.io, b, runtime.allocator) catch return false;
    return std.mem.eql(u8, aPath, bPath);
}

fn initFileReader(file: *std.Io.File) !FieldReader {
    if (options.lengths) |lengths| {
        return try FieldReader.initFixedReader(file, runtime.io, options.inputLimit, options.skipLine, lengths.items, options.trim, options.extraLineEnd, runtime.allocator);
    } else {
        return try FieldReader.initCsvReader(file, runtime.io, options.inputLimit, options.skipLine, .{ .separator = options.inputSeparator[0], .trim = options.trim, .quote = if (options.inputQuote) |quote| quote[0] else null }, runtime.allocator);
    }
}

const OutputWriter = struct {
    formatWriter: FormatWriter,
    lineBuffer: std.Io.Writer.Allocating,
    outputWriter: *std.Io.Writer,

    fn init(writer: *std.Io.Writer, fieldWidths: FieldWidths, header: ?[][]const u8) !OutputWriter {
        var self: OutputWriter = .{
            .formatWriter = try FormatWriter.init(options, runtime.allocator, fieldWidths, header),
            .lineBuffer = try std.Io.Writer.Allocating.initCapacity(runtime.allocator, 1024),
            .outputWriter = writer,
        };
        errdefer self.lineBuffer.deinit();
        try self.formatWriter.start(writer);
        return self;
    }

    fn deinit(self: *OutputWriter) void {
        self.lineBuffer.deinit();
    }

    fn writeBuffered(self: *OutputWriter, fields: *const [][]const u8, isHeader: bool) !void {
        self.lineBuffer.clearRetainingCapacity();
        if (isHeader) {
            try self.formatWriter.writeHeader(&self.lineBuffer.writer, fields);
        } else {
            try self.formatWriter.writeData(&self.lineBuffer.writer, fields);
        }
    }

    fn getBuffer(self: *OutputWriter) []u8 {
        return self.lineBuffer.written();
    }

    fn writeDirect(self: *OutputWriter, fields: *const [][]const u8, isHeader: bool) !void {
        if (isHeader) {
            try self.formatWriter.writeHeader(self.outputWriter, fields);
        } else {
            try self.formatWriter.writeData(self.outputWriter, fields);
        }
    }

    fn commitBuffer(self: *OutputWriter) !void {
        try self.outputWriter.writeAll(self.lineBuffer.written());
    }

    fn end(self: *OutputWriter) !void {
        try self.formatWriter.end(self.outputWriter);
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
        options.headerOwned = false;
        fieldReader.resetColumnCount();
    }

    try options.calculateFieldIndices();
    validateSelectedIndices();
    try fieldReader.setSelectedIndices(options.selectedIndices);
    fieldReader.setExcludedIndices(options.excludedIndices);
    fieldReader.setFilters(options.filters);
    fieldReader.setFiltersOut(options.filtersOut);

    if (options.header) |fileHeader| {
        var header = std.array_list.Managed([]const u8).init(runtime.allocator);
        if (try fieldReader.getSelectedFields(fileHeader)) |selectedHeader| {
            if (selectedHeader.len == 0) {
                if (fileHeader.len > 0 and (options.selectedIndices != null or options.excludedIndices != null)) {
                    ExitCode.noColumnsSelected.printErrorAndExit(.{});
                }
                fieldReader.resetColumnCount();
                return null;
            }
            fieldReader.setColumnCount(selectedHeader.len);
            for (selectedHeader) |field| {
                // The parser may reuse its unescape buffer while reading data,
                // so the header must own its bytes.
                try header.append(try runtime.allocator.dupe(u8, field));
            }

            if (options.count) {
                try header.append("Count");
            }
        }
        return header;
    }
    return null;
}

fn validateSelectedIndices() void {
    if (options.header) |header| {
        if (options.selectedIndices) |indices| {
            for (indices) |index| {
                if (index >= header.len) {
                    ExitCode.fieldIndexOutOfRange.printErrorAndExit(.{ index + 1, header.len });
                }
            }
        }
        if (options.excludedIndices) |excluded| {
            var iterator = excluded.keyIterator();
            while (iterator.next()) |index| {
                if (index.* >= header.len) {
                    ExitCode.fieldIndexOutOfRange.printErrorAndExit(.{ index.* + 1, header.len });
                }
            }
        }
    }
}

fn proccessFileDirect(fieldReader: anytype, outputFile: std.Io.File, header: ?std.array_list.Managed([]const u8)) !void {
    const headerFields: ?[][]const u8 = if (header) |h| h.items else null;
    var fieldWidths = try FieldWidths.init(options.outputFormat, options.fileHeader, headerFields, fieldReader, runtime.allocator);
    defer fieldWidths.deinit();

    var buffer: [4096]u8 = undefined;
    var writer = outputFile.writer(runtime.io, &buffer);
    var output = try OutputWriter.init(&writer.interface, fieldWidths, headerFields);
    defer output.deinit();

    if (options.outputHeader) {
        if (headerFields) |fields| {
            try output.writeDirect(&fields, true);
        }
    }

    if (options.outputLimit != 0) {
        var linesWritten: usize = 0;
        while (try fieldReader.readLine()) |fields| {
            try output.writeDirect(&fields, false);
            linesWritten += 1;
            if (linesWritten >= options.outputLimit) {
                break;
            }
        }
    } else {
        while (try fieldReader.readLine()) |fields| {
            try output.writeDirect(&fields, false);
        }
    }

    try output.end();
    try writer.interface.flush();
}

fn listHeader() !void {
    if (options.header) |header| {
        try printHeader(header);
    } else {
        if (options.inputFiles.items.len == 0) {
            ExitCode.noInputError.printErrorAndExit(.{});
        }
        const fileName = options.inputFiles.items[0];
        var file = std.Io.Dir.cwd().openFile(runtime.io, fileName, .{}) catch |err| ExitCode.couldNotOpenInputFile.printErrorAndExit(.{ fileName, err });
        defer file.close(runtime.io);

        var fieldReader = initFileReader(&file) catch |err| ExitCode.couldNotReadInputFile.printErrorAndExit(.{ fileName, err });
        defer fieldReader.deinit();

        const maybeHeader = fieldReader.readLine() catch |err| switch (err) {
            error.FoundEndOfLineAfterOpeningQuote => ExitCode.invalidCsvInput.printErrorAndExit(.{fileName}),
            else => return err,
        };
        if (maybeHeader) |header| {
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
        try stdout.writeAll(field);
        try stdout.writeAll("\n");
    }
    try stdout.flush();
}

fn proccessFileUnique(fieldReader: anytype, outputFile: std.Io.File, header: ?std.array_list.Managed([]const u8)) !void {
    var uniqueAgregator = UniqueAgregator.init(runtime.allocator);
    defer uniqueAgregator.deinit();

    const headerFields: ?[][]const u8 = if (header) |h| h.items else null;
    var fieldWidths = try FieldWidths.init(options.outputFormat, options.fileHeader, headerFields, fieldReader, runtime.allocator);
    defer fieldWidths.deinit();

    var buffer: [4096]u8 = undefined;
    var writer = outputFile.writer(runtime.io, &buffer);
    var output = try OutputWriter.init(&writer.interface, fieldWidths, headerFields);
    defer output.deinit();

    if (options.outputHeader) {
        if (headerFields) |fields| {
            try output.writeDirect(&fields, true);
        }
    }

    var linesWritten: usize = 0;
    while (try fieldReader.readLine()) |fields| {
        try output.writeBuffered(&fields, false);

        if (try uniqueAgregator.isNew(fields)) {
            try output.commitBuffer();
            linesWritten += 1;
        }
        if (options.outputLimit != 0 and linesWritten >= options.outputLimit) {
            break;
        }
    }

    try output.end();
    try writer.interface.flush();
}

fn proccessFileCount(fieldReader: anytype, outputFile: std.Io.File, header: ?std.array_list.Managed([]const u8)) !void {
    var countAggregator = try CountAggregator.init(runtime.allocator);
    defer countAggregator.deinit();

    while (try fieldReader.readLine()) |fields| {
        try countAggregator.add(fields);
    }

    const headerFields: ?[][]const u8 = if (header) |h| h.items else null;
    var fieldWidths = try FieldWidths.initCountAggregated(options.outputFormat, headerFields, &countAggregator, runtime.allocator);
    defer fieldWidths.deinit();

    var buffer: [4096]u8 = undefined;
    var writer = outputFile.writer(runtime.io, &buffer);
    var output = try OutputWriter.init(&writer.interface, fieldWidths, headerFields);
    defer output.deinit();

    if (options.outputHeader) {
        if (headerFields) |fields| {
            try output.writeDirect(&fields, true);
        }
    }

    var linesWritten: usize = 0;
    for (countAggregator.order.items) |key| {
        const entry = countAggregator.countMap.getEntry(key) orelse continue;
        try output.writeDirect(try entry.value_ptr.get(), false);
        linesWritten += 1;
        if (options.outputLimit != 0 and linesWritten >= options.outputLimit) {
            break;
        }
    }

    try output.end();
    try writer.interface.flush();
}

test {
    std.testing.refAllDecls(@This());
}
