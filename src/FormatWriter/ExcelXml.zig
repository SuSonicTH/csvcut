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
        _ = try writer.write("<Cell><Data ss:Type=\"String\">");
        _ = try writer.write(field);
        _ = try writer.write("</Data></Cell>");
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

pub fn end(self: *Self, writer: *const std.io.AnyWriter) !void {
    _ = self;
    _ = try writer.write("</Table>\n</Worksheet>\n</Workbook>");
}
