const std = @import("std");
const escape = @import("escape.zig");
const Self = @This();

firstLine: bool = true,

pub fn init() !Self {
    return .{};
}

pub fn start(self: *Self, writer: *std.Io.Writer) !void {
    _ = self;
    try writer.writeAll("[\n");
}

pub fn writeHeader(self: *Self, writer: *std.Io.Writer, fields: *const [][]const u8) !void {
    _ = self;
    _ = writer;
    _ = fields;
}

pub fn writeData(self: *Self, writer: *std.Io.Writer, fields: *const [][]const u8) !void {
    if (!self.firstLine) {
        try writer.writeAll(",\n");
    } else {
        self.firstLine = false;
    }
    try writer.writeAll("[");
    for (fields.*, 0..) |field, i| {
        if (i > 0) {
            try writer.writeAll(", ");
        }
        try escape.writeJsonString(writer, field);
    }
    try writer.writeAll("]");
}

pub fn end(self: *Self, writer: *std.Io.Writer) !void {
    _ = self;
    try writer.writeAll("\n]\n");
}
