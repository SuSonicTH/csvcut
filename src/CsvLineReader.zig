const std = @import("std");
const LineReader = @import("LineReader").LineReader;
const CsvLine = @import("CsvLine");

lineReader: *LineReader,
csvLine: CsvLine.CsvLine,
inputLimit: usize,
skipLine: ?std.AutoHashMap(usize, bool),
lineNumber: usize = 0,
linesRead: usize = 0,
selectionIndices: ?[]usize = null,
selected: [][]const u8 = undefined,

const Self = @This();

pub fn init(lineReader: *LineReader, inputLimit: usize, skipLine: ?std.AutoHashMap(usize, bool), csvLineOptions: CsvLine.Options, allocator: std.mem.Allocator) !Self {
    return .{
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
}

pub fn resetLinesRead(self: *Self) void {
    self.linesRead = 0;
}

pub fn setSelectionIndices(self: *Self, selectionIndices: []usize) !void {
    self.selectionIndices = selectionIndices;
    self.selected = try self.allocator.alloc([]u8, selectionIndices.len);
}

pub inline fn readLine(self: *Self) !?[][]const u8 {
    if (self.inputLimit > 0 and self.inputLimit == self.linesRead) {
        return null;
    }

    if (self.skipLine != null) {
        while (self.skipLine.?.get(self.lineNumber) != null) {
            _ = try self.lineReader.*.readLine();
            self.lineNumber += 1;
            self.linesRead += 1;
        }
    }

    self.lineNumber += 1;
    self.linesRead += 1;

    if (try self.lineReader.*.readLine()) |line| {
        return self.getSelectedFields(try self.csvLine.parse(line));
    }
    return null;
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
