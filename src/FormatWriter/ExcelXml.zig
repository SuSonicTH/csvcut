const std = @import("std");
const runtime = @import("../runtime.zig");
const escape = @import("escape.zig");
const Self = @This();

pub const Options = struct {};

allocator: std.mem.Allocator,
lineCount: usize = 0,
header: ?[][]const u8 = null,
sheet: usize = 1,
showHeader: bool = true,
dateBuffer: [32]u8 = undefined,

const maximumRows: u32 = 1024 * 1024;

pub fn init(
    allocator: std.mem.Allocator,
    header: ?[][]const u8,
    showHeader: bool,
) !Self {
    return .{
        .allocator = allocator,
        .header = header,
        .showHeader = showHeader,
    };
}

pub fn start(self: *Self, writer: *std.Io.Writer) !void {
    _ = self;
    try writer.writeAll(@embedFile("ExcelXmlHeader.xml") ++ "\n");
}

pub fn writeHeader(self: *Self, writer: *std.Io.Writer, fields: *const [][]const u8) !void {
    try self.writeData(writer, fields);
    self.header = fields.*;
}

pub fn writeData(self: *Self, writer: *std.Io.Writer, fields: *const [][]const u8) !void {
    try writer.writeAll("<Row>");
    for (fields.*) |field| {
        const val = try self.checkFormat(field);
        switch (val.format) {
            .integer => _ = try writer.print("<Cell><Data ss:Type=\"Number\">{d}</Data></Cell>", .{val.value.integer}),
            .float => _ = try writer.print("<Cell><Data ss:Type=\"Number\">{d}</Data></Cell>", .{val.value.float}),
            .string => {
                try writer.writeAll("<Cell><Data ss:Type=\"String\">");
                try escape.writeHtml(writer, val.value.string);
                try writer.writeAll("</Data></Cell>");
            },
            .dateTime => _ = try writer.print("<Cell ss:StyleID=\"{s}\"><Data ss:Type=\"DateTime\">{s}</Data></Cell>", .{ val.style, val.value.dateTime }),
        }
    }
    try writer.writeAll("</Row>\n");

    self.lineCount += 1;
    if (self.lineCount == maximumRows) {
        if (self.sheet == 1) {
            var stderr_buffer: [1024]u8 = undefined;
            var stderr_writer = std.Io.File.stderr().writer(runtime.io, &stderr_buffer);
            var stderr = &stderr_writer.interface;

            _ = try stderr.write("Warning: using more then 1048576 lines in excleXml in a single sheet is not supported, splitting to multiple sheets\n");
            try stderr.flush();
        }
        self.sheet += 1;
        self.lineCount = 0;

        try writer.writeAll("</Table>\n</Worksheet>\n");
        _ = try writer.print("<Worksheet ss:Name=\"Sheet{d}\">\n", .{self.sheet});
        try writer.writeAll("<Table ss:DefaultColumnWidth=\"48\" ss:DefaultRowHeight=\"14.4\">\n");

        if (self.showHeader) {
            if (self.header) |header| {
                try self.writeData(writer, &header);
            }
        }
    }
}

const NumberFormat = enum {
    integer,
    float,
    string,
    dateTime,
};

const NumberValue = union(NumberFormat) {
    integer: i64,
    float: f64,
    string: []const u8,
    dateTime: []const u8,
};

const CheckedFormat = struct {
    format: NumberFormat,
    value: NumberValue,
    style: []const u8 = "",
};

const baseTime = "1899-12-31T00:00:00.000";

fn checkFormat(self: *Self, field: []const u8) !CheckedFormat {
    var isFloat = false;
    var isTime = false;
    var hasGrouping = false;

    if (field.len == 0) return asString(field);
    for (field) |char| {
        if (std.mem.indexOfScalar(u8, "0123456789-,.Ee/:T ", char)) |pos| {
            if (pos == 11) {
                hasGrouping = true;
            } else if (pos > 11 and pos < 15 and !isTime) {
                isFloat = true;
            } else if (pos == 16 or pos == 17) {
                isTime = true;
            }
        } else {
            return asString(field);
        }
    }

    if (field.len >= 10 and ((field[2] == '/' and field[5] == '/') or (field[2] == '-' and field[5] == '-') or (field[2] == '.' and field[5] == '.'))) {
        //0123456789
        //dd/mm/yyyy
        std.mem.copyForwards(u8, &self.dateBuffer, baseTime);
        std.mem.copyForwards(u8, self.dateBuffer[0..], field[6..10]);
        std.mem.copyForwards(u8, self.dateBuffer[5..], field[3..5]);
        std.mem.copyForwards(u8, self.dateBuffer[8..], field[0..2]);
        if (field.len == 10) {
            return asDateTime("ShortDate", &self.dateBuffer);
        } else {
            if (self.setTime(field[11..], true)) |format| {
                return format;
            } else {
                return asDateTime("ShortDate", &self.dateBuffer);
            }
        }
    } else if (field.len >= 10 and ((field[4] == '/' and field[7] == '/') or (field[4] == '-' and field[7] == '-') or (field[4] == '.' and field[7] == '.'))) {
        //0123456789
        //yyyy/mm/dd
        std.mem.copyForwards(u8, &self.dateBuffer, baseTime);
        std.mem.copyForwards(u8, self.dateBuffer[0..], field[0..4]);
        std.mem.copyForwards(u8, self.dateBuffer[5..], field[5..7]);
        std.mem.copyForwards(u8, self.dateBuffer[8..], field[8..10]);
        if (field.len == 10) {
            return asDateTime("ShortDate", &self.dateBuffer);
        } else {
            if (self.setTime(field[11..], true)) |format| {
                return format;
            } else {
                return asDateTime("ShortDate", &self.dateBuffer);
            }
        }
    } else if (isTime) {
        std.mem.copyForwards(u8, &self.dateBuffer, baseTime);
        if (self.setTime(field, false)) |format| {
            return format;
        } else {
            return asString(field);
        }
    } else if (isFloat) {
        const number = if (hasGrouping) try self.removeGrouping(field) else field;
        defer if (hasGrouping) self.allocator.free(number);
        const value = std.fmt.parseFloat(f64, number) catch return asString(field);
        return .{
            .format = .float,
            .value = .{ .float = value },
        };
    } else {
        if (field[0] == '0') return asString(field);
        const number = if (hasGrouping) try self.removeGrouping(field) else field;
        defer if (hasGrouping) self.allocator.free(number);
        const value = std.fmt.parseInt(i64, number, 10) catch return asString(field);
        return .{
            .format = .integer,
            .value = .{ .integer = value },
        };
    }
}

fn setTime(self: *Self, field: []const u8, isDateTime: bool) ?CheckedFormat {
    var style: []const u8 = "DateTime";
    switch (field.len) {
        4 => { //1:23
            std.mem.copyForwards(u8, self.dateBuffer[12..], field);
            if (!isDateTime) style = "ShortTime";
        },
        5 => { //12:34
            std.mem.copyForwards(u8, self.dateBuffer[11..], field);
            if (!isDateTime) style = "ShortTime";
        },
        8 => { //12:34:56
            std.mem.copyForwards(u8, self.dateBuffer[11..], field);
            if (!isDateTime) style = "Time";
        },
        9, 10, 11, 12 => { //12:34:56.123
            std.mem.copyForwards(u8, self.dateBuffer[11..], field);
            if (!isDateTime) style = "TimeMs";
        },
        else => return null,
    }
    return asDateTime(style, &self.dateBuffer);
}

fn asString(field: []const u8) CheckedFormat {
    return .{
        .format = .string,
        .value = .{ .string = field },
    };
}

fn asDateTime(style: []const u8, value: []const u8) CheckedFormat {
    return .{
        .format = .dateTime,
        .value = .{ .dateTime = value[0..baseTime.len] },
        .style = style,
    };
}

fn removeGrouping(self: *Self, field: []const u8) ![]u8 {
    var commas: usize = 0;
    for (field) |c| {
        if (c == ',') commas += 1;
    }

    const buffer = try self.allocator.alloc(u8, field.len - commas);
    var i: usize = 0;
    for (field) |c| {
        if (c == ',') continue;
        buffer[i] = c;
        i += 1;
    }
    return buffer;
}

pub fn end(self: *Self, writer: *std.Io.Writer) !void {
    _ = self;
    try writer.writeAll("</Table>\n</Worksheet>\n</Workbook>");
}

// Tests

const testing = std.testing;

test "grouped numbers are parsed" {
    var excel = try init(testing.allocator, null, true);

    const integer = try excel.checkFormat("1,234");
    try testing.expectEqual(NumberFormat.integer, integer.format);
    try testing.expectEqual(@as(i64, 1234), integer.value.integer);

    const large = try excel.checkFormat("1,234,567");
    try testing.expectEqual(NumberFormat.integer, large.format);
    try testing.expectEqual(@as(i64, 1234567), large.value.integer);

    const float = try excel.checkFormat("1,234.5");
    try testing.expectEqual(NumberFormat.float, float.format);
    try testing.expectEqual(@as(f64, 1234.5), float.value.float);
}
