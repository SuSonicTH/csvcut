const std = @import("std");
const runtime = @import("runtime.zig");
const license = @import("license");

pub const version = "csvcut v0.1.4-beta";

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
    regexCompileError,

    couldNotOpenInputFile,
    couldNotOpenOutputFile,
    couldNotReadHeader,
    outOfMemory,
    emptyArgument,
    invalidFieldIndex,
    invalidFieldRange,
    invalidFieldLength,
    invalidNumberValue,
    emptyFieldInSelection,
    noSuchField,
    noHeaderForSelection,
    invalidFilter,
    invalidHeaderValue,
    fieldIndexOutOfRange,
    couldNotOpenConfigFile,
    couldNotReadInputFile,
    configRecursion,
    invalidCsvInput,
    noColumnsSelected,
    outputIsInput,
    couldNotWriteOutput,
    genericError = 255,

    pub fn code(self: ExitCode) u8 {
        return @backingInt(self);
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
            .regexCompileError => return "invalid regex '{s}' for field '{s}'",
            .couldNotOpenInputFile => return "could not open input file '{s}' reason: {}",
            .couldNotOpenOutputFile => return "could not open output file '{s}' reason: {}",
            .couldNotReadHeader => return "could not read header from file '{s}'",
            .outOfMemory => return "could not allocate more memory",
            .emptyArgument => return "empty argument is not allowed",
            .invalidFieldIndex => return "invalid field index in '{s}', indices start at 1",
            .invalidFieldRange => return "invalid field range '{s}'",
            .invalidFieldLength => return "invalid length list '{s}', all lengths must be greater than 0",
            .invalidNumberValue => return "'{s}' is not a valid number for '{s}'",
            .emptyFieldInSelection => return "empty field in column selection",
            .noSuchField => return "field '{s}' was not found in the header",
            .noHeaderForSelection => return "selecting fields by name requires a header, use --header or select by index",
            .invalidFilter => return "invalid filter '{s}', expected field=value or field~regex",
            .invalidHeaderValue => return "invalid header '{s}'",
            .fieldIndexOutOfRange => return "field index '{d}' is out of range, the file has {d} columns",
            .couldNotOpenConfigFile => return "could not open config file '{s}' reason: {}",
            .couldNotReadInputFile => return "could not read input file '{s}' reason: {}",
            .configRecursion => return "config files are nested too deeply (limit {d})",
            .invalidCsvInput => return "invalid csv in file '{s}': unterminated quoted field",
            .noColumnsSelected => return "no columns selected",
            .outputIsInput => return "output file '{s}' is also an input file",
            .couldNotWriteOutput => return "could not write output: {}",
            .genericError => return "unhandled error '{any}'",
        }
    }

    pub fn exit(self: ExitCode) !noreturn {
        std.process.exit(self.code());
    }

    pub fn printExitCodes() !void {
        var stderr_buffer: [1024]u8 = undefined;
        var stderr_writer = std.Io.File.stderr().writer(runtime.io, &stderr_buffer);
        var stderr = &stderr_writer.interface;

        _ = try stderr.print("{s}\n\nExit Codes:\n", .{version});

        const enum_info = @typeInfo(ExitCode).@"enum";
        inline for (enum_info.field_names, enum_info.field_values) |name, value| {
            try stderr.print("{d}: {s}\n", .{ value, name });
        }
        try stderr.flush();
        try ExitCode.OK.exit();
    }

    fn _printErrorAndExit(comptime self: ExitCode, values: anytype) !noreturn {
        var stderr_buffer: [1024]u8 = undefined;
        var stderr_writer = std.Io.File.stderr().writer(runtime.io, &stderr_buffer);
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
