const std = @import("std");
const runtime = @import("../runtime.zig");
const escape = @import("escape.zig");
const Self = @This();

pub const Options = struct {};

options: Options,
lineCount: usize = 0,
bodyOpen: bool = false,

pub fn init(options: Options) !Self {
    return .{
        .options = options,
    };
}

pub fn start(self: *Self, writer: *std.Io.Writer) !void {
    _ = self;
    try writer.writeAll("<html><body>\n");
    try writer.writeAll("<style>\n");
    try writer.writeAll(@embedFile("HtmlTable.css"));
    try writer.writeAll("\n</style>\n");
    try writer.writeAll("<table class=\"styled-table\">\n");
}

pub fn writeHeader(self: *Self, writer: *std.Io.Writer, fields: *const [][]const u8) !void {
    try writer.writeAll("<thead><tr>");
    for (fields.*) |field| {
        try writer.writeAll("<th>");
        try escape.writeHtml(writer, field);
        try writer.writeAll("</th>");
    }
    try writer.writeAll("</tr></thead>\n");
    try writer.writeAll("<tbody>");
    self.bodyOpen = true;
}

pub fn writeData(self: *Self, writer: *std.Io.Writer, fields: *const [][]const u8) !void {
    try writer.writeAll("<tr>");
    for (fields.*) |field| {
        try writer.writeAll("<td>");
        try escape.writeHtml(writer, field);
        try writer.writeAll("</td>");
    }
    try writer.writeAll("</tr>\n");

    self.lineCount += 1;
    if (self.lineCount == 50000) {
        var stderr_buffer: [1024]u8 = undefined;
        var stderr_writer = std.Io.File.stderr().writer(runtime.io, &stderr_buffer);
        var stderr = &stderr_writer.interface;
        _ = try stderr.write("Warning: using more then 50000 lines in html output causes performance issues and possible crashes in the browser\n");
        try stderr.flush();
    }
}

pub fn end(self: *Self, writer: *std.Io.Writer) !void {
    if (self.bodyOpen) {
        try writer.writeAll("</tbody>");
    }
    try writer.writeAll("</table></body></html>\n");
}
