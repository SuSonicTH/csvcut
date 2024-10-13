const std = @import("std");
const Options = @import("options.zig").Options;
const OutputFormat = @import("options.zig").OutputFormat;

const version = "csvcut v0.1\n\n";

const Argument = enum {
    @"--help",
    @"-v",
    @"--version",
    @"-s",
    @"--separator",
    @"-q",
    @"--quoute",
    @"-h",
    @"--header",
    @"-n",
    @"--noHeader",
    @"-S",
    @"--outputSeparator",
    @"-Q",
    @"--outputQuoute",
    @"-N",
    @"--outputNoHeader",
    @"-I",
    @"--include",
    @"-E",
    @"--exclude",
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
    @"--inputLimit",
    @"--outputLimit",
    @"--lengths",
    @"--extraLF",
    @"--extraCRLF",
};

const Separator = enum {
    comma,
    @",",
    semicolon,
    @";",
    pipe,
    @"|",
    tab,
    @"\t",
};

const Quoute = enum {
    no,
    single,
    @"'",
    double,
    @"\"",
};

const ExitCode = enum(u8) {
    OK,
    noArgumentError,
    noInputError,
    stdinOrFileError,
    unknownArgumentError,
    argumentWithUnknownValueError,
    argumentValueMissingError,
    includeAndExcludeTogether,

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
            .includeAndExcludeTogether => return "--include and --exclude cannot be used together",
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
                    .@"-s", .@"--separator" => options.inputSeparator = try getSeparator(args, index, arg),
                    .@"-q", .@"--quoute" => options.inputQuoute = try getQuoute(args, index, arg),
                    .@"-S", .@"--outputSeparator" => options.outputSeparator = try getSeparator(args, index, arg),
                    .@"-Q", .@"--outputQuoute" => options.outputQuoute = try getQuoute(args, index, arg),
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
                        options.fileHeader = false;
                        skipNext();
                    },
                    .@"-n", .@"--noHeader" => options.fileHeader = false,
                    .@"-N", .@"--outputNoHeader" => options.outputHeader = false,
                    .@"-I", .@"--include" => {
                        options.addInclude(try argumentValue(args, index, arg)) catch |err| {
                            if (err == error.IncludeAndExcludeTogether) {
                                try ExitCode.includeAndExcludeTogether.printErrorAndExit(.{});
                            }
                            return err;
                        };
                        skipNext();
                    },
                    .@"-E", .@"--exclude" => {
                        options.addExclude(try argumentValue(args, index, arg)) catch |err| {
                            if (err == error.IncludeAndExcludeTogether) {
                                try ExitCode.includeAndExcludeTogether.printErrorAndExit(.{});
                            }
                            return err;
                        };
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
                    .@"--inputLimit" => {
                        try options.setInputLimit(try argumentValue(args, index, arg));
                        skipNext();
                    },
                    .@"--outputLimit" => {
                        try options.setOutputLimit(try argumentValue(args, index, arg));
                        skipNext();
                    },
                    .@"--lengths" => {
                        try options.setLenghts(try argumentValue(args, index, arg));
                        skipNext();
                    },
                    .@"--extraLF" => options.extraLineEnd = 1,
                    .@"--extraCRLF" => options.extraLineEnd = 2,
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

    fn getSeparator(args: [][]u8, index: usize, arg: []const u8) ![1]u8 {
        const sep = try argumentValue(args, index, arg);
        skipNext();
        switch (std.meta.stringToEnum(Separator, sep) orelse {
            try ExitCode.argumentWithUnknownValueError.printErrorAndExit(.{ arg, sep });
        }) {
            .comma, .@"," => return .{','},
            .semicolon, .@";" => return .{';'},
            .tab, .@"\t" => return .{'\t'},
            .pipe, .@"|" => return .{'|'},
        }
    }

    fn getQuoute(args: [][]u8, index: usize, arg: []const u8) !?[1]u8 {
        const quoute = try argumentValue(args, index, arg);
        skipNext();
        switch (std.meta.stringToEnum(Quoute, quoute) orelse {
            try ExitCode.argumentWithUnknownValueError.printErrorAndExit(.{ arg, quoute });
        }) {
            .no => return null,
            .single, .@"'" => return .{'\''},
            .double, .@"\"" => return .{'"'},
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
