const std = @import("std");
const csvline = @import("csvline.zig");

const version = "csvcut v0.1\n\n";

const Options = struct {
    separator: u8 = ',',
    quoute: ?u8 = null,
};

const Arguments = enum {
    @"-h",
    @"--help",
    @"-v",
    @"--version",
    @"-T",
    @"--tab",
    @"-C",
    @"--comma",
    @"-S",
    @"--semicolon",
    @"-P",
    @"--pipe",
    @"-D",
    @"--doubleQuoute",
    @"-Q",
    @"--Quoute",
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
                .@"-T", .@"--tab" => options.separator = '\t',
                .@"-C", .@"--comma" => options.separator = ',',
                .@"-S", .@"--semicolon" => options.separator = ';',
                .@"-P", .@"--pipe" => options.separator = '|',
                .@"-D", .@"--doubleQuoute" => options.quoute = '"',
                .@"-Q", .@"--Quoute" => options.quoute = '\'',
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
    var parser = try csvline.Parser.init(allocator, .{});
    defer parser.free();
    _ = options;
    std.log.debug("before\n", .{});
    while (try buffered_reader.reader().readUntilDelimiterOrEof(&buffer, '\n')) |line| {
        for (try parser.parse(line)) |field| {
            _ = try buffered_writer.write(field);
            _ = try buffered_writer.write("\t");
        }
        _ = try buffered_writer.write("\n");
    }
    try buffered_writer.flush();
}
