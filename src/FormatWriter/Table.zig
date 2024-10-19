const std = @import("std");
const FieldWidths = @import("../FieldWidths.zig");

const Self = @This();

allocator: std.mem.Allocator,
fieldWidths: FieldWidths,
spaces: []u8 = undefined,
lineDashes: []u8 = undefined,
fieldCount: usize = undefined,

pub fn init(
    allocator: std.mem.Allocator,
    fieldWidths: FieldWidths,
) !Self {
    return .{
        .allocator = allocator,
        .fieldWidths = fieldWidths,
    };
}

pub fn start(self: *Self, writer: *const std.io.AnyWriter) !void {
    _ = writer;
    const maxSpace = self.fieldWidths.maxSpace;

    self.spaces = try self.allocator.alloc(u8, maxSpace + 1);
    @memset(self.spaces, ' ');

    self.lineDashes = try self.allocator.alloc(u8, maxSpace * 3);
    for (0..maxSpace) |i| {
        std.mem.copyForwards(u8, self.lineDashes[(i * 3)..], "─");
    }
}

pub fn writeHeader(self: *Self, writer: *const std.io.AnyWriter, fields: *const [][]const u8) !void {
    try self.writeTableLine(writer, fields.len, "┌", "┬", "┐\n");
    for (fields.*, 0..) |field, i| {
        const len = self.fieldWidths.widths[i] - field.len;
        _ = try writer.write("│");
        _ = try writer.write(field);
        _ = try writer.write(self.spaces[0..len]);
    }
    _ = try writer.write("│\n");
    try self.writeTableLine(writer, fields.len, "├", "┼", "┤\n");
    self.fieldCount = fields.len;
}

pub fn writeData(self: *Self, writer: *const std.io.AnyWriter, fields: *const [][]const u8) !void {
    for (fields.*, 0..) |field, i| {
        const len = self.fieldWidths.widths[i] - field.len;
        _ = try writer.write("│");
        _ = try writer.write(field);
        _ = try writer.write(self.spaces[0..len]);
    }
    _ = try writer.write("│\n");
}

pub fn end(self: *Self, writer: *const std.io.AnyWriter) !void {
    try self.writeTableLine(writer, self.fieldCount, "└", "┴", "┘\n");
    self.allocator.free(self.spaces);
    self.allocator.free(self.lineDashes);
}

inline fn writeTableLine(self: *Self, writer: *const std.io.AnyWriter, len: usize, left: []const u8, middle: []const u8, right: []const u8) !void {
    for (0..len) |i| {
        if (i == 0) {
            _ = try writer.write(left);
        } else {
            _ = try writer.write(middle);
        }
        _ = try writer.write(self.lineDashes[0 .. self.fieldWidths.widths[i] * 3]);
    }
    _ = try writer.write(right);
}
