const std = @import("std");
const Self = @This();

pub const Options = struct {
    separator: [1]u8 = .{','},
    lineEnding: [1]u8 = .{'\n'},
    quoute: ?[1]u8 = null,
};

options: Options,

pub fn init(options: Options) !Self {
    return .{
        .options = options,
    };
}

pub fn start(self: *Self, writer: *std.Io.Writer) !void {
    _ = self;
    _ = writer;
}

pub fn writeHeader(self: *Self, writer: *std.Io.Writer, fields: *const [][]const u8) !void {
    try self.writeData(writer, fields);
}

pub fn writeData(self: *Self, writer: *std.Io.Writer, fields: *const [][]const u8) !void {
    for (fields.*, 0..) |field, index| {
        if (index > 0) {
            _ = try writer.write(&self.options.separator);
        }
        if (self.options.quoute != null) {
            _ = try writer.write(&self.options.quoute.?);
        }
        _ = try writer.write(field);
        if (self.options.quoute != null) {
            _ = try writer.write(&self.options.quoute.?);
        }
    }
    _ = try writer.write("\n");
}

pub fn end(self: *Self, writer: *std.Io.Writer) !void {
    _ = self;
    _ = writer;
}
