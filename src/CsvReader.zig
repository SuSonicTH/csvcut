const std = @import("std");
const CsvLine = @import("CsvLine.zig");
const Filter = @import("options.zig").Filter;

const MemMappedLineReader = @import("MemMappedLineReader.zig");

const Self = @This();

allocator: std.mem.Allocator,
lineReader: MemMappedLineReader,
inputLimit: usize,
skipLines: ?std.AutoHashMap(usize, bool),
csvLine: CsvLine,

lineNumber: usize = 0,
linesRead: usize = 0,

selectedIndices: ?[]usize = null,
excludedIndices: ?std.AutoHashMap(usize, bool) = null,
selected: ?[][]const u8 = null,
filters: ?std.ArrayList(Filter) = null,
filtersOut: ?std.ArrayList(Filter) = null,

pub fn init(file: *std.fs.File, inputLimit: usize, skipLines: ?std.AutoHashMap(usize, bool), csvLineOptions: CsvLine.Options, allocator: std.mem.Allocator) !Self {
    var csvLineParser = try CsvLine.init(allocator, csvLineOptions);
    errdefer csvLineParser.deinit();

    return .{
        .allocator = allocator,
        .inputLimit = inputLimit,
        .skipLines = skipLines,
        .csvLine = csvLineParser,
        .lineReader = try MemMappedLineReader.init(file, false),
    };
}

pub fn deinit(self: *Self) void {
    self.lineReader.deinit();
    self.csvLine.deinit();
}

pub fn reset(self: *Self) void {
    self.lineNumber = 0;
    self.linesRead = 0;
    self.lineReader.reset();
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

        try self.doSkipLines();

        self.lineNumber += 1;
        self.linesRead += 1;

        if (try self.getFields()) |fields| {
            if (self.noFilterOrfilterMatches(fields)) {
                return self.getSelectedFields(fields);
            }
        } else {
            return null;
        }
    }
}

inline fn doSkipLines(self: *Self) !void {
    if (self.skipLines != null) {
        while (self.skipLines.?.get(self.lineNumber) != null) {
            try self.skipOneLine();
        }
    }
}

pub inline fn skipOneLine(self: *Self) !void {
    _ = try self.lineReader.readLine();
    self.lineNumber += 1;
    self.linesRead += 1;
}

fn getFields(self: *Self) !?[][]const u8 {
    if (try self.lineReader.readLine()) |line| {
        return try self.csvLine.parse(line);
    }
    return null;
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
