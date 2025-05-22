const std = @import("std");
const MemMappedLineReader = @import("MemMappedLineReader.zig");
const CsvLine = @import("CsvLine.zig");

const Self = @This();

allocator: std.mem.Allocator,
lineReader: MemMappedLineReader,
csvLine: CsvLine,

pub fn init(file: *std.fs.File, csvLineOptions: CsvLine.Options, allocator: std.mem.Allocator) !Self {
    var csvLineParser = try CsvLine.init(allocator, csvLineOptions);
    errdefer csvLineParser.deinit();

    return .{
        .allocator = allocator,
        .csvLine = csvLineParser,
        .lineReader = try MemMappedLineReader.init(file, false),
    };
}

pub fn deinit(self: *Self) void {
    self.lineReader.deinit();
    self.csvLine.deinit();
}

pub fn reset(self: *Self) void {
    self.lineReader.reset();
}

pub fn getFields(self: *Self) !?[][]const u8 {
    if (try self.lineReader.readLine()) |line| {
        return try self.csvLine.parse(line);
    }
    return null;
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
    const file = try std.fs.cwd().createFile(file_path, .{});
    defer file.close();

    try file.writeAll(data);
}

const fileName: []const u8 = "test/CsvReaderTest.csv";
var fileWritten: bool = false;

const HEADER = &[_][]const u8{ "ONE", "TWO", "THREE", "FOUR" };
const LINE_1 = &[_][]const u8{ "11", "12", "13", "14" };
const LINE_2 = &[_][]const u8{ "21", "22", "23", "24" };
const LINE_3 = &[_][]const u8{ "31", "32", "33", "34" };
const LINE_4 = &[_][]const u8{ "41", "42", "43", "44" };

fn writeTestFile() !void {
    if (!fileWritten) {
        try writeFile(fileName, "ONE,TWO,THREE,FOUR\n" ++
            "11,12,13,14\n" ++
            "21,22,23,24\n" ++
            "31,32,33,34\n" ++
            "41,42,43,44\n");
        fileWritten = true;
    }
}

test "reading" {
    try writeTestFile();
    var file = try std.fs.cwd().openFile(fileName, .{});
    defer file.close();

    var reader = try init(&file,  .{}, testing.allocator);
    defer reader.deinit();

    try expectEqualStringsArray(HEADER, (try reader.getFields()).?);
    try expectEqualStringsArray(LINE_1, (try reader.getFields()).?);
    try expectEqualStringsArray(LINE_2, (try reader.getFields()).?);
    try expectEqualStringsArray(LINE_3, (try reader.getFields()).?);
    try expectEqualStringsArray(LINE_4, (try reader.getFields()).?);
    try testing.expectEqual(null, try reader.getFields());
}

test "reset after 3 lines read" {
    try writeTestFile();
    var file = try std.fs.cwd().openFile(fileName, .{});
    defer file.close();

    var reader = try init(&file,  .{}, testing.allocator);
    defer reader.deinit();

    try expectEqualStringsArray(HEADER, (try reader.getFields()).?);
    try expectEqualStringsArray(LINE_1, (try reader.getFields()).?);
    try expectEqualStringsArray(LINE_2, (try reader.getFields()).?);
    reader.reset();

    try expectEqualStringsArray(HEADER, (try reader.getFields()).?);
    try expectEqualStringsArray(LINE_1, (try reader.getFields()).?);
    try expectEqualStringsArray(LINE_2, (try reader.getFields()).?);
    try expectEqualStringsArray(LINE_3, (try reader.getFields()).?);
    try expectEqualStringsArray(LINE_4, (try reader.getFields()).?);
    try testing.expectEqual(null, try reader.getFields());
}
