const std = @import("std");
const csvline = @import("csvline.zig");
const LineReader = @import("linereader.zig").LineReader;

const version = "csvcut v0.1\n\n";

const Options = struct {
    input_separator: u8 = ',',
    input_quoute: ?u8 = null,
    output_separator: u8 = ',',
    output_quoute: ?u8 = null,
    fields: ?[]u8 = null,
    indices: ?[]u8 = null,
};

const Arguments = enum {
    @"-h",
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
    @"--outputquoute",
    @"-N",
    @"--outputNoQuote",
    @"-F",
    @"--fields",
    @"-I",
    @"--indices",
};

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_allocator.allocator();
    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    var options = Options{};

    if (args.len == 1) {
        try noArgumentError();
    }

    var skip_next: bool = false;
    for (args[1..], 1..) |arg, index| {
        if (skip_next) {
            skip_next = false;
        } else if (arg[0] == '-' and arg.len > 1) {
            switch (std.meta.stringToEnum(Arguments, arg) orelse {
                try argumentError(arg);
            }) {
                .@"-h", .@"--help" => try printUsage(std.io.getStdOut(), true),
                .@"-v", .@"--version" => try printVersion(),

                .@"-t", .@"--tab" => options.input_separator = '\t',
                .@"-c", .@"--comma" => options.input_separator = ',',
                .@"-s", .@"--semicolon" => options.input_separator = ';',
                .@"-p", .@"--pipe" => options.input_separator = '|',
                .@"-d", .@"--doubleQuoute" => options.input_quoute = '"',
                .@"-q", .@"--quoute" => options.input_quoute = '\'',
                .@"-n", .@"--noQuote" => options.input_quoute = null,
                .@"-T", .@"--outputTab" => options.output_separator = '\t',
                .@"-C", .@"--outputComma" => options.output_separator = ',',
                .@"-S", .@"--outputSemicolon" => options.output_separator = ';',
                .@"-P", .@"--outputPipe" => options.output_separator = '|',
                .@"-D", .@"--outputDoubleQuoute" => options.output_quoute = '"',
                .@"-Q", .@"--outputquoute" => options.output_quoute = '\'',
                .@"-N", .@"--outputNoQuote" => options.output_quoute = null,
                .@"-F", .@"--fields" => {
                    options.fields = args[index + 1];
                    skip_next = true;
                },
                .@"-I", .@"--indices" => {
                    options.indices = args[index + 1];
                    skip_next = true;
                },
            }
        } else if (arg[0] == '-' and arg.len == 1) {
            try proccessFile(std.io.getStdIn().reader(), std.io.getStdOut().writer(), options, gpa);
        } else {
            try processFileByName(arg, options, gpa);
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

    try proccessFile(file.reader(), std.io.getStdOut().writer(), options, allocator);
}

fn proccessFile(reader: std.fs.File.Reader, writer: std.fs.File.Writer, options: Options, allocator: std.mem.Allocator) !void {
    var buffered_writer = std.io.bufferedWriter(writer);
    var parser = try csvline.Parser.init(allocator, .{ .separator = options.input_separator, .quoute = options.input_quoute });
    defer parser.free();

    const outputSeparator: [1]u8 = .{options.output_separator};

    var outputQuoute: [1]u8 = undefined;
    if (options.output_quoute != null) {
        outputQuoute[0] = options.output_quoute.?;
    }

    var line_reader = try LineReader.init(reader, allocator, .{});

    if (options.output_quoute == null) {
        while (try line_reader.read_line()) |line| {
            const fields = try parser.parse(line);
            _ = try buffered_writer.write(fields[0]);
            for (fields[1..]) |field| {
                _ = try buffered_writer.write(&outputSeparator);
                _ = try buffered_writer.write(field);
            }
            _ = try buffered_writer.write("\n");
        }
    } else {
        while (try line_reader.read_line()) |line| {
            for (try parser.parse(line), 0..) |field, index| {
                if (index > 0) {
                    _ = try buffered_writer.write(&outputSeparator);
                }
                if (options.output_quoute != null) {
                    _ = try buffered_writer.write(&outputQuoute);
                }
                _ = try buffered_writer.write(field);
                if (options.output_quoute != null) {
                    _ = try buffered_writer.write(&outputQuoute);
                }
            }
            _ = try buffered_writer.write("\n");
        }
    }
    try buffered_writer.flush();
}
