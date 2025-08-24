const std = @import("std");

var stdout_buffer: [4096]u8 = undefined;
var stdout_writer: ?std.fs.File.Writer = null;
var stdout_writer_interface: *std.Io.Writer = undefined;

pub fn getWriter() *std.Io.Writer {
    if (stdout_writer == null) {
        stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        stdout_writer_interface = &stdout_writer.?.interface;
    }
    return stdout_writer_interface;
}

pub fn flush() void {
    getWriter().flush() catch @panic("could not flush to stdout");
}

var stderr_buffer: [4096]u8 = undefined;
var stderr_writer: ?std.fs.File.Writer = null;
var stderr_writer_interface: *std.Io.Writer = undefined;

pub fn getErrWriter() *std.Io.Writer {
    if (stderr_writer == null) {
        stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
        stderr_writer_interface = &stderr_writer.?.interface;
    }
    return stderr_writer_interface;
}

pub fn flushErr() void {
    getErrWriter().flush() catch @panic("could not flush to stderr");
}
