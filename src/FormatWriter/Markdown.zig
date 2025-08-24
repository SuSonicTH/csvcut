const std = @import("std");
const FieldWidths = @import("../FieldWidths.zig");
const escape = @import("escape.zig");

const Self = @This();

allocator: std.mem.Allocator,
fieldWidths: FieldWidths,
spaces: []u8 = undefined,
dashes: []u8 = undefined,

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
    _ = writer;
    const maxSpace = self.fieldWidths.maxSpace;

    self.spaces = try self.allocator.alloc(u8, maxSpace + 1);
    @memset(self.spaces, ' ');

    self.dashes = try self.allocator.alloc(u8, maxSpace);
    @memset(self.dashes, '-');
}

pub fn writeHeader(self: *Self, writer: *std.Io.Writer, fields: *const [][]const u8) !void {
    try self.writeData(writer, fields);
    for (fields.*, 0..) |field, i| {
        _ = field;
        const width = self.fieldWidths.widths[i];
        const len = if (width < 3) 3 else width;

        _ = try writer.write("| ");
        _ = try writer.write(self.dashes[0..len]);
        _ = try writer.write(" ");
    }
    _ = try writer.write("|\n");
}

pub fn writeData(self: *Self, writer: *std.Io.Writer, fields: *const [][]const u8) !void {
    for (fields.*, 0..) |field, i| {
        const escaped = try escape.markdown(field);
        const len = self.fieldWidths.widths[i] - escaped.len + 1;

        _ = try writer.write("| ");
        _ = try writer.write(escaped);
        _ = try writer.write(self.spaces[0..len]);
    }
    _ = try writer.write("|\n");
}

pub fn end(self: *Self, writer: *std.Io.Writer) !void {
    _ = writer;
    self.allocator.free(self.spaces);
    self.allocator.free(self.dashes);
}
