const std = @import("std");
const FieldWidths = @import("../FieldWidths.zig");
const escape = @import("escape.zig");

const Self = @This();

allocator: std.mem.Allocator,
fieldWidths: FieldWidths,
spaces: []u8 = &.{},

pub fn init(allocator: std.mem.Allocator, fieldWidths: FieldWidths) !Self {
    return .{
        .allocator = allocator,
        .fieldWidths = fieldWidths,
    };
}

pub fn start(self: *Self, writer: *std.Io.Writer) !void {
    _ = writer;
    const maxSpace = self.fieldWidths.maxSpace;

    self.spaces = try self.allocator.alloc(u8, maxSpace + 1);
    @memset(self.spaces, ' ');
}

pub fn writeHeader(self: *Self, writer: *std.Io.Writer, fields: *const [][]const u8) !void {
    for (fields.*, 0..) |field, i| {
        if (i >= self.fieldWidths.widths.len) break;
        const width = self.fieldWidths.widths[i];
        const escapedLen = escape.jiraLen(field);
        const len = if (width >= escapedLen) width - escapedLen + 1 else 1;

        try writer.writeAll("||");
        try escape.writeJira(writer, field);
        try writer.writeAll(self.spaces[0..len]);
    }
    try writer.writeAll("||\n");
}

pub fn writeData(self: *Self, writer: *std.Io.Writer, fields: *const [][]const u8) !void {
    for (fields.*, 0..) |field, i| {
        if (i >= self.fieldWidths.widths.len) break;
        const width = self.fieldWidths.widths[i];
        const escapedLen = escape.jiraLen(field);
        const len = if (width >= escapedLen) width - escapedLen + 1 else 1;

        try writer.writeAll("| ");
        try escape.writeJira(writer, field);
        try writer.writeAll(self.spaces[0..len]);
    }
    try writer.writeAll("|\n");
}

pub fn end(self: *Self, writer: *std.Io.Writer) !void {
    _ = writer;
    self.allocator.free(self.spaces);
}
