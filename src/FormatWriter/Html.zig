const std = @import("std");
const Self = @This();

pub const Options = struct {};

options: Options,
lineCount: usize = 0,

pub fn init(options: Options) !Self {
    return .{
        .options = options,
    };
}

pub fn start(self: *Self, writer: *std.Io.Writer) !void {
    _ = self;
    _ = try writer.write("<html><body>\n");
    _ = try writer.write("<style>\n");
    _ = try writer.write(@embedFile("HtmlTable.css"));
    _ = try writer.write("\n</style>\n");
    _ = try writer.write("<table class=\"styled-table\">\n");
}

pub fn writeHeader(self: *Self, writer: *std.Io.Writer, fields: *const [][]const u8) !void {
    _ = self;
    _ = try writer.write("<thead><tr>");
    for (fields.*) |field| {
        _ = try writer.write("<th>");
        _ = try writer.write(field);
        _ = try writer.write("</th>");
    }
    _ = try writer.write("</tr></thead>\n");
    _ = try writer.write("<tbody>");
}

pub fn writeData(self: *Self, writer: *std.Io.Writer, fields: *const [][]const u8) !void {
    _ = try writer.write("<tr>");
    for (fields.*) |field| {
        _ = try writer.write("<td>");
        _ = try writer.write(field);
        _ = try writer.write("</td>");
    }
    _ = try writer.write("</tr>\n");

    self.lineCount += 1;
    if (self.lineCount == 50000) {
        var stderr_buffer: [1024]u8 = undefined;
        var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
        var stderr = &stderr_writer.interface;
        _ = try stderr.write("Warning: using more then 50000 lines in html output causes performance issues and possible crashes in the browser\n");
        try stderr.flush();
    }
}

pub fn end(self: *Self, writer: *std.Io.Writer) !void {
    _ = self;
    _ = try writer.write("</tbody></table></body></html>\n");
}
