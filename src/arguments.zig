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
    @"--exitCodes",
    @"--unique",
    @"--count",
};

const ExitCode = enum(u8) {
    OK,
    noArgumentError,
    noInputError,
    stdinOrFileError,
    unknownArgumentError,
    argumentWithUnknownValueError,
    argumentValueMissingError,

    const useStdinMessage = "\nuse --stdin if you want to process standard input";

    pub fn code(self: ExitCode) u8 {
        return @intFromEnum(self);
    }

    pub fn message(self: ExitCode) []const u8 {
        switch (self) {
            .OK => return "",
            .noArgumentError => return "no argument given, expecting at least one argument" ++ useStdinMessage,
            .noInputError => return "no input file given" ++ useStdinMessage,
            .stdinOrFileError => return "use either --stdin or input file(s) not both" ++ useStdinMessage,
            .unknownArgumentError => return "argument '{s}' is unknown",
            .argumentWithUnknownValueError => return "argument '{s}' got unknown value '{s}'",
            .argumentValueMissingError => return "value for argument '{s}' is missing",
        }
    }

    pub fn exit(self: ExitCode) !noreturn {
        std.process.exit(self.code());
    }

    fn printExitCodes() !void {
        const writer = std.io.getStdOut().writer();
        _ = try writer.write(version);
        _ = try writer.write("Exit Codes:\n");

        inline for (std.meta.fields(ExitCode)) |exitCode| {
            try std.fmt.format(writer, "{d}: {s}\n", .{ exitCode.value, exitCode.name });
        }
        try ExitCode.OK.exit();
    }

    fn printErrorAndExit(comptime self: ExitCode, values: anytype) !noreturn {
        const stdErr = std.io.getStdErr();
        try stdErr.writeAll(version);
        std.log.err(self.message(), values);
        try stdErr.writeAll("\nuse csvcut --help for argument documentation\n");
        try self.exit();
    }
};

pub const Parser = struct {
    var skip_next: bool = false;

    pub fn parse(options: *Options, args: [][]u8) !void {
        if (args.len == 1) {
            try ExitCode.noArgumentError.printErrorAndExit(.{});
        }

        for (args[1..], 1..) |arg, index| {
            if (skip_next) {
                skip_next = false;
                continue;
            }
            if (arg[0] == '-') {
                switch (std.meta.stringToEnum(Argument, arg) orelse {
                    try ExitCode.unknownArgumentError.printErrorAndExit(.{arg});
                }) {
                    .@"--help" => try printUsage(),
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
                    .@"--unique" => options.unique = true,
                    .@"--count" => options.count = true,
                    .@"--format" => {
                        if (std.meta.stringToEnum(OutputFormat, try argumentValue(args, index, arg))) |outputFormat| {
                            options.outputFormat = outputFormat;
                        } else {
                            try ExitCode.argumentWithUnknownValueError.printErrorAndExit(.{ arg, try argumentValue(args, index, arg) });
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
                    .@"--exitCodes" => try ExitCode.printExitCodes(),
                }
            } else {
                try options.inputFiles.append(arg);
            }
        }

        if (!options.useStdin and options.inputFiles.items.len == 0) {
            try ExitCode.noInputError.printErrorAndExit(.{});
        } else if (options.useStdin and options.inputFiles.items.len > 0) {
            try ExitCode.stdinOrFileError.printErrorAndExit(.{});
        }
    }

    inline fn skipNext() void {
        skip_next = true;
    }

    fn argumentValue(args: [][]u8, index: usize, argument: []const u8) ![]u8 {
        const pos = index + 1;
        if (pos >= args.len) {
            try ExitCode.argumentValueMissingError.printErrorAndExit(.{argument});
        }
        return args[pos];
    }

    fn printUsage() !void {
        const help = @embedFile("USAGE.txt");
        try std.io.getStdOut().writeAll(version ++ help);
        try ExitCode.OK.exit();
    }

    fn printVersion() !void {
        const license = @embedFile("LICENSE.txt");
        try std.io.getStdOut().writeAll(version ++ license);
    }
};
