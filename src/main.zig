const std = @import("std");
const LineReader = @import("LineReader").LineReader;
const MemMappedLineReader = @import("LineReader").MemMappedLineReader;
const CsvLine = @import("CsvLine").CsvLine;

const version = "csvcut v0.1\n\n";

const SelectionType = enum {
    name,
    index,
};

const Selection = struct {
    type: SelectionType,
    field: []const u8,
};

const OptionError = error{NoSuchField};

const Options = struct {
    csvLine: CsvLine,
    allocator: std.mem.Allocator,
    input_separator: [1]u8 = .{','},
    input_quoute: ?[1]u8 = null,
    output_separator: [1]u8 = .{','},
    output_quoute: ?[1]u8 = null,
    fileHeader: bool = true,
    header: ?[][]const u8 = null,
    selectedFields: ?std.ArrayList(Selection) = null,
    selectionIndices: ?[]usize = null,

    pub fn init(allocator: std.mem.Allocator) !Options {
        return .{
            .allocator = allocator,
            .csvLine = try CsvLine.init(allocator, .{}),
        };
    }

    pub fn deinit(self: *Options) void {
        if (self.selectedFields) |selectedFields| {
            selectedFields.deinit();
        }
        if (self.header) |header| {
            self.allocator.free(header);
        }
        self.csvLine.free();
    }

    fn setHeader(self: *Options, header: []u8) !void {
        self.header = try self.allocator.dupe([]const u8, try self.csvLine.parse(header));
        self.fileHeader = false;
    }

    fn addIndex(self: *Options, selectionType: SelectionType, fields: []u8) !void {
        if (self.selectedFields == null) {
            self.selectedFields = std.ArrayList(Selection).init(self.allocator);
        }
        for ((try self.csvLine.parse(fields))) |field| {
            try self.selectedFields.?.append(.{ .type = selectionType, .field = field });
        }
    }

    fn setSelectionIndices(self: *Options) !void {
        if (self.header == null or self.selectionIndices != null) return;
        self.selectionIndices = try self.allocator.alloc(usize, self.selectedFields.?.items.len);

        for (self.selectedFields.?.items, 0..) |item, i| {
            switch (item.type) {
                .index => self.selectionIndices.?[i] = (try std.fmt.parseInt(usize, item.field, 10)) - 1,
                .name => self.selectionIndices.?[i] = try getHeaderIndex(self, item.field),
            }
        }
    }

    fn getHeaderIndex(self: *Options, search: []const u8) OptionError!usize {
        return for (self.header.?, 0..) |field, index| {
            if (std.mem.eql(u8, field, search)) {
                break index;
            }
        } else OptionError.NoSuchField;
    }
};

const Arguments = enum {
    @"--help",
    @"-v",
    @"--version",
    @"-t",
    @"--tab",
    @"-c",
    @"--comma",
    @"-s",
    @"--semicolon",
    @"-p",
    @"--pipe",
    @"-d",
    @"--doubleQuoute",
    @"-q",
    @"--quoute",
    @"-n",
    @"--noQuote",
    @"-h",
    @"--header",
    @"-T",
    @"--outputTab",
    @"-C",
    @"--outputComma",
    @"-S",
    @"--outputSemicolon",
    @"-P",
    @"--outputPipe",
    @"-D",
    @"--outputDoubleQuoute",
    @"-Q",
    @"--outputQuoute",
    @"-N",
    @"--outputNoQuote",
    @"-F",
    @"--fields",
    @"-I",
    @"--indices",
};

const hpa = std.heap.page_allocator;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var options = try Options.init(allocator);
    defer options.deinit();

    if (args.len == 1) {
        try noArgumentError();
    }

    var skip_next: bool = false;
    for (args[1..], 1..) |arg, index| {
        if (skip_next) {
            skip_next = false;
            continue;
        }
        if (arg[0] == '-' and arg.len > 1) {
            switch (std.meta.stringToEnum(Arguments, arg) orelse {
                try argumentError(arg);
            }) {
                .@"--help" => try printUsage(std.io.getStdOut(), true),
                .@"-v", .@"--version" => try printVersion(),
                .@"-t", .@"--tab" => options.input_separator = .{'\t'},
                .@"-c", .@"--comma" => options.input_separator = .{','},
                .@"-s", .@"--semicolon" => options.input_separator = .{';'},
                .@"-p", .@"--pipe" => options.input_separator = .{'|'},
                .@"-d", .@"--doubleQuoute" => options.input_quoute = .{'"'},
                .@"-q", .@"--quoute" => options.input_quoute = .{'\''},
                .@"-n", .@"--noQuote" => options.input_quoute = null,
                .@"-T", .@"--outputTab" => options.output_separator = .{'\t'},
                .@"-C", .@"--outputComma" => options.output_separator = .{','},
                .@"-S", .@"--outputSemicolon" => options.output_separator = .{';'},
                .@"-P", .@"--outputPipe" => options.output_separator = .{'|'},
                .@"-D", .@"--outputDoubleQuoute" => options.output_quoute = .{'"'},
                .@"-Q", .@"--outputQuoute" => options.output_quoute = .{'\''},
                .@"-N", .@"--outputNoQuote" => options.output_quoute = null,
                .@"-h", .@"--header" => {
                    try options.setHeader(args[index + 1]); //todo: check if there are more arguments -> error if not
                    skip_next = true;
                },
                .@"-F", .@"--fields" => {
                    try options.addIndex(.name, args[index + 1]); //todo: check if there are more arguments -> error if not
                    skip_next = true;
                },
                .@"-I", .@"--indices" => {
                    try options.addIndex(.index, args[index + 1]); //todo: check if there are more arguments -> error if not
                    skip_next = true;
                },
            }
        } else if (arg[0] == '-' and arg.len == 1) {
            var lineReader = try LineReader.init(std.io.getStdIn().reader(), hpa, .{});
            defer lineReader.deinit();
            try proccessFile(&lineReader, std.io.getStdOut(), options, allocator);
        } else {
            try options.setSelectionIndices();
            try processFileByName(arg, options, allocator);
        }
    }
}

fn printUsage(file: std.fs.File, exit: bool) !void {
    const help = @embedFile("USAGE.txt");
    try file.writeAll(version ++ help);
    if (exit) {
        std.process.exit(0);
    }
}

fn printVersion() !void {
    const license = @embedFile("LICENSE.txt");
    try std.io.getStdOut().writeAll(version ++ license);
    std.process.exit(0);
}

fn noArgumentError() !noreturn {
    try printUsage(std.io.getStdErr(), false);
    std.log.err("no argument given, expecting at least one option", .{});
    std.process.exit(1);
}

fn argumentError(arg: []u8) !noreturn {
    try printUsage(std.io.getStdErr(), false);
    std.log.err("argument '{s}' is unknown\n", .{arg});
    std.process.exit(1);
}

fn processFileByName(name: []const u8, options: Options, allocator: std.mem.Allocator) !void {
    var path_buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const path = try std.fs.realpath(name, &path_buffer);
    const file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();
    var lineReader = try MemMappedLineReader.init(file, .{});
    //var lineReader = try LineReader.init(file.reader(), allocator, .{});
    defer lineReader.deinit();

    try proccessFile(&lineReader, std.io.getStdOut(), options, allocator);
}

fn proccessFile(lineReader: anytype, outputFile: std.fs.File, options: Options, allocator: std.mem.Allocator) !void {
    var bufferedWriter = std.io.bufferedWriter(outputFile.writer());
    var csvLine = try CsvLine.init(allocator, .{ .separator = options.input_separator[0], .quoute = if (options.input_quoute) |quote| quote[0] else null });
    defer csvLine.free();

    if (options.selectionIndices) |indices| {
        while (try lineReader.readLine()) |line| {
            const fields = try csvLine.parse(line);
            for (indices, 0..) |field, index| {
                if (index > 0) {
                    _ = try bufferedWriter.write(&options.output_separator);
                }
                if (options.output_quoute != null) {
                    _ = try bufferedWriter.write(&options.output_quoute.?);
                }
                _ = try bufferedWriter.write(fields[field]);
                if (options.output_quoute != null) {
                    _ = try bufferedWriter.write(&options.output_quoute.?);
                }
            }
            _ = try bufferedWriter.write("\n");
        }
    } else {
        while (try lineReader.readLine()) |line| {
            for (try csvLine.parse(line), 0..) |field, index| {
                if (index > 0) {
                    _ = try bufferedWriter.write(&options.output_separator);
                }
                if (options.output_quoute != null) {
                    _ = try bufferedWriter.write(&options.output_quoute.?);
                }
                _ = try bufferedWriter.write(field);
                if (options.output_quoute != null) {
                    _ = try bufferedWriter.write(&options.output_quoute.?);
                }
            }
            _ = try bufferedWriter.write("\n");
        }
    }
    try bufferedWriter.flush();
}

test {
    std.testing.refAllDecls(@This());
}
