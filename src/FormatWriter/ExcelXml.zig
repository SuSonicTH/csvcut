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
    self.header = try self.allocator.alloc([]u8, fields.*.len);
    for (fields.*, 0..) |field, i| {
        self.header[i] = try self.allocator.dupe(u8, field);
    }
}

pub fn writeData(self: *Self, writer: *const std.io.AnyWriter, fields: *const [][]const u8) !void {
    _ = try writer.write("<Row>");
    for (fields.*) |field| {
        _ = try writer.write("<Cell>");

        const value = checkFormat(field);
        switch (value.format) {
            .integer => _ = try writer.print("<Data ss:Type=\"Number\">{d}</Data></Cell>", .{value.value.integer}),
            .float => _ = try writer.print("<Data ss:Type=\"Number\">{d}</Data></Cell>", .{value.value.float}),
            .string => _ = try writer.print("<Data ss:Type=\"String\">{s}</Data></Cell>", .{value.value.string}),
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
};

const NumberValue = union(NumberFormat) {
    integer: i64,
    float: f64,
    string: []const u8,
};

const CheckedFormat = struct {
    format: NumberFormat,
    value: NumberValue,
};

var numberBuffer: [128]u8 = undefined;

fn checkFormat(field: []const u8) CheckedFormat {
    var isFloat = false;
    var hasGrouping = false;

    if (field.len == 0) return asString(field);

    for (field) |char| {
        if (std.mem.indexOfScalar(u8, "0123456789-,.Ee", char)) |pos| {
            if (pos == 11) {
                hasGrouping = true;
            } else if (pos > 11) {
                isFloat = true;
            }
        } else {
            return asString(field);
        }
    }

    const number = removeGrouping(hasGrouping, field);

    if (isFloat) {
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

fn asString(field: []const u8) CheckedFormat {
    return .{
        .format = .string,
        .value = .{ .string = field },
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
