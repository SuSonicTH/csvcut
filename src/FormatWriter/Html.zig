const std = @import("std");
const Self = @This();

pub const Options = struct {};

options: Options,

pub fn init(options: Options) !Self {
    return .{
        .options = options,
    };
}

pub fn start(self: *Self, writer: *const std.io.AnyWriter) !void {
    _ = self;
    _ = try writer.write("<html><body>\n");
    _ = try writer.write("<style>\n");
    _ = try writer.write(@embedFile("HtmlTable.css"));
    _ = try writer.write("\n</style>\n");
    _ = try writer.write("<table class=\"styled-table\">\n");
}

pub fn writeHeader(self: *Self, writer: *const std.io.AnyWriter, fields: *const [][]const u8) !void {
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

pub fn writeData(self: *Self, writer: *const std.io.AnyWriter, fields: *const [][]const u8) !void {
    _ = self;
    _ = try writer.write("<tr>");
    for (fields.*) |field| {
        _ = try writer.write("<td>");
        _ = try writer.write(field);
        _ = try writer.write("</td>");
    }
    _ = try writer.write("</tr>\n");
}

pub fn end(self: *Self, writer: *const std.io.AnyWriter) !void {
    _ = self;
    _ = try writer.write("</tbody></table></body></html>\n");
}
