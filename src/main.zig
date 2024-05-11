const std = @import("std");
const csvline = @import("csvline.zig");

const version = "csvcut v0.1\n\n";

const Options = struct {
    input_separator: u8 = ',',
    input_quoute: ?u8 = null,
    output_separator: u8 = ',',
    output_quoute: ?u8 = null,
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

    for (args[1..]) |arg| {
        if (arg[0] == '-' and arg.len > 1) {
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

                .@"-T", .@"--outputTab" => options.output_separator = '\t',
                .@"-C", .@"--outputComma" => options.output_separator = ',',
                .@"-S", .@"--outputSemicolon" => options.output_separator = ';',
                .@"-P", .@"--outputPipe" => options.output_separator = '|',
                .@"-D", .@"--outputDoubleQuoute" => options.output_quoute = '"',
                .@"-Q", .@"--outputquoute" => options.output_quoute = '\'',
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
    var buffered_reader = std.io.bufferedReader(reader);
    var buffered_writer = std.io.bufferedWriter(writer);
    var buffer: [1024]u8 = undefined;
    var parser = try csvline.Parser.init(allocator, .{ .separator = options.input_separator, .quoute = options.input_quoute });
    defer parser.free();

    const outputSeparator: [1]u8 = .{options.output_separator};

    var outputQuoute: [1]u8 = undefined;
    if (options.output_quoute != null) {
        outputQuoute[0] = options.output_quoute.?;
    }

    while (try buffered_reader.reader().readUntilDelimiterOrEof(&buffer, '\n')) |line| {
        for (try parser.parse(line), 0..) |field, index| {
            if (options.output_quoute != null) {
                _ = try buffered_writer.write(&outputQuoute);
            }
            _ = try buffered_writer.write(field);
            if (options.output_quoute != null) {
                _ = try buffered_writer.write(&outputQuoute);
            }
            if (index < line.len) {
                _ = try buffered_writer.write(&outputSeparator);
            }
        }
        _ = try buffered_writer.write("\n");
    }

    try buffered_writer.flush();
}
