const std = @import("std");
const runtime = @import("../runtime.zig");
const escape = @import("escape.zig");
const Self = @This();

showHeader: bool,
header: ?[][]const u8 = null,
lineCount: usize = 0,

pub fn init(showHeader: bool, header: ?[][]const u8) !Self {
    return .{
        .showHeader = showHeader,
        .header = header,
    };
}

pub fn start(self: *Self, writer: *std.Io.Writer) !void {
    try writer.writeAll(@embedFile("HtmlHandsonHeader.html"));

    if (!self.showHeader) {
        try writer.writeAll("false\n");
    } else if (self.header) |header| {
        try writer.writeAll("[");
        for (header, 0..) |field, i| {
            if (i > 0) {
                try writer.writeAll(", ");
            }
            try escape.writeJsonString(writer, field);
        }
        try writer.writeAll("]\n");
    } else {
        // Handsontable generates column headers from the data when given `true`.
        try writer.writeAll("true\n");
    }

    try writer.writeAll("            });\n");
    try writer.writeAll("        });\n");
    try writer.writeAll("var data = [\n");
    self.lineCount = 0;
}

pub fn writeHeader(self: *Self, writer: *std.Io.Writer, fields: *const [][]const u8) !void {
    _ = self;
    _ = writer;
    _ = fields;
}

pub fn writeData(self: *Self, writer: *std.Io.Writer, fields: *const [][]const u8) !void {
    try writer.writeAll("[");
    for (fields.*, 0..) |field, i| {
        if (i > 0) {
            try writer.writeAll(", ");
        }
        try escape.writeJsonString(writer, field);
    }
    try writer.writeAll("],\n");

    self.lineCount += 1;
    if (self.lineCount == 10000) {
        var stderr_buffer: [1024]u8 = undefined;
        var stderr_writer = std.Io.File.stderr().writer(runtime.io, &stderr_buffer);
        var stderr = &stderr_writer.interface;

        _ = try stderr.write("Warning: using more then 10000 lines in htmlHandson output causes performance issues and possible crashes in the browser\n");
        try stderr.flush();
    }
}

pub fn end(self: *Self, writer: *std.Io.Writer) !void {
    _ = self;
    try writer.writeAll("];\n");
    try writer.writeAll(@embedFile("HtmlHandsonFooter.html"));
}
