const std = @import("std");

pub const version = "csvcut v0.1.1-beta";

pub const ExitCode = enum(u8) {
    OK,
    noArgumentError,
    noInputError,
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

    pub fn code(self: ExitCode) u8 {
        return @intFromEnum(self);
    }

    pub fn message(self: ExitCode) []const u8 {
        switch (self) {
            .OK => return "",
            .noArgumentError => return "no argument given, expecting at least one argument",
            .noInputError => return "no input file given",
            .unknownArgumentError => return "argument '{s}' is unknown",
            .argumentWithUnknownValueError => return "argument '{s}' got unknown value '{s}'",
            .argumentValueMissingError => return "value for argument '{s}' is missing",
            .includeAndExcludeTogether => return "--include and --exclude cannot be used together",
            .extraLfWithoutLength => return "--extraLF and --extraCRLF are only used for fixed field processing with --lengths",
            .countAndUniqueAreExclusive => return "--count and --unique are exclusive, use either, not both at the same time",

            .couldNotOpenInputFile => return "could not open input file '{s}' reason: {}",
            .couldNotOpenOutputFile => return "could not open output file '{s}' reason: {}",
            .couldNotReadHeader => return "could not read header from file '{s}'",
            .outOfMemory => return "could not allocate more memory",
            .genericError => return "unhandled error '{any}'",
        }
    }

    pub fn exit(self: ExitCode) !noreturn {
        std.process.exit(self.code());
    }

    pub fn printExitCodes() !void {
        var stderr_buffer: [1024]u8 = undefined;
        var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
        var stderr = &stderr_writer.interface;

        _ = try stderr.print("{s}\n\nExit Codes:\n", .{version});

        inline for (std.meta.fields(ExitCode)) |exitCode| {
            try stderr.print("{d}: {s}\n", .{ exitCode.value, exitCode.name });
        }
        try stderr.flush();
        try ExitCode.OK.exit();
    }

    fn _printErrorAndExit(comptime self: ExitCode, values: anytype) !noreturn {
        var stderr_buffer: [1024]u8 = undefined;
        var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
        var stderr = &stderr_writer.interface;

        _ = try stderr.print("{s}\n\nError #{d}: ", .{ version, self.code() });
        _ = try stderr.print(self.message(), values);
        _ = try stderr.write("\n");
        try stderr.flush();
        _ = try self.exit();
    }

    pub fn printErrorAndExit(comptime self: ExitCode, values: anytype) noreturn {
        _printErrorAndExit(self, values) catch @panic("could not print error message");
    }
};
