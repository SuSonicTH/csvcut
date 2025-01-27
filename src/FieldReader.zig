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
selectedIndices: ?[]usize = null,
excludedIndices: ?std.AutoHashMap(usize, bool) = null,
selected: ?[][]const u8 = null,
filters: ?std.ArrayList(Filter) = null,
filtersOut: ?std.ArrayList(Filter) = null,
readerImpl: ReaderImpl,

const Self = @This();

pub fn initCsvFile(file: *std.fs.File, inputLimit: usize, skipLine: ?std.AutoHashMap(usize, bool), csvLineOptions: CsvLine.Options, allocator: std.mem.Allocator) !Self {
    return .{
        .readerImpl = try ReaderImpl.initCsvFile(file, csvLineOptions, allocator),
        .allocator = allocator,
        .inputLimit = inputLimit,
        .skipLine = skipLine,
    };
}

pub fn initCsvReader(reader: std.io.AnyReader, inputLimit: usize, skipLine: ?std.AutoHashMap(usize, bool), csvLineOptions: CsvLine.Options, allocator: std.mem.Allocator) !Self {
    return .{
        .readerImpl = try ReaderImpl.initCsvReader(reader, csvLineOptions, allocator),
        .allocator = allocator,
        .inputLimit = inputLimit,
        .skipLine = skipLine,
    };
}

pub fn initWidthFile(file: *std.fs.File, widhts: []usize, trim: bool, inputLimit: usize, skipLine: ?std.AutoHashMap(usize, bool), extraLineEnd: u2, allocator: std.mem.Allocator) !Self {
    return .{
        .readerImpl = try ReaderImpl.initWidthFile(file, widhts, trim, extraLineEnd, allocator),
        .allocator = allocator,
        .inputLimit = inputLimit,
        .skipLine = skipLine,
    };
}

pub fn initWidthReader(reader: std.io.AnyReader, widhts: []usize, trim: bool, inputLimit: usize, skipLine: ?std.AutoHashMap(usize, bool), extraLineEnd: u2, allocator: std.mem.Allocator) !Self {
    return .{
        .readerImpl = try ReaderImpl.initWidthReader(reader, widhts, trim, extraLineEnd, allocator),
        .allocator = allocator,
        .inputLimit = inputLimit,
        .skipLine = skipLine,
    };
}

pub fn deinit(self: *Self) void {
    self.readerImpl.deinit();
    if (self.selectedIndices != null) {
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

        if (try self.readerImpl.getFields()) |fields| {
            if (self.noFilterOrfilterMatches(fields)) {
                return self.getSelectedFields(fields);
            }
        } else {
            return null;
        }
    }
}

pub inline fn skipOneLine(self: *Self) !void {
    _ = try self.readerImpl.getFields();
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

const ReaderImpl = union(enum) {
    csvFile: CsvFileReader,
    csvReader: CsvReader,
    widthFile: WidthFileReader,
    widthReader: WidthReader,

    fn initCsvFile(file: *std.fs.File, csvLineOptions: CsvLine.Options, allocator: std.mem.Allocator) !ReaderImpl {
        return .{
            .csvFile = try CsvFileReader.init(file, csvLineOptions, allocator),
        };
    }

    fn initCsvReader(reader: std.io.AnyReader, csvLineOptions: CsvLine.Options, allocator: std.mem.Allocator) !ReaderImpl {
        return .{
            .csvReader = try CsvReader.init(reader, csvLineOptions, allocator),
        };
    }

    fn initWidthFile(file: *std.fs.File, widhts: []usize, trim: bool, extraLineEnd: u2, allocator: std.mem.Allocator) !ReaderImpl {
        return .{
            .widthFile = try WidthFileReader.init(file, widhts, trim, extraLineEnd, allocator),
        };
    }

    fn initWidthReader(reader: std.io.AnyReader, widhts: []usize, trim: bool, extraLineEnd: u2, allocator: std.mem.Allocator) !ReaderImpl {
        return .{
            .widthReader = try WidthReader.init(reader, widhts, trim, extraLineEnd, allocator),
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

const CsvFileReader = struct {
    lineReader: LineReader,
    csvLine: ?CsvLine.CsvLine = null,

    fn init(file: *std.fs.File, csvLineOptions: CsvLine.Options, allocator: std.mem.Allocator) !CsvFileReader {
        var ret: CsvFileReader = .{
            .lineReader = try LineReader.initFile(file, allocator, .{}),
        };

        errdefer ret.lineReader.deinit();
        ret.csvLine = try CsvLine.CsvLine.init(allocator, csvLineOptions);
        return ret;
    }

    fn deinit(self: *CsvFileReader) void {
        self.lineReader.deinit();
        if (self.csvLine) |csvLine| {
            csvLine.free();
        }
    }

    fn reset(self: *CsvFileReader) !void {
        try self.lineReader.reset();
    }

    fn skipLine(self: *CsvFileReader) !void {
        _ = try self.lineReader.readLine();
    }

    fn getFields(self: *CsvFileReader) !?[][]const u8 {
        if (try self.lineReader.readLine()) |line| {
            return try self.csvLine.?.parse(line);
        }
        return null;
    }
};

const CsvReader = struct {
    lineReader: LineReader,
    csvLine: CsvLine.CsvLine = undefined,

    fn init(reader: std.io.AnyReader, csvLineOptions: CsvLine.Options, allocator: std.mem.Allocator) !CsvReader {
        var csvReader: CsvReader = .{
            .lineReader = try LineReader.initReader(reader, allocator, .{}),
        };
        errdefer csvReader.lineReader.deinit();
        csvReader.csvLine = try CsvLine.CsvLine.init(allocator, csvLineOptions);
        return csvReader;
    }

    fn deinit(self: *CsvReader) void {
        self.csvLine.free();
    }

    fn reset(self: *CsvReader) !void {
        try self.lineReader.reset();
    }

    fn skipLine(self: *CsvReader) !void {
        _ = try self.lineReader.readLine();
    }

    fn getFields(self: *CsvReader) !?[][]const u8 {
        if (try self.lineReader.readLine()) |line| {
            return try self.csvLine.parse(line);
        }
        return null;
    }
};

const FieldProperty = struct {
    pos: usize,
    length: usize,
};

fn calculateFieldProperties(widhts: []usize, recordSize: *usize, allocator: std.mem.Allocator) ![]FieldProperty {
    var fieldProperties = try allocator.alloc(FieldProperty, widhts.len);
    var start: usize = 0;
    for (widhts, 0..) |width, i| {
        fieldProperties[i].pos = start;
        fieldProperties[i].length = width;
        start += width;
    }
    recordSize.* = start;
    return fieldProperties[0..widhts.len];
}

const WidthFileReader = struct {
    allocator: std.mem.Allocator,
    memMapper: MemMapper,
    trim: bool,
    data: []u8 = undefined,
    fieldProperties: ?[]FieldProperty = null,
    recordSize: usize = 0,
    fields: ?[][]const u8 = undefined,
    pos: usize = 0,
    extraLineEnd: u2,

    fn init(file: *std.fs.File, widhts: []usize, trim: bool, extraLineEnd: u2, allocator: std.mem.Allocator) !WidthFileReader {
        var reader: WidthFileReader = .{
            .allocator = allocator,
            .memMapper = try MemMapper.init(file.*, false),
            .trim = trim,
            .extraLineEnd = extraLineEnd,
        };
        errdefer reader.deinit();
        reader.data = try reader.memMapper.map(u8, .{});
        reader.fieldProperties = try calculateFieldProperties(widhts, &reader.recordSize, allocator);
        reader.fields = try allocator.alloc([]const u8, widhts.len);
        return reader;
    }

    fn deinit(self: *WidthFileReader) void {
        self.memMapper.unmap(self.data);
        self.memMapper.deinit();
        if (self.fieldProperties) |properties| {
            self.allocator.free(properties);
        }
        if (self.fields) |fields| {
            self.allocator.free(fields);
        }
    }

    fn reset(self: *WidthFileReader) !void {
        self.pos = 0;
    }

    fn skipLine(self: *WidthFileReader) !void {
        _ = try self.readLine();
    }

    inline fn readLine(self: *WidthFileReader) !?[]const u8 {
        if (self.pos + self.recordSize <= self.data.len) {
            const current = self.pos;
            self.pos += self.recordSize + self.extraLineEnd;
            return self.data[current .. current + self.recordSize];
        }
        return null;
    }

    fn getFields(self: *WidthFileReader) !?[][]const u8 {
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

const WidthReader = struct {
    allocator: std.mem.Allocator,
    reader: std.io.AnyReader,
    trim: bool,
    fieldProperties: ?[]FieldProperty = null,
    recordSize: usize = 0,
    fields: [][]const u8,
    data: ?[]u8 = null,
    pos: usize = 0,
    end: usize = 0,
    extraLineEnd: u2,

    fn init(anyReader: std.io.AnyReader, widhts: []usize, trim: bool, extraLineEnd: u2, allocator: std.mem.Allocator) !WidthReader {
        var reader: WidthReader = .{
            .allocator = allocator,
            .reader = anyReader,
            .trim = trim,
            .fields = try allocator.alloc([]const u8, widhts.len),
            .extraLineEnd = extraLineEnd,
        };
        errdefer reader.deinit();
        reader.fieldProperties = try calculateFieldProperties(widhts, &reader.recordSize, allocator);
        reader.data = try allocator.alloc(u8, (reader.recordSize + extraLineEnd) * 100);
        _ = try reader.fillBuffer();
        return reader;
    }

    fn deinit(self: *WidthReader) void {
        self.allocator.free(self.fields);
        if (self.fieldProperties) |properties| {
            self.allocator.free(properties);
        }
        if (self.data) |records| {
            self.allocator.free(records);
        }
    }

    inline fn fillBuffer(self: *WidthReader) !bool {
        self.pos = 0;
        self.end = try self.reader.readAll(self.data.?);
        return self.end >= self.recordSize;
    }

    fn reset(self: *WidthReader) !void {
        _ = self;
        return error.Unsupported;
    }

    fn skipLine(self: *WidthReader) !void {
        _ = try self.readLine();
    }

    inline fn readLine(self: *WidthReader) !?[]const u8 {
        if (self.pos + self.recordSize > self.end) {
            if (!(try self.fillBuffer())) {
                return null;
            }
        }
        const current = self.pos;
        self.pos += self.recordSize + self.extraLineEnd;
        return self.data.?[current .. current + self.recordSize];
    }

    fn getFields(self: *WidthReader) !?[][]const u8 {
        if (try self.readLine()) |line| {
            for (self.fieldProperties.?, 0..) |property, i| {
                if (self.trim) {
                    self.fields[i] = std.mem.trim(u8, line[property.pos .. property.pos + property.length], " \t");
                } else {
                    self.fields[i] = line[property.pos .. property.pos + property.length];
                }
            }
            return self.fields;
        }
        return null;
    }
};
