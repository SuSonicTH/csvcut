const std = @import("std");
const LineReader = @import("LineReader").LineReader;
const CsvLine = @import("CsvLine");
const Filter = @import("options.zig").Filter;
const MemMapper = @import("MemMapper").MemMapper;

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

pub fn initWidth(file: *std.fs.File, widhts: []usize, trim: bool, inputLimit: usize, skipLine: ?std.AutoHashMap(usize, bool), allocator: std.mem.Allocator) !Self {
    return .{
        .readerImpl = try ReaderImpl.initWidth(file, widhts, trim, allocator),
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

    fn initWidth(file: *std.fs.File, widhts: []usize, trim: bool, allocator: std.mem.Allocator) !ReaderImpl {
        return .{
            .width = try WidthReader.init(file, widhts, trim, allocator),
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

const FieldProperty = struct {
    pos: usize,
    length: usize,
};

const WidthReader = struct {
    allocator: std.mem.Allocator,
    memMapper: MemMapper,
    trim: bool,
    data: []u8 = undefined,
    fieldProperties: ?[]FieldProperty = null,
    recordSize: usize = 0,
    fields: ?[][]const u8 = undefined,
    pos: usize = 0,

    fn init(file: *std.fs.File, widhts: []usize, trim: bool, allocator: std.mem.Allocator) !WidthReader {
        var reader: WidthReader = .{
            .allocator = allocator,
            .memMapper = try MemMapper.init(file.*, false),
            .trim = trim,
        };
        errdefer reader.deinit();
        reader.data = try reader.memMapper.map(u8, .{});
        reader.recordSize = try calculateFieldProperties(&reader, widhts);
        reader.fields = try allocator.alloc([]u8, widhts.len);
        return reader;
    }

    fn deinit(self: *WidthReader) void {
        self.memMapper.unmap(self.data);
        self.memMapper.deinit();
        if (self.fieldProperties) |properties| {
            self.allocator.free(properties);
        }
        if (self.fields) |fields| {
            self.allocator.free(fields);
        }
    }

    fn calculateFieldProperties(self: *WidthReader, widhts: []usize) !usize {
        self.fieldProperties = try self.allocator.alloc(FieldProperty, widhts.len);
        var start: usize = 0;
        for (widhts, 0..) |width, i| {
            self.fieldProperties.?[i].pos = start;
            self.fieldProperties.?[i].length = width;
            start += width;
        }
        return start;
    }

    fn reset(self: *WidthReader) !void {
        self.pos = 0;
    }

    fn skipLine(self: *WidthReader) !void {
        _ = try self.readLine();
    }

    inline fn readLine(self: *WidthReader) !?[]const u8 {
        if (self.pos + self.recordSize < self.data.len) {
            const current = self.pos;
            self.pos += self.recordSize;
            return self.data[current .. current + self.recordSize];
        }
        return null;
    }

    fn getFields(self: *WidthReader) !?[][]const u8 {
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
};
