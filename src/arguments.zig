const std = @import("std");
const Options = @import("options.zig").Options;
const OutputFormat = @import("options.zig").OutputFormat;

const version = "csvcut v0.1\n\n";

const Argument = enum {
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
    @"--skipLines",
};

const ExitCode = enum(u8) {
    OK,
    noArgumentError,
    noInputError,
    stdinOrFileError,
    argumentError,
    argumentValueError,
    argumentValueMissingError,
};

pub const Parser = struct {
    var skip_next: bool = false;

    pub fn parse(options: *Options, args: [][]u8) !void {
        if (args.len == 1) {
            try noArgumentError();
        }

        for (args[1..], 1..) |arg, index| {
            if (skip_next) {
                skip_next = false;
                continue;
            }
            if (arg[0] == '-') {
                switch (std.meta.stringToEnum(Argument, arg) orelse {
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
                        if (std.meta.stringToEnum(OutputFormat, try argumentValue(args, index, arg))) |outputFormat| {
                            options.outputFormat = outputFormat;
                        } else {
                            try argumentValueError(arg, try argumentValue(args, index, arg));
                        }
                        skipNext();
                    },
                    .@"-h", .@"--header" => {
                        try options.setHeader(try argumentValue(args, index, arg));
                        skipNext();
                    },
                    .@"-n", .@"--noHeader" => options.fileHeader = false,
                    .@"-N", .@"--outputNoHeader" => options.outputHeader = false,
                    .@"-F", .@"--fields" => {
                        try options.addIndex(.name, try argumentValue(args, index, arg));
                        skipNext();
                    },
                    .@"-I", .@"--indices" => {
                        try options.addIndex(.index, try argumentValue(args, index, arg));
                        skipNext();
                    },
                    .@"--filter" => {
                        try options.addFilter(try argumentValue(args, index, arg));
                        skipNext();
                    },
                    .@"--stdin" => options.useStdin = true,
                    .@"--skipLines" => {
                        try options.addSkipLines(try argumentValue(args, index, arg));
                        skipNext();
                    },
                }
            } else {
                try options.inputFiles.append(arg);
            }
        }

        if (!options.useStdin and options.inputFiles.items.len == 0) {
            try noInputError();
        } else if (options.useStdin and options.inputFiles.items.len > 0) {
            try stdinOrFileError();
        }
    }

    inline fn skipNext() void {
        skip_next = true;
    }

    fn argumentValue(args: [][]u8, index: usize, argument: []const u8) ![]u8 {
        const pos = index + 1;
        if (pos >= args.len) {
            try argumentValueMissingError(argument);
        }
        return args[pos];
    }

    fn printUsage(file: std.fs.File, shouldExit: bool) !void {
        const help = @embedFile("USAGE.txt");
        try file.writeAll(version ++ help);
        if (shouldExit) {}
    }

    fn printVersion() !void {
        const license = @embedFile("LICENSE.txt");
        try std.io.getStdOut().writeAll(version ++ license);
    }

    const useStdinMessage = "\nuse --stdin if you want to process standard input";

    fn noArgumentError() !noreturn {
        try printErrorAndExit("no argument given, expecting at least one argument" ++ useStdinMessage, .{}, ExitCode.noArgumentError);
    }

    fn noInputError() !noreturn {
        try printErrorAndExit("no input file given" ++ useStdinMessage, .{}, ExitCode.noInputError);
    }

    fn stdinOrFileError() !noreturn {
        try printErrorAndExit("use either --stdin or input file(s) not both" ++ useStdinMessage, .{}, ExitCode.stdinOrFileError);
    }

    fn argumentError(arg: []const u8) !noreturn {
        try printErrorAndExit("argument '{s}' is unknown\n", .{arg}, ExitCode.argumentError);
    }

    fn argumentValueError(arg: []const u8, val: []u8) !noreturn {
        try printErrorAndExit("value '{s}' for argument '{s}' is unknown\n", .{ val, arg }, ExitCode.argumentValueError);
    }

    fn argumentValueMissingError(arg: []const u8) !noreturn {
        try printErrorAndExit("value for argument '{s}' is missing\n", .{arg}, ExitCode.argumentValueMissingError);
    }

    inline fn printErrorAndExit(message: []const u8, values: anytype, exitCode: ExitCode) !noreturn {
        const stdErr = std.io.getStdErr();
        try stdErr.writeAll(version);
        std.log.err(message, values);
        try stdErr.writeAll("\nuse csvcut --help for argument documentation\n");
        std.process.exit(@intFromEnum(exitCode));
    }
};
