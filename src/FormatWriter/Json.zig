const std = @import("std");
const Self = @This();

allocator: std.mem.Allocator,
firstLine: bool = true,
header: [][]const u8 = undefined,

pub fn init(allocator: std.mem.Allocator) !Self {
    return .{
        .allocator = allocator,
    };
}

pub fn start(self: *Self, writer: *const std.io.AnyWriter) !void {
    _ = self;
    _ = try writer.write("[\n");
}

pub fn writeHeader(self: *Self, writer: *const std.io.AnyWriter, fields: *const [][]const u8) !void {
    _ = writer;
    self.header = try self.allocator.dupe([]const u8, fields.*);
}

pub fn writeData(self: *Self, writer: *const std.io.AnyWriter, fields: *const [][]const u8) !void {
    if (!self.firstLine) {
        _ = try writer.write(",\n");
    } else {
        self.firstLine = false;
    }
    _ = try writer.write("{");
    for (self.header, 0..) |name, i| {
        if (i > 0) {
            _ = try writer.write(", ");
        }
        _ = try writer.write("\"");
        _ = try writer.write(name);
        _ = try writer.write("\": \"");
        _ = try writer.write(fields.*[i]);
        _ = try writer.write("\"");
    }
    _ = try writer.write("}");
}

pub fn end(self: *Self, writer: *const std.io.AnyWriter) !void {
    _ = try writer.write("\n]\n");
    self.allocator.free(self.header);
}
