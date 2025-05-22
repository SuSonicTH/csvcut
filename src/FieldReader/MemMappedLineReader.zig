const std = @import("std");
const MemMapper = @import("MemMapper.zig");

memMapper: MemMapper,
includeEol: bool,
data: []u8 = undefined,
next: usize = 0,

const Self = @This();

pub fn init(file: *std.fs.File, includeEol: bool) !Self {
    var lineReader: Self = .{
        .memMapper = try MemMapper.init(file.*, false),
        .includeEol = includeEol,
    };
    errdefer lineReader.deinit();
    lineReader.data = try lineReader.memMapper.map(u8, .{});
    return lineReader;
}

pub fn deinit(self: *Self) void {
    self.memMapper.unmap(self.data);
    self.memMapper.deinit();
}

pub fn readLine(self: *Self) !?[]const u8 {
    const data = self.data[self.next..];
    var pos: usize = 0;
    var eol_characters: usize = 0;

    if (pos >= data.len) {
        return null;
    }

    while (pos < data.len and data[pos] != '\r' and data[pos] != '\n') {
        pos += 1;
    }
    if (pos < data.len) {
        if (data[pos] == '\r') {
            eol_characters = 1;
            if (pos + 1 < data.len and data[pos + 1] == '\n') {
                eol_characters = 2;
            }
        } else if (data[pos] == '\n') {
            eol_characters = 1;
        }
    }
    self.next += pos + eol_characters;
    if (self.includeEol) {
        return data[0 .. pos + eol_characters];
    } else {
        return data[0..pos];
    }
}

pub fn reset(self: *Self) void {
    self.next = 0;
}

// Tests

const testing = std.testing;

fn writeFile(file_path: []const u8, data: []const u8) !void {
    const file = try std.fs.cwd().createFile(file_path, .{});
    defer file.close();

    try file.writeAll(data);
}

const fileName: []const u8 = "test/MemMappedLineReaderTest.txt";

test "file with LF" {
    try writeFile(fileName, "one\ntwo\nthree\n");

    var file = try std.fs.cwd().openFile(fileName, .{});
    defer file.close();

    var reader = try init(&file, false);
    defer reader.deinit();

    try testing.expectEqualStrings("one", (try reader.readLine()).?);
    try testing.expectEqualStrings("two", (try reader.readLine()).?);
    try testing.expectEqualStrings("three", (try reader.readLine()).?);
    try testing.expectEqual(null, try reader.readLine());
}

test "file with CR LF" {
    try writeFile(fileName, "one\r\ntwo\r\nthree\r\n");

    var file = try std.fs.cwd().openFile(fileName, .{});
    defer file.close();

    var reader = try init(&file, false);
    defer reader.deinit();

    try testing.expectEqualStrings("one", (try reader.readLine()).?);
    try testing.expectEqualStrings("two", (try reader.readLine()).?);
    try testing.expectEqualStrings("three", (try reader.readLine()).?);
    try testing.expectEqual(null, try reader.readLine());
}

test "file with LF included" {
    try writeFile(fileName, "one\ntwo\nthree\n");

    var file = try std.fs.cwd().openFile(fileName, .{});
    defer file.close();

    var reader = try init(&file, true);
    defer reader.deinit();

    try testing.expectEqualStrings("one\n", (try reader.readLine()).?);
    try testing.expectEqualStrings("two\n", (try reader.readLine()).?);
    try testing.expectEqualStrings("three\n", (try reader.readLine()).?);
    try testing.expectEqual(null, try reader.readLine());
}

test "file with CR LF included" {
    try writeFile(fileName, "one\r\ntwo\r\nthree\r\n");

    var file = try std.fs.cwd().openFile(fileName, .{});
    defer file.close();

    var reader = try init(&file, true);
    defer reader.deinit();

    try testing.expectEqualStrings("one\r\n", (try reader.readLine()).?);
    try testing.expectEqualStrings("two\r\n", (try reader.readLine()).?);
    try testing.expectEqualStrings("three\r\n", (try reader.readLine()).?);
    try testing.expectEqual(null, try reader.readLine());
}

test "reset" {
    try writeFile(fileName, "one\ntwo\nthree\n");

    var file = try std.fs.cwd().openFile(fileName, .{});
    defer file.close();

    var reader = try init(&file, false);
    defer reader.deinit();

    try testing.expectEqualStrings("one", (try reader.readLine()).?);
    try testing.expectEqualStrings("two", (try reader.readLine()).?);

    reader.reset();

    try testing.expectEqualStrings("one", (try reader.readLine()).?);
    try testing.expectEqualStrings("two", (try reader.readLine()).?);
    try testing.expectEqualStrings("three", (try reader.readLine()).?);
    try testing.expectEqual(null, try reader.readLine());
}
