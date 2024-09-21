const std = @import("std");
const LineReader = @import("LineReader").LineReader;
const CsvLine = @import("CsvLine");

lineReader: *LineReader,
csvLine: CsvLine.CsvLine,
inputLimit: usize,
skipLine: ?std.AutoHashMap(usize, bool),
lineNumber: usize = 0,
linesRead: usize = 0,

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
        return try self.csvLine.parse(line);
    }
    return null;
}
