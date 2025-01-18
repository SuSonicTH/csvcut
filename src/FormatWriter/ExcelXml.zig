const std = @import("std");
const Self = @This();

pub const Options = struct {};

allocator: std.mem.Allocator,
lineCount: usize = 0,
header: [][]const u8 = undefined,
sheet: u8 = 1,

const maximumRows: u32 = 1024 * 1024;

pub fn init(
    allocator: std.mem.Allocator,
) !Self {
    return .{
        .allocator = allocator,
    };
}

pub fn start(self: *Self, writer: *const std.io.AnyWriter) !void {
    _ = self;
    _ = try writer.write(@embedFile("ExcelXmlHeader.xml") ++ "\n");
}

pub fn writeHeader(self: *Self, writer: *const std.io.AnyWriter, fields: *const [][]const u8) !void {
    try self.writeData(writer, fields);
    self.header = try self.allocator.alloc([]const u8, fields.*.len);
    for (fields.*, 0..) |field, i| {
        self.header[i] = try self.allocator.dupe(u8, field);
    }
}

pub fn writeData(self: *Self, writer: *const std.io.AnyWriter, fields: *const [][]const u8) !void {
    _ = try writer.write("<Row>");
    for (fields.*) |field| {
        const val = checkFormat(field);
        switch (val.format) {
            .integer => _ = try writer.print("<Cell><Data ss:Type=\"Number\">{d}</Data></Cell>", .{val.value.integer}),
            .float => _ = try writer.print("<Cell><Data ss:Type=\"Number\">{d}</Data></Cell>", .{val.value.float}),
            .string => _ = try writer.print("<Cell><Data ss:Type=\"String\">{s}</Data></Cell>", .{val.value.string}),
            .dateTime => _ = try writer.print("<Cell ss:StyleID=\"{s}\"><Data ss:Type=\"DateTime\">{s}</Data></Cell>", .{ val.style, val.value.dateTime }),
        }
    }
    _ = try writer.write("</Row>\n");

    self.lineCount += 1;
    if (self.lineCount == maximumRows) {
        if (self.sheet == 1) {
            _ = try std.io.getStdErr().write("Warning: using more then 1048576 lines in excleXml in a single sheet is not supported, splitting to multiple sheets\n");
        }
        self.sheet += 1;
        self.lineCount = 0;

        _ = try writer.write("</Table>\n</Worksheet>\n");
        _ = try writer.print("<Worksheet ss:Name=\"Sheet{d}\">\n", .{self.sheet});
        _ = try writer.write("<Table ss:DefaultColumnWidth=\"48\" ss:DefaultRowHeight=\"14.4\">\n");

        try self.writeData(writer, &self.header);
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

var numberBuffer: [128]u8 = undefined;
const baseTime = "1899-12-31T00:00:00.000";

fn checkFormat(field: []const u8) CheckedFormat {
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
            } else if (pos == 16) {
                isTime = true;
            }
        } else {
            return asString(field);
        }
    }

    const number = removeGrouping(hasGrouping, field);
    if (field.len >= 10 and ((field[2] == '/' and field[5] == '/') or (field[2] == '-' and field[5] == '-') or (field[2] == '.' and field[5] == '.'))) {
        //0123456789
        //dd/mm/yyyy
        std.mem.copyForwards(u8, &numberBuffer, baseTime);
        std.mem.copyForwards(u8, numberBuffer[0..], field[6..10]);
        std.mem.copyForwards(u8, numberBuffer[5..], field[3..5]);
        std.mem.copyForwards(u8, numberBuffer[8..], field[0..2]);
        if (field.len == 10) {
            return asDateTime("ShortDate", &numberBuffer);
        } else {
            if (setTime(field[11..], true)) |format| {
                return format;
            } else {
                return asDateTime("ShortDate", &numberBuffer);
            }
        }
    } else if (field.len >= 10 and ((field[4] == '/' and field[7] == '/') or (field[4] == '-' and field[7] == '-') or (field[4] == '.' and field[7] == '.'))) {
        //0123456789
        //yyyy/mm/dd
        std.mem.copyForwards(u8, &numberBuffer, baseTime);
        std.mem.copyForwards(u8, numberBuffer[0..], field[0..4]);
        std.mem.copyForwards(u8, numberBuffer[5..], field[5..7]);
        std.mem.copyForwards(u8, numberBuffer[8..], field[8..10]);
        if (field.len == 10) {
            return asDateTime("ShortDate", &numberBuffer);
        } else {
            if (setTime(field[11..], true)) |format| {
                return format;
            } else {
                return asDateTime("ShortDate", &numberBuffer);
            }
        }
    } else if (isTime) {
        std.mem.copyForwards(u8, &numberBuffer, baseTime);
        if (setTime(field, false)) |format| {
            return format;
        } else {
            return asString(field);
        }
    } else if (isFloat) {
        const value = std.fmt.parseFloat(f64, number) catch return asString(field);
        return .{
            .format = .float,
            .value = .{ .float = value },
        };
    } else {
        if (field[0] == '0') return asString(field);
        const value = std.fmt.parseInt(i64, number, 10) catch return asString(field);
        return .{
            .format = .integer,
            .value = .{ .integer = value },
        };
    }
}

fn setTime(field: []const u8, isDateTime: bool) ?CheckedFormat {
    var style: []const u8 = "DateTime";
    switch (field.len) {
        4 => { //1:23
            std.mem.copyForwards(u8, numberBuffer[12..], field);
            if (!isDateTime) style = "ShortTime";
        },
        5 => { //12:34
            std.mem.copyForwards(u8, numberBuffer[11..], field);
            if (!isDateTime) style = "ShortTime";
        },
        8 => { //12:34:56
            std.mem.copyForwards(u8, numberBuffer[11..], field);
            if (!isDateTime) style = "Time";
        },
        9, 10, 11, 12 => { //12:34:56.123
            std.mem.copyForwards(u8, numberBuffer[11..], field);
            if (!isDateTime) style = "TimeMs";
        },
        else => return null,
    }
    return asDateTime(style, &numberBuffer);
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

fn removeGrouping(hasGrouping: bool, field: []const u8) []const u8 {
    if (hasGrouping) {
        var removed: u8 = 0;
        var i: u8 = 0;
        for (field) |d| {
            if (d == ',') {
                removed += 1;
            } else {
                numberBuffer[i - removed] = d;
            }
            i += 1;
        }
        return numberBuffer[0 .. i - 1];
    }
    return field;
}

pub fn end(self: *Self, writer: *const std.io.AnyWriter) !void {
    _ = self;
    _ = try writer.write("</Table>\n</Worksheet>\n</Workbook>");
}
