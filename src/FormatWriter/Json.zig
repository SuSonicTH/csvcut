const std = @import("std");
const escape = @import("escape.zig");
const Self = @This();

allocator: std.mem.Allocator,
firstLine: bool = true,
header: ?[][]const u8 = null,

pub fn init(allocator: std.mem.Allocator, header: ?[][]const u8) !Self {
    return .{
        .allocator = allocator,
        .header = header,
    };
}

pub fn start(self: *Self, writer: *std.Io.Writer) !void {
    _ = self;
    try writer.writeAll("[\n");
}

pub fn writeHeader(self: *Self, writer: *std.Io.Writer, fields: *const [][]const u8) !void {
    _ = writer;
    self.header = fields.*;
}

pub fn writeData(self: *Self, writer: *std.Io.Writer, fields: *const [][]const u8) !void {
    if (!self.firstLine) {
        try writer.writeAll(",\n");
    } else {
        self.firstLine = false;
    }
    try writer.writeAll("{");
    if (self.header) |header| {
        for (header, 0..) |name, i| {
            if (i > 0) {
                try writer.writeAll(", ");
            }
            try escape.writeJsonString(writer, name);
            try writer.writeAll(": ");
            if (i < fields.*.len) {
                try escape.writeJsonString(writer, fields.*[i]);
            } else {
                try writer.writeAll("\"\"");
            }
        }
    } else {
        for (fields.*, 0..) |field, i| {
            if (i > 0) {
                try writer.writeAll(", ");
            }
            _ = try writer.print("\"{d}\": ", .{i + 1});
            try escape.writeJsonString(writer, field);
        }
    }
    try writer.writeAll("}");
}

pub fn end(self: *Self, writer: *std.Io.Writer) !void {
    _ = self;
    try writer.writeAll("\n]\n");
}
