const std = @import("std");
const Self = @This();

selectionIndices: ?[]usize = null,
allocator: std.mem.Allocator = undefined,
selected: [][]const u8 = undefined,

pub fn init(selectionIndices: ?[]usize, allocator: std.mem.Allocator) !Self {
    if (selectionIndices) |indices| {
        return .{
            .allocator = allocator,
            .selectionIndices = selectionIndices,
            .selected = try allocator.alloc([]u8, indices.len),
        };
    } else {
        return .{};
    }
}

pub fn deinit(self: Self) void {
    if (self.selectionIndices != null) {
        self.allocator.free(self.selected);
    }
}

pub inline fn get(self: Self, fields: *const [][]const u8) *const [][]const u8 {
    if (self.selectionIndices) |indices| {
        for (indices, 0..) |field, index| {
            self.selected[index] = fields.*[field];
        }
        return &self.selected;
    } else {
        return fields;
    }
}
