const std = @import("std");
const escape = @import("escape.zig");
const Self = @This();

pub fn init() !Self {
    return .{};
}

pub fn start(self: *Self, writer: *std.Io.Writer) !void {
    _ = self;
    _ = writer;
}

pub fn writeHeader(self: *Self, writer: *std.Io.Writer, fields: *const [][]const u8) !void {
    try self.writeData(writer, fields);
    for (fields.*) |field| {
        _ = field;
        _ = try writer.write("| --- ");
    }
    _ = try writer.write("|\n");
}

pub fn writeData(self: *Self, writer: *std.Io.Writer, fields: *const [][]const u8) !void {
    _ = self;
    for (fields.*) |field| {
        _ = try writer.write("| ");
        _ = try writer.write(try escape.markdown(field));
        _ = try writer.write(" ");
    }
    _ = try writer.write("|\n");
}

pub fn end(self: *Self, writer: *std.Io.Writer) !void {
    _ = self;
    _ = writer;
}
