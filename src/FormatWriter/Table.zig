const std = @import("std");
const FieldWidths = @import("../FieldWidths.zig");

const Self = @This();

allocator: std.mem.Allocator,
fieldWidths: FieldWidths,
spaces: []u8 = &.{},
lineDashes: []u8 = &.{},
fieldCount: usize = 0,

pub fn init(
    allocator: std.mem.Allocator,
    fieldWidths: FieldWidths,
) !Self {
    return .{
        .allocator = allocator,
        .fieldWidths = fieldWidths,
    };
}

pub fn start(self: *Self, writer: *std.Io.Writer) !void {
    const maxSpace = self.fieldWidths.maxSpace;

    self.spaces = try self.allocator.alloc(u8, maxSpace + 1);
    @memset(self.spaces, ' ');

    self.lineDashes = try self.allocator.alloc(u8, maxSpace * 3);
    for (0..maxSpace) |i| {
        std.mem.copyForwards(u8, self.lineDashes[(i * 3)..], "─");
    }

    if (self.fieldWidths.widths.len > 0) {
        try self.writeTableLine(writer, self.fieldWidths.widths.len, "┌", "┬", "┐\n");
    }
}

pub fn writeHeader(self: *Self, writer: *std.Io.Writer, fields: *const [][]const u8) !void {
    for (fields.*, 0..) |field, i| {
        if (i >= self.fieldWidths.widths.len) break;
        const width = self.fieldWidths.widths[i];
        const len = if (width >= field.len) width - field.len else 0;
        try writer.writeAll("│");
        try writer.writeAll(field);
        try writer.writeAll(self.spaces[0..len]);
    }
    try writer.writeAll("│\n");
    try self.writeTableLine(writer, fields.len, "├", "┼", "┤\n");
    self.fieldCount = fields.len;
}

pub fn writeData(self: *Self, writer: *std.Io.Writer, fields: *const [][]const u8) !void {
    for (fields.*, 0..) |field, i| {
        if (i >= self.fieldWidths.widths.len) break;
        const width = self.fieldWidths.widths[i];
        const len = if (width >= field.len) width - field.len else 0;
        try writer.writeAll("│");
        try writer.writeAll(field);
        try writer.writeAll(self.spaces[0..len]);
    }
    try writer.writeAll("│\n");
}

pub fn end(self: *Self, writer: *std.Io.Writer) !void {
    const count = if (self.fieldCount != 0) self.fieldCount else self.fieldWidths.widths.len;
    if (count != 0) {
        try self.writeTableLine(writer, count, "└", "┴", "┘\n");
    }
    self.allocator.free(self.spaces);
    self.allocator.free(self.lineDashes);
}

inline fn writeTableLine(self: *Self, writer: *std.Io.Writer, len: usize, left: []const u8, middle: []const u8, right: []const u8) !void {
    for (0..len) |i| {
        if (i >= self.fieldWidths.widths.len) break;
        if (i == 0) {
            try writer.writeAll(left);
        } else {
            try writer.writeAll(middle);
        }
        try writer.writeAll(self.lineDashes[0 .. self.fieldWidths.widths[i] * 3]);
    }
    try writer.writeAll(right);
}
