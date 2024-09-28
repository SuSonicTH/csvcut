const std = @import("std");
const LineReader = @import("LineReader").LineReader;
const CsvLine = @import("CsvLine");
const Filter = @import("options.zig").Filter;

allocator: std.mem.Allocator,
inputLimit: usize,
skipLine: ?std.AutoHashMap(usize, bool),
lineNumber: usize = 0,
linesRead: usize = 0,
selectionIndices: ?[]usize = null,
selected: [][]const u8 = undefined,
filterFields: ?std.ArrayList(Filter) = null,
readerImpl: ReaderImpl,

const Self = @This();

pub fn initCsv(lineReader: *LineReader, inputLimit: usize, skipLine: ?std.AutoHashMap(usize, bool), csvLineOptions: CsvLine.Options, allocator: std.mem.Allocator) !Self {
    return .{
        .readerImpl = try ReaderImpl.initCsv(lineReader, csvLineOptions, allocator),
        .allocator = allocator,
        .inputLimit = inputLimit,
        .skipLine = skipLine,
    };
}

pub fn deinit(self: *Self) void {
    self.readerImpl.deinit();
    if (self.selectionIndices != null) {
        self.allocator.free(self.selected);
    }
}

pub fn reset(self: *Self) !void {
    self.lineNumber = 0;
    self.linesRead = 0;
    try self.readerImpl.reset();
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

        if (try self.readerImpl.getFields()) |fields| {
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
            try self.readerImpl.skipLine();
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

pub inline fn getSelectedFields(self: *Self, fields: [][]const u8) !?[][]const u8 {
    if (self.selectionIndices) |indices| {
        for (indices, 0..) |field, index| {
            self.selected[index] = fields[field];
        }
        return self.selected;
    } else {
        return fields;
    }
}

const ReaderImpl = union(enum) {
    csv: CsvReader,
    width: WidthReader,

    fn initCsv(lineReader: *LineReader, csvLineOptions: CsvLine.Options, allocator: std.mem.Allocator) !ReaderImpl {
        return .{
            .csv = try CsvReader.init(lineReader, csvLineOptions, allocator),
        };
    }

    fn initWidth() !ReaderImpl {
        return .{
            .width = WidthReader.init(),
        };
    }

    pub fn deinit(self: *ReaderImpl) !void {
        switch (self.*) {
            inline else => |*readerImpl| try readerImpl.deinit(),
        }
    }

    pub fn reset(self: *ReaderImpl) !void {
        switch (self.*) {
            inline else => |*readerImpl| try readerImpl.reset(),
        }
    }

    pub fn skipLine(self: *ReaderImpl) !void {
        switch (self.*) {
            inline else => |*readerImpl| try readerImpl.skipLine(),
        }
    }

    pub fn getFields(self: *ReaderImpl) !?[][]const u8 {
        switch (self.*) {
            inline else => |*readerImpl| return try readerImpl.getFields(),
        }
    }
};

const CsvReader = struct {
    lineReader: *LineReader,
    csvLine: CsvLine.CsvLine,

    fn init(lineReader: *LineReader, csvLineOptions: CsvLine.Options, allocator: std.mem.Allocator) !CsvReader {
        return .{
            .lineReader = lineReader,
            .csvLine = try CsvLine.CsvLine.init(allocator, csvLineOptions),
        };
    }

    fn deinit(self: *CsvReader) void {
        self.csvLine.free();
    }

    fn reset(self: *CsvReader) !void {
        try self.lineReader.reset();
    }

    fn skipLine(self: *CsvReader) !void {
        _ = try self.lineReader.*.readLine();
    }

    fn getFields(self: *CsvReader) !?[][]const u8 {
        if (try self.lineReader.*.readLine()) |line| {
            return try self.csvLine.parse(line);
        }
        return null;
    }
};

const WidthReader = struct {
    fn init() !WidthReader {
        return .{};
    }

    fn deinit(self: *WidthReader) void {
        _ = self;
    }

    fn reset(self: *WidthReader) !void {
        _ = self;
    }

    fn skipLine(self: *WidthReader) !void {
        _ = self;
    }

    fn getFields(self: *WidthReader) !?[][]const u8 {
        _ = self;
        return null;
    }
};
