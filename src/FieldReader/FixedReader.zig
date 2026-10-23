const std = @import("std");
const MemMapper = @import("MemMapper.zig");

const FieldProperty = struct {
    pos: usize,
    length: usize,
};

const Self = @This();

allocator: std.mem.Allocator,
memMapper: MemMapper,
trim: bool,
data: []u8 = &.{},
fieldProperties: ?[]FieldProperty = null,
recordSize: usize = 0,
fields: ?[][]const u8 = null,
pos: usize = 0,
extraLineEnd: u2,
lineBuffer: []u8 = &.{},

pub fn init(file: *std.Io.File, io: std.Io, widhts: []const usize, trim: bool, extraLineEnd: u2, allocator: std.mem.Allocator) !Self {
    var reader: Self = .{
        .allocator = allocator,
        .memMapper = try MemMapper.init(file.*, io, false),
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
        start = std.math.add(usize, start, width) catch return error.RecordSizeOverflow;
    }
    recordSize.* = start;
    return fieldProperties[0..widhts.len];
}

pub fn deinit(self: *Self) void {
    self.memMapper.unmap(self.data);
    self.memMapper.deinit();
    if (self.fieldProperties) |properties| {
        self.allocator.free(properties);
    }
    if (self.fields) |fields| {
        self.allocator.free(fields);
    }
    if (self.lineBuffer.len > 0) {
        self.allocator.free(self.lineBuffer);
    }
}

pub fn reset(self: *Self) void {
    self.pos = 0;
}

pub fn getFields(self: *Self) !?[][]const u8 {
    if (try self.readLine()) |line| {
        for (self.fieldProperties.?, 0..) |property, i| {
            const start = @min(property.pos, line.len);
            const end = @min(property.pos +| property.length, line.len);
            if (self.trim) {
                self.fields.?[i] = std.mem.trim(u8, line[start..end], " \t");
            } else {
                self.fields.?[i] = line[start..end];
            }
        }
        return self.fields;
    }
    return null;
}

inline fn readLine(self: *Self) !?[]const u8 {
    if (self.recordSize == 0 or self.pos >= self.data.len) {
        return null;
    }

    const current = self.pos;
    const remaining = self.data.len - current;
    if (remaining < self.recordSize) {
        const bodyLength = self.partialBodyLength(self.data[current..]);

        // A record size larger than the file cannot produce a full record;
        // return the remaining bytes and let field extraction clamp them.
        if (self.recordSize > self.data.len) {
            self.pos = self.data.len;
            return self.data[current..][0..bodyLength];
        }

        // Pad the last, incomplete record with spaces so no data is dropped.
        if (self.lineBuffer.len < self.recordSize) {
            if (self.lineBuffer.len == 0) {
                self.lineBuffer = try self.allocator.alloc(u8, self.recordSize);
            } else {
                self.lineBuffer = try self.allocator.realloc(self.lineBuffer, self.recordSize);
            }
        }
        @memset(self.lineBuffer, ' ');
        @memcpy(self.lineBuffer[0..bodyLength], self.data[current..][0..bodyLength]);
        self.pos = self.data.len;
        return self.lineBuffer[0..self.recordSize];
    }

    self.pos = current +| self.recordSize +| self.extraLineEnd;
    return self.data[current .. current + self.recordSize];
}

fn partialBodyLength(self: *Self, data: []const u8) usize {
    var length = data.len;
    if (self.extraLineEnd == 0 or length == 0) {
        return length;
    }
    if (data[length - 1] == '\n') {
        length -= 1;
        if (self.extraLineEnd == 2 and length > 0 and data[length - 1] == '\r') {
            length -= 1;
        }
    } else if (data[length - 1] == '\r') {
        length -= 1;
    }
    return length;
}

// Tests
const testing = std.testing;

fn expectEqualStringsArray(expected: []const []const u8, actual: [][]const u8) !void {
    try testing.expect(expected.len <= actual.len);
    for (expected, 0..) |exp, idx| {
        try testing.expectEqualStrings(exp, actual[idx]);
    }
    try testing.expectEqual(expected.len, actual.len);
}

fn writeFile(file_path: []const u8, data: []const u8) !void {
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = file_path, .data = data });
}

fn expectDataMatches(reader: *Self) !void {
    try expectEqualStringsArray(&[_][]const u8{ "A ", "B   ", "C     ", "D         " }, (try reader.getFields()).?);
    try expectEqualStringsArray(&[_][]const u8{ "1 ", "2   ", "3     ", "4         " }, (try reader.getFields()).?);
    try expectEqualStringsArray(&[_][]const u8{ "12", "1234", "123456", "1234567890" }, (try reader.getFields()).?);
    try testing.expectEqual(null, try reader.getFields());
}

test "fields without EOL" {
    const fileName: []const u8 = "./test/fixedLenTest.dat";
    try writeFile(fileName, "A B   C     D         1 2   3     4         1212341234561234567890");

    var file = try std.Io.Dir.cwd().openFile(std.testing.io, fileName, .{});
    defer file.close(std.testing.io);

    var reader = try init(&file, std.testing.io, &.{ 2, 4, 6, 10 }, false, 0, testing.allocator);
    defer reader.deinit();

    try expectDataMatches(&reader);
}

test "fields with LF" {
    const fileName: []const u8 = "./test/fixedLenTest.dat";
    try writeFile(fileName, "A B   C     D         \n1 2   3     4         \n1212341234561234567890\n");

    var file = try std.Io.Dir.cwd().openFile(std.testing.io, fileName, .{});
    defer file.close(std.testing.io);

    var reader = try init(&file, std.testing.io, &.{ 2, 4, 6, 10 }, false, 1, testing.allocator);
    defer reader.deinit();

    try expectDataMatches(&reader);
}

test "fields with CR LF" {
    const fileName: []const u8 = "./test/fixedLenTest.dat";
    try writeFile(fileName, "A B   C     D         \r\n1 2   3     4         \r\n1212341234561234567890\r\n");

    var file = try std.Io.Dir.cwd().openFile(std.testing.io, fileName, .{});
    defer file.close(std.testing.io);

    var reader = try init(&file, std.testing.io, &.{ 2, 4, 6, 10 }, false, 2, testing.allocator);
    defer reader.deinit();

    try expectDataMatches(&reader);
}

test "fields with CR LF exept last line" {
    const fileName: []const u8 = "./test/fixedLenTest.dat";
    try writeFile(fileName, "A B   C     D         \r\n1 2   3     4         \r\n1212341234561234567890");

    var file = try std.Io.Dir.cwd().openFile(std.testing.io, fileName, .{});
    defer file.close(std.testing.io);

    var reader = try init(&file, std.testing.io, &.{ 2, 4, 6, 10 }, false, 2, testing.allocator);
    defer reader.deinit();

    try expectDataMatches(&reader);
}

test "fields trimmed" {
    const fileName: []const u8 = "./test/fixedLenTest.dat";
    try writeFile(fileName, "A B   C     D         1 2   3     4         1212341234561234567890");

    var file = try std.Io.Dir.cwd().openFile(std.testing.io, fileName, .{});
    defer file.close(std.testing.io);

    var reader = try init(&file, std.testing.io, &.{ 2, 4, 6, 10 }, true, 0, testing.allocator);
    defer reader.deinit();

    try expectEqualStringsArray(&[_][]const u8{ "A", "B", "C", "D" }, (try reader.getFields()).?);
    try expectEqualStringsArray(&[_][]const u8{ "1", "2", "3", "4" }, (try reader.getFields()).?);
    try expectEqualStringsArray(&[_][]const u8{ "12", "1234", "123456", "1234567890" }, (try reader.getFields()).?);
    try testing.expectEqual(null, try reader.getFields());
}

test "partial last record is padded" {
    const fileName: []const u8 = "./test/fixedLenTest.dat";
    try writeFile(fileName, "A B   C     D         1 2");

    var file = try std.Io.Dir.cwd().openFile(std.testing.io, fileName, .{});
    defer file.close(std.testing.io);

    var reader = try init(&file, std.testing.io, &.{ 2, 4, 6, 10 }, false, 0, testing.allocator);
    defer reader.deinit();

    try expectEqualStringsArray(&[_][]const u8{ "A ", "B   ", "C     ", "D         " }, (try reader.getFields()).?);
    try expectEqualStringsArray(&[_][]const u8{ "1 ", "2   ", "      ", "          " }, (try reader.getFields()).?);
    try testing.expectEqual(null, try reader.getFields());
}
