const std = @import("std");

pub const version = "csvcut v0.1";

pub const ExitCode = enum(u8) {
    OK,
    noArgumentError,
    noInputError,
    stdinOrFileError,
    unknownArgumentError,
    argumentWithUnknownValueError,
    argumentValueMissingError,
    includeAndExcludeTogether,
    countAndUniqueAreExclusive,
    extraLfWithoutLength,

    couldNotOpenInputFile,
    couldNotOpenOutputFile,
    couldNotReadHeader,
    outOfMemory,
    genericError = 255,

    const useStdinMessage = "\n          use --stdin if you want to process standard input";

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
            .extraLfWithoutLength => return "--extraLF and --extraCRLF are only used for fixed field processing with --lengths",
            .countAndUniqueAreExclusive => return "--count and --unique are exclusive, use either, not both at the same time",

            .couldNotOpenInputFile => return "could not open input file '{s}' reason: {!}",
            .couldNotOpenOutputFile => return "could not open output file '{s}' reason: {!}",
            .couldNotReadHeader => return "could not read header from file '{s}'",
            .outOfMemory => return "could not allocate more memory",
            .genericError => return "unhandled error '{any}'",
        }
    }

    pub fn exit(self: ExitCode) !noreturn {
        std.process.exit(self.code());
    }

    pub fn printExitCodes() !void {
        const writer = std.io.getStdOut().writer();
        _ = try writer.print("{s}\n\nExit Codes:\n", .{version});

        inline for (std.meta.fields(ExitCode)) |exitCode| {
            try writer.print("{d}: {s}\n", .{ exitCode.value, exitCode.name });
        }
        try ExitCode.OK.exit();
    }

    fn _printErrorAndExit(comptime self: ExitCode, values: anytype) !noreturn {
        const writer = std.io.getStdErr().writer();
        _ = try writer.print("{s}\n\nError #{d}: ", .{ version, self.code() });
        _ = try writer.print(self.message(), values);
        _ = try writer.write("\n");
        _ = try self.exit();
    }

    pub fn printErrorAndExit(comptime self: ExitCode, values: anytype) noreturn {
        _printErrorAndExit(self, values) catch @panic("could not print error message");
    }
};
