const std = @import("std");
const Self = @This();

firstLine: bool = true,

pub fn init() !Self {
    return .{};
}

pub fn start(self: *Self, writer: *std.Io.Writer) !void {
    _ = self;
    _ = try writer.write("[\n");
}

pub fn writeHeader(self: *Self, writer: *std.Io.Writer, fields: *const [][]const u8) !void {
    _ = self;
    _ = writer;
    _ = fields;
}

pub fn writeData(self: *Self, writer: *std.Io.Writer, fields: *const [][]const u8) !void {
    if (!self.firstLine) {
        _ = try writer.write(",\n");
    } else {
        self.firstLine = false;
    }
    _ = try writer.write("[");
    for (fields.*, 0..) |field, i| {
        if (i > 0) {
            _ = try writer.write(", ");
        }
        _ = try writer.write("\"");
        _ = try writer.write(field);
        _ = try writer.write("\"");
    }
    _ = try writer.write("]");
}

pub fn end(self: *Self, writer: *std.Io.Writer) !void {
    _ = self;
    _ = try writer.write("\n]\n");
}
