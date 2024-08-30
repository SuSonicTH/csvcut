const std = @import("std");
const Options = @import("options.zig").Options;
const OutputFormat = @import("options.zig").OutputFormat;

const version = "csvcut v0.1\n\n";

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
    @"--noQuote",
    @"-h",
    @"--header",
    @"-n",
    @"--noHeader",
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
    @"--outputNoQuote",
    @"-N",
    @"--outputNoHeader",
    @"-F",
    @"--fields",
    @"-I",
    @"--indices",
    @"--trim",
    @"--filter",
    @"--format",
    @"-l",
    @"--listHeader",
    @"--stdin",
};

pub fn parse(options: *Options, args: [][]u8) !void {
    if (args.len == 1) {
        try noArgumentError();
    }

    var skip_next: bool = false;
    for (args[1..], 1..) |arg, index| {
        if (skip_next) {
            skip_next = false;
            continue;
        }
        if (arg[0] == '-') {
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
                .@"--noQuote" => options.input_quoute = null,
                .@"-T", .@"--outputTab" => options.output_separator = .{'\t'},
                .@"-C", .@"--outputComma" => options.output_separator = .{','},
                .@"-S", .@"--outputSemicolon" => options.output_separator = .{';'},
                .@"-P", .@"--outputPipe" => options.output_separator = .{'|'},
                .@"-D", .@"--outputDoubleQuoute" => options.output_quoute = .{'"'},
                .@"-Q", .@"--outputQuoute" => options.output_quoute = .{'\''},
                .@"--outputNoQuote" => options.output_quoute = null,
                .@"--trim" => options.trim = true,
                .@"-l", .@"--listHeader" => options.listHeader = true,
                .@"--format" => {
                    if (std.meta.stringToEnum(OutputFormat, args[index + 1])) |outputFormat| {
                        options.outputFormat = outputFormat;
                    } else {
                        try argumentValueError(arg, args[index + 1]);
                    }
                    skip_next = true;
                },
                .@"-h", .@"--header" => {
                    try options.setHeader(args[index + 1]); //todo: check if there are more arguments -> error if not
                    skip_next = true;
                },
                .@"-n", .@"--noHeader" => options.fileHeader = false,
                .@"-N", .@"--outputNoHeader" => options.outputHeader = false,
                .@"-F", .@"--fields" => {
                    try options.addIndex(.name, args[index + 1]); //todo: check if there are more arguments -> error if not
                    skip_next = true;
                },
                .@"-I", .@"--indices" => {
                    try options.addIndex(.index, args[index + 1]); //todo: check if there are more arguments -> error if not
                    skip_next = true;
                },
                .@"--filter" => {
                    try options.addFilter(args[index + 1]);
                    skip_next = true;
                },
                .@"--stdin" => options.useStdin = true,
            }
        } else {
            try options.inputFiles.append(arg);
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
    std.process.exit(2);
}

fn argumentValueError(arg: []u8, val: []u8) !noreturn {
    try printUsage(std.io.getStdErr(), false);
    std.log.err("value '{s}' for argument '{s}' is unknown\n", .{ val, arg });
    std.process.exit(3);
}
