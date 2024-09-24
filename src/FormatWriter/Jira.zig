const std = @import("std");
const FieldWidths = @import("../FieldWidths.zig");
const escape = @import("escape.zig");

const Self = @This();

pub const Options = struct {
    fieldWidths: FieldWidths,
    allocator: std.mem.Allocator,
};

options: Options,
spaces: []u8 = undefined,
dashes: []u8 = undefined,

pub fn init(options: Options) !Self {
    return .{
        .options = options,
    };
}

pub fn start(self: *Self, writer: *const std.io.AnyWriter) !void {
    _ = writer;
    const maxSpace = self.options.fieldWidths.maxSpace;

    self.spaces = try self.options.allocator.alloc(u8, maxSpace + 1);
    @memset(self.spaces, ' ');

    self.dashes = try self.options.allocator.alloc(u8, maxSpace);
    @memset(self.dashes, '-');
}

pub fn writeHeader(self: *Self, writer: *const std.io.AnyWriter, fields: *const [][]const u8) !void {
    for (fields.*, 0..) |field, i| {
        const escaped = try escape.jira(field);
        const len = self.options.fieldWidths.widths[i] - escaped.len + 1;

        _ = try writer.write("||");
        _ = try writer.write(escaped);
        _ = try writer.write(self.spaces[0..len]);
    }
    _ = try writer.write("||\n");
}

pub fn writeData(self: *Self, writer: *const std.io.AnyWriter, fields: *const [][]const u8) !void {
    for (fields.*, 0..) |field, i| {
        const escaped = try escape.jira(field);
        const len = self.options.fieldWidths.widths[i] - escaped.len + 1;

        _ = try writer.write("| ");
        _ = try writer.write(try escape.jira(field));
        _ = try writer.write(self.spaces[0..len]);
    }
    _ = try writer.write("|\n");
}

pub fn end(self: *Self, writer: *const std.io.AnyWriter) !void {
    _ = writer;
    self.options.allocator.free(self.spaces);
    self.options.allocator.free(self.dashes);
}
