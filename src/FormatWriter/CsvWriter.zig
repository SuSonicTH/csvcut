const std = @import("std");
const Self = @This();

pub const Options = struct {
    separator: [1]u8 = .{','},
    lineEnding: [1]u8 = .{'\n'},
    quote: ?[1]u8 = null,
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
            try writer.writeAll(&self.options.separator);
        }
        try self.writeField(writer, field);
    }
    try writer.writeAll(&self.options.lineEnding);
}

fn writeField(self: *Self, writer: *std.Io.Writer, field: []const u8) !void {
    if (self.options.quote) |quote| {
        try writer.writeAll(&quote);
        try writeQuotedBody(writer, field, quote[0]);
        try writer.writeAll(&quote);
        return;
    }

    if (needsQuoting(field, self.options.separator[0])) {
        try writer.writeAll("\"");
        try writeQuotedBody(writer, field, '"');
        try writer.writeAll("\"");
    } else {
        try writer.writeAll(field);
    }
}

fn needsQuoting(field: []const u8, separator: u8) bool {
    for (field) |c| {
        if (c == separator or c == '"' or c == '\r' or c == '\n') {
            return true;
        }
    }
    return false;
}

fn writeQuotedBody(writer: *std.Io.Writer, field: []const u8, quote: u8) !void {
    for (field) |c| {
        if (c == quote) {
            try writer.writeByte(quote);
        }
        try writer.writeByte(c);
    }
}

pub fn end(self: *Self, writer: *std.Io.Writer) !void {
    _ = self;
    _ = writer;
}
