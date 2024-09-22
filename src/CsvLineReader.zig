const std = @import("std");
const LineReader = @import("LineReader").LineReader;
const CsvLine = @import("CsvLine");
const Filter = @import("options.zig").Filter;

allocator: std.mem.Allocator,
lineReader: *LineReader,
csvLine: CsvLine.CsvLine,
inputLimit: usize,
skipLine: ?std.AutoHashMap(usize, bool),
lineNumber: usize = 0,
linesRead: usize = 0,
selectionIndices: ?[]usize = null,
selected: [][]const u8 = undefined,
filterFields: ?std.ArrayList(Filter) = null,

const Self = @This();

pub fn init(lineReader: *LineReader, inputLimit: usize, skipLine: ?std.AutoHashMap(usize, bool), csvLineOptions: CsvLine.Options, allocator: std.mem.Allocator) !Self {
    return .{
        .allocator = allocator,
        .lineReader = lineReader,
        .csvLine = try CsvLine.CsvLine.init(allocator, csvLineOptions),
        .inputLimit = inputLimit,
        .skipLine = skipLine,
    };
}

pub fn deinit(self: *Self) void {
    self.csvLine.deinit();
}

pub fn reset(self: *Self) !void {
    self.lineNumber = 0;
    self.linesRead = 0;
    try self.lineReader.reset();
    if (self.selectionIndices != null) {
        self.allocator.free(self.selected);
    }
}

pub fn resetLinesRead(self: *Self) void {
    self.linesRead = 0;
}

pub fn setSelectionIndices(self: *Self, selectionIndices: ?[]usize) !void {
    if (selectionIndices) |indices| {
        self.selectionIndices = indices;
        self.selected = try self.allocator.alloc([]u8, selectionIndices.?.len);
    }
}

pub fn setFilterFields(self: *Self, filterFields: ?std.ArrayList(Filter)) void {
    //_ = std.io.getStdErr().writer().print("setFilterFields\n", .{}) catch unreachable;
    self.filterFields = filterFields;
}

pub inline fn readLine(self: *Self) !?[][]const u8 {
    while (true) {
        if (self.inputLimit > 0 and self.inputLimit == self.linesRead) {
            return null;
        }

        try self.skipLines();

        self.lineNumber += 1;
        self.linesRead += 1;

        if (try self.lineReader.*.readLine()) |line| {
            const fields = try self.csvLine.parse(line);
            if (self.noFilterOrfilterMatches(fields)) {
                return self.getSelectedFields(fields);
            }
        } else {
            return null;
        }
    }
}

inline fn skipLines(self: *Self) !void {
    if (self.skipLine != null) {
        while (self.skipLine.?.get(self.lineNumber) != null) {
            _ = try self.lineReader.*.readLine();
            self.lineNumber += 1;
            self.linesRead += 1;
        }
    }
}

inline fn noFilterOrfilterMatches(self: *Self, fields: [][]const u8) bool {
    if (self.filterFields == null) {
        return true;
    }
    for (self.filterFields.?.items) |filter| {
        if (!std.mem.eql(u8, fields[filter.index], filter.value)) {
            return false;
        }
    }
    return true;
}

inline fn getSelectedFields(self: *Self, fields: [][]const u8) !?[][]const u8 {
    if (self.selectionIndices) |indices| {
        for (indices, 0..) |field, index| {
            self.selected[index] = fields[field];
        }
        return self.selected;
    } else {
        return fields;
    }
}
