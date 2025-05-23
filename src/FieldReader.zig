const std = @import("std");

const CsvReader = @import("FieldReader/CsvReader.zig");
const Filter = @import("options.zig").Filter;
const CsvLine = @import("FieldReader/CsvLine.zig");

const FixedReader = @import("FieldReader/FixedReader.zig");

pub const FieldReader = union(enum) {
    csvReader: CsvReader,
    fixedReader: FixedReader,

    pub fn initCsvReader(file: *std.fs.File, csvLineOptions: CsvLine.Options, allocator: std.mem.Allocator) !FieldReader {
        return .{ .csvReader = try CsvReader.init(file, csvLineOptions, allocator) };
    }

    pub fn initFixedReader(file: *std.fs.File, widhts: []const usize, trim: bool, extraLineEnd: u2, allocator: std.mem.Allocator) !FieldReader {
        return .{ .fixedReader = try FixedReader.init(file, widhts, trim, extraLineEnd, allocator) };
    }

    pub fn deinit(self: *FieldReader) void {
        switch (self.*) {
            inline else => |*fieldReader| fieldReader.deinit(),
        }
    }

    pub fn reset(self: *FieldReader) void {
        switch (self.*) {
            inline else => |*fieldReader| fieldReader.reset(),
        }
    }

    fn getFields(self: *FieldReader) !?[][]const u8 {
        switch (self.*) {
            inline else => |*fieldReader| return fieldReader.getFields(),
        }
    }
};

const Self = @This();

allocator: std.mem.Allocator,
fieldReader: FieldReader,
inputLimit: usize,
skipLine: ?std.AutoHashMap(usize, bool),
lineNumber: usize = 0,
linesRead: usize = 0,
selectedIndices: ?[]usize = null,
excludedIndices: ?std.AutoHashMap(usize, bool) = null,
selected: ?[][]const u8 = null,
filters: ?std.ArrayList(Filter) = null,
filtersOut: ?std.ArrayList(Filter) = null,

pub fn initCsvReader(file: *std.fs.File, inputLimit: usize, skipLine: ?std.AutoHashMap(usize, bool), csvLineOptions: CsvLine.Options, allocator: std.mem.Allocator) !Self {
    return .{
        .fieldReader = try FieldReader.initCsvReader(file, csvLineOptions, allocator),
        .allocator = allocator,
        .inputLimit = inputLimit,
        .skipLine = skipLine,
    };
}

pub fn initFixedReader(file: *std.fs.File, inputLimit: usize, skipLine: ?std.AutoHashMap(usize, bool), widhts: []const usize, trim: bool, extraLineEnd: u2, allocator: std.mem.Allocator) !Self {
    return .{
        .fieldReader = try FieldReader.initFixedReader(file, widhts, trim, extraLineEnd, allocator),
        .allocator = allocator,
        .inputLimit = inputLimit,
        .skipLine = skipLine,
    };
}

pub fn deinit(self: *Self) void {
    self.fieldReader.deinit();
    if (self.selected != null) {
        self.allocator.free(self.selected.?);
    }
}

pub fn reset(self: *Self) void {
    self.lineNumber = 0;
    self.linesRead = 0;
    self.fieldReader.reset();
}

pub fn resetLinesRead(self: *Self) void {
    self.linesRead = 0;
}

pub fn setSelectedIndices(self: *Self, selectedIndices: ?[]usize) !void {
    if (selectedIndices) |indices| {
        self.selectedIndices = indices;
        self.selected = try self.allocator.alloc([]const u8, selectedIndices.?.len);
    }
}

pub fn setExcludedIndices(self: *Self, excludedIndices: ?std.AutoHashMap(usize, bool)) void {
    if (excludedIndices) |indices| {
        self.excludedIndices = indices;
    }
}

pub fn setFilters(self: *Self, filterList: ?std.ArrayList(Filter)) void {
    if (filterList) |filters| {
        self.filters = filters;
    }
}

pub fn setFiltersOut(self: *Self, filterOutList: ?std.ArrayList(Filter)) void {
    if (filterOutList) |filters| {
        self.filtersOut = filters;
    }
}

pub inline fn readLine(self: *Self) !?[][]const u8 {
    while (true) {
        if (self.inputLimit > 0 and self.inputLimit == self.linesRead) {
            return null;
        }

        try self.skipLines();

        self.lineNumber += 1;
        self.linesRead += 1;

        if (try self.fieldReader.getFields()) |fields| {
            if (self.noFilterOrfilterMatches(fields)) {
                return self.getSelectedFields(fields);
            }
        } else {
            return null;
        }
    }
}

pub inline fn skipOneLine(self: *Self) !void {
    _ = try self.fieldReader.getFields();
}

inline fn skipLines(self: *Self) !void {
    if (self.skipLine != null) {
        while (self.skipLine.?.get(self.lineNumber) != null) {
            try self.skipOneLine();
            self.lineNumber += 1;
            self.linesRead += 1;
        }
    }
}

inline fn noFilterOrfilterMatches(self: *Self, fields: [][]const u8) bool {
    if (self.filters == null and self.filtersOut == null) {
        return true;
    }

    if (self.filtersOut) |filtersOut| {
        for (filtersOut.items) |filter| {
            if (filter.matches(fields)) {
                return false;
            }
        }
    }

    if (self.filters == null) {
        return true;
    }

    for (self.filters.?.items) |filter| {
        if (filter.matches(fields)) {
            return true;
        }
    }
    return false;
}

pub inline fn getSelectedFields(self: *Self, fields: [][]const u8) !?[][]const u8 {
    if (self.selectedIndices) |indices| {
        for (indices, 0..) |field, index| {
            self.selected.?[index] = fields[field];
        }
        return self.selected;
    } else if (self.excludedIndices) |indices| {
        if (self.selected == null) {
            self.selected = try self.allocator.alloc([]const u8, fields.len);
        }
        var i: usize = 0;
        for (fields, 0..) |field, index| {
            if (!indices.contains(index)) {
                self.selected.?[i] = field;
                i += 1;
            }
        }
        return self.selected.?[0..i];
    } else {
        return fields;
    }
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

const fileName: []const u8 = "./test/CsvReaderTest.csv";
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

test "unfiltered reading" {
    try writeTestFile();
    var file = try std.fs.cwd().openFile(fileName, .{});
    defer file.close();

    var reader = try initCsvReader(&file, 0, null, .{}, testing.allocator);
    defer reader.deinit();

    try expectEqualStringsArray(HEADER, (try reader.readLine()).?);
    try expectEqualStringsArray(LINE_1, (try reader.readLine()).?);
    try expectEqualStringsArray(LINE_2, (try reader.readLine()).?);
    try expectEqualStringsArray(LINE_3, (try reader.readLine()).?);
    try expectEqualStringsArray(LINE_4, (try reader.readLine()).?);
    try testing.expectEqual(null, try reader.readLine());
}

test "input limit 1" {
    try writeTestFile();
    var file = try std.fs.cwd().openFile(fileName, .{});
    defer file.close();

    var reader = try initCsvReader(&file, 1, null, .{}, testing.allocator);
    defer reader.deinit();

    try expectEqualStringsArray(HEADER, (try reader.readLine()).?);
    try testing.expectEqual(null, try reader.readLine());
}

test "input limit 3" {
    try writeTestFile();
    var file = try std.fs.cwd().openFile(fileName, .{});
    defer file.close();

    var reader = try initCsvReader(&file, 3, null, .{}, testing.allocator);
    defer reader.deinit();

    try expectEqualStringsArray(HEADER, (try reader.readLine()).?);
    try expectEqualStringsArray(LINE_1, (try reader.readLine()).?);
    try expectEqualStringsArray(LINE_2, (try reader.readLine()).?);
    try testing.expectEqual(null, try reader.readLine());
}

test "skip lines 2 & 3" {
    try writeTestFile();
    var file = try std.fs.cwd().openFile(fileName, .{});
    defer file.close();

    var skip = std.AutoHashMap(usize, bool).init(testing.allocator);
    defer skip.deinit();
    try skip.put(2, true);
    try skip.put(3, true);

    var reader = try initCsvReader(&file, 0, skip, .{}, testing.allocator);
    defer reader.deinit();

    try expectEqualStringsArray(HEADER, (try reader.readLine()).?);
    try expectEqualStringsArray(LINE_1, (try reader.readLine()).?);
    try expectEqualStringsArray(LINE_4, (try reader.readLine()).?);
    try testing.expectEqual(null, try reader.readLine());
}

test "reset after 3 lines read" {
    try writeTestFile();
    var file = try std.fs.cwd().openFile(fileName, .{});
    defer file.close();

    var reader = try initCsvReader(&file, 0, null, .{}, testing.allocator);
    defer reader.deinit();

    try expectEqualStringsArray(HEADER, (try reader.readLine()).?);
    try expectEqualStringsArray(LINE_1, (try reader.readLine()).?);
    try expectEqualStringsArray(LINE_2, (try reader.readLine()).?);
    reader.reset();

    try expectEqualStringsArray(HEADER, (try reader.readLine()).?);
    try expectEqualStringsArray(LINE_1, (try reader.readLine()).?);
    try expectEqualStringsArray(LINE_2, (try reader.readLine()).?);
    try expectEqualStringsArray(LINE_3, (try reader.readLine()).?);
    try expectEqualStringsArray(LINE_4, (try reader.readLine()).?);
    try testing.expectEqual(null, try reader.readLine());
}

test "input limit 3 reasetLinesRead after header" {
    try writeTestFile();
    var file = try std.fs.cwd().openFile(fileName, .{});
    defer file.close();

    var reader = try initCsvReader(&file, 3, null, .{}, testing.allocator);
    defer reader.deinit();

    try expectEqualStringsArray(HEADER, (try reader.readLine()).?);
    reader.resetLinesRead();

    try expectEqualStringsArray(LINE_1, (try reader.readLine()).?);
    try expectEqualStringsArray(LINE_2, (try reader.readLine()).?);
    try expectEqualStringsArray(LINE_3, (try reader.readLine()).?);
    try testing.expectEqual(null, try reader.readLine());
}

test "skipOneLine" {
    try writeTestFile();
    var file = try std.fs.cwd().openFile(fileName, .{});
    defer file.close();

    var reader = try initCsvReader(&file, 0, null, .{}, testing.allocator);
    defer reader.deinit();

    try expectEqualStringsArray(HEADER, (try reader.readLine()).?);
    try expectEqualStringsArray(LINE_1, (try reader.readLine()).?);
    try reader.skipOneLine();
    try expectEqualStringsArray(LINE_3, (try reader.readLine()).?);
    try expectEqualStringsArray(LINE_4, (try reader.readLine()).?);
    try testing.expectEqual(null, try reader.readLine());
}

test "selected indices 1,2" {
    try writeTestFile();
    var file = try std.fs.cwd().openFile(fileName, .{});
    defer file.close();

    var reader = try initCsvReader(&file, 0, null, .{}, testing.allocator);
    defer reader.deinit();

    var selected: [2]usize = .{ 1, 2 };
    try reader.setSelectedIndices(&selected);

    try expectEqualStringsArray(&[_][]const u8{ "TWO", "THREE" }, (try reader.readLine()).?);
    try expectEqualStringsArray(&[_][]const u8{ "12", "13" }, (try reader.readLine()).?);
    try expectEqualStringsArray(&[_][]const u8{ "22", "23" }, (try reader.readLine()).?);
    try expectEqualStringsArray(&[_][]const u8{ "32", "33" }, (try reader.readLine()).?);
    try expectEqualStringsArray(&[_][]const u8{ "42", "43" }, (try reader.readLine()).?);
    try testing.expectEqual(null, try reader.readLine());
}

test "selected indices 2,1,0" {
    try writeTestFile();
    var file = try std.fs.cwd().openFile(fileName, .{});
    defer file.close();

    var reader = try initCsvReader(&file, 0, null, .{}, testing.allocator);
    defer reader.deinit();

    var selected: [3]usize = .{ 2, 1, 0 };
    try reader.setSelectedIndices(&selected);

    try expectEqualStringsArray(&[_][]const u8{ "THREE", "TWO", "ONE" }, (try reader.readLine()).?);
    try expectEqualStringsArray(&[_][]const u8{ "13", "12", "11" }, (try reader.readLine()).?);
    try expectEqualStringsArray(&[_][]const u8{ "23", "22", "21" }, (try reader.readLine()).?);
    try expectEqualStringsArray(&[_][]const u8{ "33", "32", "31" }, (try reader.readLine()).?);
    try expectEqualStringsArray(&[_][]const u8{ "43", "42", "41" }, (try reader.readLine()).?);
    try testing.expectEqual(null, try reader.readLine());
}

test "exclude 0,3" {
    try writeTestFile();
    var file = try std.fs.cwd().openFile(fileName, .{});
    defer file.close();

    var reader = try initCsvReader(&file, 0, null, .{}, testing.allocator);
    defer reader.deinit();

    var exclude = std.AutoHashMap(usize, bool).init(testing.allocator);
    defer exclude.deinit();
    try exclude.put(0, true);
    try exclude.put(3, true);
    reader.setExcludedIndices(exclude);

    try expectEqualStringsArray(&[_][]const u8{ "TWO", "THREE" }, (try reader.readLine()).?);
    try expectEqualStringsArray(&[_][]const u8{ "12", "13" }, (try reader.readLine()).?);
    try expectEqualStringsArray(&[_][]const u8{ "22", "23" }, (try reader.readLine()).?);
    try expectEqualStringsArray(&[_][]const u8{ "32", "33" }, (try reader.readLine()).?);
    try expectEqualStringsArray(&[_][]const u8{ "42", "43" }, (try reader.readLine()).?);
    try testing.expectEqual(null, try reader.readLine());
}

test "Filter A" {
    try writeFile(fileName, "ONE,TWO,THREE,FOUR\n" ++
        "A,12,13,14\n" ++
        "B,22,23,24\n" ++
        "A,32,33,34\n" ++
        "B,42,43,44\n");
    fileWritten = false;

    var file = try std.fs.cwd().openFile(fileName, .{});
    defer file.close();

    var reader = try initCsvReader(&file, 0, null, .{}, testing.allocator);
    defer reader.deinit();

    const header = try testing.allocator.dupe([]const u8, (try reader.readLine()).?);
    defer testing.allocator.free(header);

    //setup filter
    var filterList = std.ArrayList(Filter).init(testing.allocator);
    defer filterList.deinit();
    var filter = try Filter.init(testing.allocator);
    defer filter.deinit();
    try filter.append("ONE=A");
    try filter.calculateIndices(header);
    try filterList.append(filter);
    reader.setFilters(filterList);

    try expectEqualStringsArray(&[_][]const u8{ "A", "12", "13", "14" }, (try reader.readLine()).?);
    try expectEqualStringsArray(&[_][]const u8{ "A", "32", "33", "34" }, (try reader.readLine()).?);
    try testing.expectEqual(null, try reader.readLine());
}

test "FilterOut A" {
    try writeFile(fileName, "ONE,TWO,THREE,FOUR\n" ++
        "A,12,13,14\n" ++
        "B,22,23,24\n" ++
        "A,32,33,34\n" ++
        "B,42,43,44\n");
    fileWritten = false;

    var file = try std.fs.cwd().openFile(fileName, .{});
    defer file.close();

    var reader = try initCsvReader(&file, 0, null, .{}, testing.allocator);
    defer reader.deinit();

    const header = try testing.allocator.dupe([]const u8, (try reader.readLine()).?);
    defer testing.allocator.free(header);

    //setup filter
    var filterList = std.ArrayList(Filter).init(testing.allocator);
    defer filterList.deinit();
    var filter = try Filter.init(testing.allocator);
    defer filter.deinit();
    try filter.append("ONE=A");
    try filter.calculateIndices(header);
    try filterList.append(filter);
    reader.setFiltersOut(filterList);

    try expectEqualStringsArray(&[_][]const u8{ "B", "22", "23", "24" }, (try reader.readLine()).?);
    try expectEqualStringsArray(&[_][]const u8{ "B", "42", "43", "44" }, (try reader.readLine()).?);
    try testing.expectEqual(null, try reader.readLine());
}
