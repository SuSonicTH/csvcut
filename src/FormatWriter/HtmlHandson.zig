const std = @import("std");
const stdout = @import("../stdout.zig");
const Self = @This();

firstLine: bool = true,
lineCount: usize = 0,

pub fn init() !Self {
    return .{};
}

pub fn start(self: *Self, writer: *std.Io.Writer) !void {
    _ = try writer.write(@embedFile("HtmlHandsonHeader.html"));
    self.lineCount = 0;
}

pub fn writeHeader(self: *Self, writer: *std.Io.Writer, fields: *const [][]const u8) !void {
    _ = self;
    _ = try writer.write("[");
    for (fields.*, 0..) |field, i| {
        if (i > 0) {
            _ = try writer.write(", ");
        }
        _ = try writer.write("'");
        _ = try writer.write(field);
        _ = try writer.write("'");
    }
    _ = try writer.write("]\n");
    _ = try writer.write("            });\n");
    _ = try writer.write("        });\n");
    _ = try writer.write("var data = [\n");
}

pub fn writeData(self: *Self, writer: *std.Io.Writer, fields: *const [][]const u8) !void {
    if (!self.firstLine) {
        _ = try writer.write(",\n");
    } else {
        self.firstLine = false;
    }

    _ = try writer.write("[");
    for (fields.*, 0..) |field, i| {
        if (i > 0) {
            _ = try writer.write(", ");
        }
        _ = try writer.write("\"");
        _ = try writer.write(field);
        _ = try writer.write("\"");
    }
    _ = try writer.write("]");

    self.lineCount += 1;
    if (self.lineCount == 10000) {
        _ = try stdout.getErrWriter().write("Warning: using more then 10000 lines in htmlHandson output causes performance issues and possible crashes in the browser\n");
    }
}

pub fn end(self: *Self, writer: *std.Io.Writer) !void {
    _ = self;
    _ = try writer.write("\n];\n");
    _ = try writer.write(@embedFile("HtmlHandsonFooter.html"));
}
