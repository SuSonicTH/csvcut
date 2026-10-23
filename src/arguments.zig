const std = @import("std");
const runtime = @import("runtime.zig");
const license = @import("license");
const Options = @import("options.zig").Options;
const OutputFormat = @import("options.zig").OutputFormat;
const readConfigFromFile = @import("config.zig").readConfigFromFile;
const ExitCode = @import("exitCode.zig").ExitCode;
const version = @import("exitCode.zig").version;

const Argument = enum {
    @"--help",
    @"-v",
    @"--version",
    @"-s",
    @"--separator",
    @"-q",
    @"--quote",
    @"-h",
    @"--header",
    @"-n",
    @"--noHeader",
    @"-S",
    @"--outputSeparator",
    @"-Q",
    @"--outputQuote",
    @"-N",
    @"--outputNoHeader",
    @"-I",
    @"--include",
    @"-E",
    @"--exclude",
    @"--trim",
    @"--filter",
    @"--filterOut",
    @"--format",
    @"-l",
    @"--listHeader",
    @"--skipLines",
    @"--exitCodes",
    @"--unique",
    @"--count",
    @"--inputLimit",
    @"--outputLimit",
    @"--lengths",
    @"--extraLF",
    @"--extraCRLF",
    @"--config",
    @"-o",
    @"--output",
    @"--time",
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

const Quote = enum {
    no,
    single,
    @"'",
    double,
    @"\"",
};

pub const Parser = struct {
    const max_config_depth: usize = 16;

    pub fn parse(options: *Options, args: [][]const u8, allocator: std.mem.Allocator) !void {
        try parseDepth(options, args, allocator, 0);
    }

    /// Parses an automatically loaded config file. Unlike the command line,
    /// an empty config file is valid.
    pub fn parseConfig(options: *Options, args: [][]const u8, allocator: std.mem.Allocator) !void {
        try parseDepth(options, args, allocator, 1);
    }

    fn parseDepth(options: *Options, args: [][]const u8, allocator: std.mem.Allocator, depth: usize) !void {
        if (depth == 0 and args.len == 1) {
            try ExitCode.noArgumentError.printErrorAndExit(.{});
        }

        var skip_next: bool = false;
        for (args[1..], 1..) |arg, index| {
            if (skip_next) {
                skip_next = false;
                continue;
            }
            if (arg.len == 0) {
                try ExitCode.emptyArgument.printErrorAndExit(.{});
            }
            if (arg[0] == '-') {
                switch (std.meta.stringToEnum(Argument, arg) orelse {
                    try ExitCode.unknownArgumentError.printErrorAndExit(.{arg});
                }) {
                    .@"--help" => try printUsage(),
                    .@"-v", .@"--version" => try printVersion(),
                    .@"-s", .@"--separator" => {
                        options.inputSeparator = try getSeparator(args, index, arg);
                        skip_next = true;
                    },
                    .@"-q", .@"--quote" => {
                        options.inputQuote = try getQuote(args, index, arg);
                        skip_next = true;
                    },
                    .@"-S", .@"--outputSeparator" => {
                        options.outputSeparator = try getSeparator(args, index, arg);
                        skip_next = true;
                    },
                    .@"-Q", .@"--outputQuote" => {
                        options.outputQuote = try getQuote(args, index, arg);
                        skip_next = true;
                    },
                    .@"--trim" => options.trim = true,
                    .@"-l", .@"--listHeader" => options.listHeader = true,
                    .@"-o", .@"--output" => {
                        options.outputName = try argumentValue(args, index, arg);
                        skip_next = true;
                    },
                    .@"--unique" => {
                        if (options.count) try ExitCode.countAndUniqueAreExclusive.printErrorAndExit(.{});
                        options.unique = true;
                    },
                    .@"--count" => {
                        if (options.unique) try ExitCode.countAndUniqueAreExclusive.printErrorAndExit(.{});
                        options.count = true;
                    },
                    .@"--format" => {
                        if (std.meta.stringToEnum(OutputFormat, try argumentValue(args, index, arg))) |outputFormat| {
                            options.outputFormat = outputFormat;
                        } else {
                            try ExitCode.argumentWithUnknownValueError.printErrorAndExit(.{ arg, try argumentValue(args, index, arg) });
                        }
                        skip_next = true;
                    },
                    .@"-h", .@"--header" => {
                        const value = try argumentValue(args, index, arg);
                        options.setHeader(value) catch |err| switch (err) {
                            error.FoundEndOfLineAfterOpeningQuote => ExitCode.invalidHeaderValue.printErrorAndExit(.{value}),
                            else => return err,
                        };
                        options.fileHeader = false;
                        skip_next = true;
                    },
                    .@"-n", .@"--noHeader" => options.fileHeader = false,
                    .@"-N", .@"--outputNoHeader" => options.outputHeader = false,
                    .@"-I", .@"--include" => {
                        const value = try argumentValue(args, index, arg);
                        if (value.len == 0) {
                            try ExitCode.emptyFieldInSelection.printErrorAndExit(.{});
                        }
                        addSelection(options, value, true) catch |err| switch (err) {
                            error.IncludeAndExcludeTogether => ExitCode.includeAndExcludeTogether.printErrorAndExit(.{}),
                            error.InvalidIndex => ExitCode.invalidFieldIndex.printErrorAndExit(.{value}),
                            error.InvalidRange => ExitCode.invalidFieldRange.printErrorAndExit(.{value}),
                            error.EmptyField => ExitCode.emptyFieldInSelection.printErrorAndExit(.{}),
                            else => return err,
                        };
                        skip_next = true;
                    },
                    .@"-E", .@"--exclude" => {
                        const value = try argumentValue(args, index, arg);
                        if (value.len == 0) {
                            try ExitCode.emptyFieldInSelection.printErrorAndExit(.{});
                        }
                        addSelection(options, value, false) catch |err| switch (err) {
                            error.IncludeAndExcludeTogether => ExitCode.includeAndExcludeTogether.printErrorAndExit(.{}),
                            error.InvalidIndex => ExitCode.invalidFieldIndex.printErrorAndExit(.{value}),
                            error.InvalidRange => ExitCode.invalidFieldRange.printErrorAndExit(.{value}),
                            error.EmptyField => ExitCode.emptyFieldInSelection.printErrorAndExit(.{}),
                            else => return err,
                        };
                        skip_next = true;
                    },
                    .@"--filter" => {
                        const value = try argumentValue(args, index, arg);
                        if (value.len == 0) {
                            try ExitCode.emptyFieldInSelection.printErrorAndExit(.{});
                        }
                        options.addFilter(value) catch |err| switch (err) {
                            error.NoEqualOrTildeInFilter => ExitCode.invalidFilter.printErrorAndExit(.{value}),
                            error.InvalidIndex => ExitCode.invalidFieldIndex.printErrorAndExit(.{value}),
                            error.InvalidRange => ExitCode.invalidFieldRange.printErrorAndExit(.{value}),
                            error.EmptyField => ExitCode.emptyFieldInSelection.printErrorAndExit(.{}),
                            else => return err,
                        };
                        skip_next = true;
                    },
                    .@"--filterOut" => {
                        const value = try argumentValue(args, index, arg);
                        if (value.len == 0) {
                            try ExitCode.emptyFieldInSelection.printErrorAndExit(.{});
                        }
                        options.addFilterOut(value) catch |err| switch (err) {
                            error.NoEqualOrTildeInFilter => ExitCode.invalidFilter.printErrorAndExit(.{value}),
                            error.InvalidIndex => ExitCode.invalidFieldIndex.printErrorAndExit(.{value}),
                            error.InvalidRange => ExitCode.invalidFieldRange.printErrorAndExit(.{value}),
                            error.EmptyField => ExitCode.emptyFieldInSelection.printErrorAndExit(.{}),
                            else => return err,
                        };
                        skip_next = true;
                    },
                    .@"--skipLines" => {
                        const value = try argumentValue(args, index, arg);
                        options.addSkipLines(value) catch |err| switch (err) {
                            error.InvalidNumber => ExitCode.invalidNumberValue.printErrorAndExit(.{ value, arg }),
                            else => return err,
                        };
                        skip_next = true;
                    },
                    .@"--exitCodes" => try ExitCode.printExitCodes(),
                    .@"--inputLimit" => {
                        const value = try argumentValue(args, index, arg);
                        options.setInputLimit(value) catch |err| switch (err) {
                            error.InvalidNumber => ExitCode.invalidNumberValue.printErrorAndExit(.{ value, arg }),
                            else => return err,
                        };
                        skip_next = true;
                    },
                    .@"--outputLimit" => {
                        const value = try argumentValue(args, index, arg);
                        options.setOutputLimit(value) catch |err| switch (err) {
                            error.InvalidNumber => ExitCode.invalidNumberValue.printErrorAndExit(.{ value, arg }),
                            else => return err,
                        };
                        skip_next = true;
                    },
                    .@"--lengths" => {
                        const value = try argumentValue(args, index, arg);
                        options.setLenghts(value) catch |err| switch (err) {
                            error.InvalidLength => ExitCode.invalidFieldLength.printErrorAndExit(.{value}),
                            else => return err,
                        };
                        skip_next = true;
                    },
                    .@"--extraLF" => options.extraLineEnd = 1,
                    .@"--extraCRLF" => options.extraLineEnd = 2,
                    .@"--config" => {
                        const value = try argumentValue(args, index, arg);
                        if (value.len == 0) {
                            try ExitCode.emptyArgument.printErrorAndExit(.{});
                        }
                        if (depth >= max_config_depth) {
                            ExitCode.configRecursion.printErrorAndExit(.{max_config_depth});
                        }
                        const defaultArguments = readConfigFromFile(runtime.io, runtime.environ, value, allocator) catch |err| {
                            ExitCode.couldNotOpenConfigFile.printErrorAndExit(.{ value, err });
                        };
                        try parseDepth(options, defaultArguments.items, allocator, depth + 1);
                        skip_next = true;
                    },
                    .@"--time" => {
                        options.time = true;
                    },
                }
            } else {
                try options.inputFiles.append(arg);
            }
        }
    }

    fn addSelection(options: *Options, value: []const u8, include: bool) !void {
        if (include) {
            try options.addInclude(value);
        } else {
            try options.addExclude(value);
        }
    }

    fn getSeparator(args: [][]const u8, index: usize, arg: []const u8) ![1]u8 {
        const sep = try argumentValue(args, index, arg);
        switch (std.meta.stringToEnum(Separator, sep) orelse {
            try ExitCode.argumentWithUnknownValueError.printErrorAndExit(.{ arg, sep });
        }) {
            .comma, .@"," => return .{','},
            .semicolon, .@";" => return .{';'},
            .tab, .@"\t" => return .{'\t'},
            .pipe, .@"|" => return .{'|'},
        }
    }

    fn getQuote(args: [][]const u8, index: usize, arg: []const u8) !?[1]u8 {
        const quote = try argumentValue(args, index, arg);
        switch (std.meta.stringToEnum(Quote, quote) orelse {
            try ExitCode.argumentWithUnknownValueError.printErrorAndExit(.{ arg, quote });
        }) {
            .no => return null,
            .single, .@"'" => return .{'\''},
            .double, .@"\"" => return .{'"'},
        }
    }

    fn argumentValue(args: [][]const u8, index: usize, argument: []const u8) ![]const u8 {
        const pos = index + 1;
        if (pos >= args.len) {
            try ExitCode.argumentValueMissingError.printErrorAndExit(.{argument});
        }
        return args[pos];
    }

    fn printUsage() !void {
        const help = @embedFile("USAGE.txt");

        var stdout_buffer: [1024]u8 = undefined;
        var stdout_writer = std.Io.File.stdout().writer(runtime.io, &stdout_buffer);
        var stdout = &stdout_writer.interface;
        try stdout.writeAll(version ++ "\n" ++ help);
        try stdout.flush();

        try ExitCode.OK.exit();
    }

    fn printVersion() !void {
        var stdout_buffer: [1024]u8 = undefined;
        var stdout_writer = std.Io.File.stdout().writer(runtime.io, &stdout_buffer);
        var stdout = &stdout_writer.interface;
        try stdout.writeAll(version ++ "\n\n" ++ license.text);
        try stdout.flush();

        try ExitCode.exit(.OK);
    }

    pub fn validateArguments(options: *Options) !void {
        if (options.lengths == null and (options.extraLineEnd > 0)) ExitCode.extraLfWithoutLength.printErrorAndExit(.{});
        if (options.inputFiles.items.len == 0) {
            if (!(options.listHeader and options.header != null)) {
                ExitCode.noInputError.printErrorAndExit(.{});
            }
        }
    }
};
