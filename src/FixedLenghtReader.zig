const std = @import("std");
const MemMapper = @import("MemMapper.zig");

const Self = @This();

const FieldProperty = struct {
    pos: usize,
    length: usize,
};

allocator: std.mem.Allocator,
memMapper: MemMapper,
trim: bool,
data: []u8 = undefined,
fieldProperties: ?[]FieldProperty = null,
recordSize: usize = 0,
fields: ?[][]const u8 = undefined,
pos: usize = 0,
extraLineEnd: u2,

fn init(file: *std.fs.File, widhts: []const usize, trim: bool, extraLineEnd: u2, allocator: std.mem.Allocator) !Self {
    var reader: Self = .{
        .allocator = allocator,
        .memMapper = try MemMapper.init(file.*, false),
        .trim = trim,
        .extraLineEnd = extraLineEnd,
    };
    errdefer reader.deinit();
    reader.data = try reader.memMapper.map(u8, .{});
    reader.fieldProperties = try calculateFieldProperties(widhts, &reader.recordSize, allocator);
    reader.fields = try allocator.alloc([]const u8, widhts.len);
    return reader;
}

fn calculateFieldProperties(widhts: []const usize, recordSize: *usize, allocator: std.mem.Allocator) ![]FieldProperty {
    var fieldProperties = try allocator.alloc(FieldProperty, widhts.len);
    var start: usize = 0;
    for (widhts, 0..) |width, i| {
        fieldProperties[i].pos = start;
        fieldProperties[i].length = width;
        start += width;
    }
    recordSize.* = start;
    return fieldProperties[0..widhts.len];
}

fn deinit(self: *Self) void {
    self.memMapper.unmap(self.data);
    self.memMapper.deinit();
    if (self.fieldProperties) |properties| {
        self.allocator.free(properties);
    }
    if (self.fields) |fields| {
        self.allocator.free(fields);
    }
}

fn reset(self: *Self) !void {
    self.pos = 0;
}

fn skipLine(self: *Self) !void {
    _ = try self.readLine();
}

inline fn readLine(self: *Self) !?[]const u8 {
    if (self.pos + self.recordSize <= self.data.len) {
        const current = self.pos;
        self.pos += self.recordSize + self.extraLineEnd;
        return self.data[current .. current + self.recordSize];
    }
    return null;
}

fn getFields(self: *Self) !?[][]const u8 {
    if (try self.readLine()) |line| {
        for (self.fieldProperties.?, 0..) |property, i| {
            if (self.trim) {
                self.fields.?[i] = std.mem.trim(u8, line[property.pos .. property.pos + property.length], " \t");
            } else {
                self.fields.?[i] = line[property.pos .. property.pos + property.length];
            }
        }
        return self.fields;
    }
    return null;
}

// Tests

const testing = std.testing;
const testUtils = @import("testUtils.zig");

const writeFile = testUtils.writeFile;
const expectEqualStringsArray = testUtils.expectEqualStringsArray;

fn expectDataMatches(reader: *Self) !void {
    try expectEqualStringsArray(&[_][]const u8{ "A ", "B   ", "C     ", "D         " }, (try reader.getFields()).?);
    try expectEqualStringsArray(&[_][]const u8{ "1 ", "2   ", "3     ", "4         " }, (try reader.getFields()).?);
    try expectEqualStringsArray(&[_][]const u8{ "12", "1234", "123456", "1234567890" }, (try reader.getFields()).?);
    try testing.expectEqual(null, try reader.getFields());
}

test "fields without EOL" {
    const fileName: []const u8 = "./test/fixedLenTest.dat";
    try writeFile(fileName, "A B   C     D         1 2   3     4         1212341234561234567890");

    var file = try std.fs.cwd().openFile(fileName, .{});
    defer file.close();

    var reader = try init(&file, &.{ 2, 4, 6, 10 }, false, 0, testing.allocator);
    defer reader.deinit();

    try expectDataMatches(&reader);
}

test "fields with LF" {
    const fileName: []const u8 = "./test/fixedLenTest.dat";
    try writeFile(fileName, "A B   C     D         \n1 2   3     4         \n1212341234561234567890\n");

    var file = try std.fs.cwd().openFile(fileName, .{});
    defer file.close();

    var reader = try init(&file, &.{ 2, 4, 6, 10 }, false, 1, testing.allocator);
    defer reader.deinit();

    try expectDataMatches(&reader);
}

test "fields with CR LF" {
    const fileName: []const u8 = "./test/fixedLenTest.dat";
    try writeFile(fileName, "A B   C     D         \r\n1 2   3     4         \r\n1212341234561234567890\r\n");

    var file = try std.fs.cwd().openFile(fileName, .{});
    defer file.close();

    var reader = try init(&file, &.{ 2, 4, 6, 10 }, false, 2, testing.allocator);
    defer reader.deinit();

    try expectDataMatches(&reader);
}

test "fields with CR LF exept last line" {
    const fileName: []const u8 = "./test/fixedLenTest.dat";
    try writeFile(fileName, "A B   C     D         \r\n1 2   3     4         \r\n1212341234561234567890");

    var file = try std.fs.cwd().openFile(fileName, .{});
    defer file.close();

    var reader = try init(&file, &.{ 2, 4, 6, 10 }, false, 2, testing.allocator);
    defer reader.deinit();

    try expectDataMatches(&reader);
}

test "fields trimmed" {
    const fileName: []const u8 = "./test/fixedLenTest.dat";
    try writeFile(fileName, "A B   C     D         1 2   3     4         1212341234561234567890");

    var file = try std.fs.cwd().openFile(fileName, .{});
    defer file.close();

    var reader = try init(&file, &.{ 2, 4, 6, 10 }, true, 0, testing.allocator);
    defer reader.deinit();

    try expectEqualStringsArray(&[_][]const u8{ "A", "B", "C", "D" }, (try reader.getFields()).?);
    try expectEqualStringsArray(&[_][]const u8{ "1", "2", "3", "4" }, (try reader.getFields()).?);
    try expectEqualStringsArray(&[_][]const u8{ "12", "1234", "123456", "1234567890" }, (try reader.getFields()).?);
    try testing.expectEqual(null, try reader.getFields());
}
