const std = @import("std");
const CsvLine = @import("FieldReader/CsvLine.zig");

pub const OutputFormat = enum {
    csv,
    lazyMarkdown,
    lazyJira,
    markdown,
    jira,
    table,
    html,
    htmlHandson,
    json,
    jsonArray,
    excelXml,
};

const Selection = union(enum) {
    name: []const u8,
    index: usize,
};

const OptionError = error{
    NoSuchField,
    NoHeader,
    MoreThanOneEqualInFilter,
};

pub const Options = struct {
    csvLine: ?CsvLine = null,
    allocator: std.mem.Allocator,
    inputSeparator: [1]u8 = .{','},
    inputQuoute: ?[1]u8 = null,
    outputSeparator: [1]u8 = .{','},
    outputQuoute: ?[1]u8 = null,
    fileHeader: bool = true,
    header: ?[][]const u8 = null,
    outputHeader: bool = true,
    includedFields: ?SelectionList = null,
    excludedFields: ?SelectionList = null,
    selectedIndices: ?[]usize = null,
    excludedIndices: ?std.AutoHashMap(usize, bool) = null,
    filters: ?std.array_list.Managed(Filter) = null,
    filtersOut: ?std.array_list.Managed(Filter) = null,
    trim: bool = false,
    outputFormat: OutputFormat = .csv,
    listHeader: bool = false,
    inputFiles: std.array_list.Managed([]const u8),
    skipLine: ?std.AutoHashMap(usize, bool) = null,
    unique: bool = false,
    count: bool = false,
    inputLimit: usize = 0,
    outputLimit: usize = 0,
    lengths: ?std.array_list.Managed(usize) = null,
    extraLineEnd: u2 = 0,
    outputName: ?[]const u8 = null,
    time: bool = false,

    pub fn init(allocator: std.mem.Allocator) !Options {
        return .{
            .allocator = allocator,
            .inputFiles = std.array_list.Managed([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Options) void {
        self.inputFiles.deinit();
        if (self.includedFields) |selectedFields| {
            selectedFields.deinit();
        }
        if (self.selectedIndices) |selectedIndices| {
            self.allocator.free(selectedIndices);
        }
        if (self.filters) |filters| {
            filters.deinit();
        }
        if (self.filtersOut) |filtersOut| {
            filtersOut.deinit();
        }
        if (self.excludedFields) |selectedFields| {
            selectedFields.deinit();
        }
        if (self.excludedIndices != null) {
            self.excludedIndices.?.deinit();
        }
        if (self.header) |header| {
            self.allocator.free(header);
        }
        if (self.csvLine != null) {
            self.csvLine.?.deinit();
        }
        if (self.skipLine != null) {
            self.skipLine.?.deinit();
        }
    }

    pub fn setHeader(self: *Options, header: []const u8) !void {
        self.header = try self.allocator.dupe([]const u8, try (try self.getCsvLine()).parse(header));
    }

    pub fn setHeaderFields(self: *Options, fields: [][]const u8) !void {
        self.header = try self.allocator.dupe([]const u8, fields);
    }

    fn getCsvLine(self: *Options) !*CsvLine {
        if (self.csvLine == null) {
            self.csvLine = try CsvLine.init(self.allocator, .{ .trim = self.trim });
        }
        return &(self.csvLine.?);
    }

    pub fn addInclude(self: *Options, fields: []const u8) !void {
        if (self.excludedFields != null) {
            return error.IncludeAndExcludeTogether;
        } else if (self.includedFields == null) {
            self.includedFields = try SelectionList.init(self.allocator);
        }
        for ((try (try self.getCsvLine()).parse(fields))) |field| {
            try self.includedFields.?.append(field);
        }
    }

    pub fn addExclude(self: *Options, fields: []const u8) !void {
        if (self.includedFields != null) {
            return error.IncludeAndExcludeTogether;
        } else if (self.excludedFields == null) {
            self.excludedFields = try SelectionList.init(self.allocator);
        }
        for ((try (try self.getCsvLine()).parse(fields))) |field| {
            try self.excludedFields.?.append(field);
        }
    }

    pub fn calculateFieldIndices(self: *Options) !void {
        if (self.includedFields != null) {
            self.selectedIndices = try self.includedFields.?.calculateIndices(self.header);
        } else if (self.excludedFields != null) {
            self.excludedIndices = std.AutoHashMap(usize, bool).init(self.allocator);
            for (try self.excludedFields.?.calculateIndices(self.header)) |index| {
                try self.excludedIndices.?.put(index, true);
            }
        }
        if (self.filters != null) {
            for (0..self.filters.?.items.len) |i| {
                try self.filters.?.items[i].calculateIndices(self.header);
            }
        }
        if (self.filtersOut != null) {
            for (0..self.filtersOut.?.items.len) |i| {
                try self.filtersOut.?.items[i].calculateIndices(self.header);
            }
        }
    }

    pub fn addFilter(self: *Options, filterList: []const u8) !void {
        if (self.filters == null) {
            self.filters = std.array_list.Managed(Filter).init(self.allocator);
        }
        const list = (try (try self.getCsvLine()).parse(filterList));

        try self.filters.?.append(try Filter.init(self.allocator));
        for (list) |filterString| {
            try self.filters.?.items[self.filters.?.items.len - 1].append(filterString);
        }
    }

    pub fn addFilterOut(self: *Options, filterList: []const u8) !void {
        if (self.filtersOut == null) {
            self.filtersOut = std.array_list.Managed(Filter).init(self.allocator);
        }
        const list = (try (try self.getCsvLine()).parse(filterList));

        try self.filtersOut.?.append(try Filter.init(self.allocator));
        for (list) |filterString| {
            try self.filtersOut.?.items[self.filtersOut.?.items.len - 1].append(filterString);
        }
    }

    pub fn addSkipLines(self: *Options, list: []const u8) !void {
        if (self.skipLine == null) {
            self.skipLine = std.AutoHashMap(usize, bool).init(self.allocator);
        }
        for ((try (try self.getCsvLine()).parse(list))) |item| {
            const lineNumber = try std.fmt.parseInt(usize, item, 10);
            try self.skipLine.?.put(lineNumber, true);
        }
    }

    pub fn setInputLimit(self: *Options, value: []const u8) !void {
        self.inputLimit = try std.fmt.parseInt(usize, value, 10);
    }

    pub fn setOutputLimit(self: *Options, value: []const u8) !void {
        self.outputLimit = try std.fmt.parseInt(usize, value, 10);
    }

    pub fn setLenghts(self: *Options, value: []const u8) !void {
        self.lengths = try std.array_list.Managed(usize).initCapacity(self.allocator, 16);
        for (try (try self.getCsvLine()).parse(value)) |len| {
            try self.lengths.?.append(try std.fmt.parseInt(usize, len, 10));
        }
    }
};

pub const Filter = struct {
    selectionList: SelectionList,
    values: std.array_list.Managed([]const u8),

    pub fn init(allocator: std.mem.Allocator) !Filter {
        return .{
            .selectionList = try SelectionList.init(allocator),
            .values = std.array_list.Managed([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Filter) void {
        self.selectionList.deinit();
        self.values.deinit();
    }

    pub fn append(self: *Filter, filter: []const u8) !void {
        var it = std.mem.splitScalar(u8, filter, '=');
        if (it.next()) |field| {
            try self.selectionList.append(field);
        }
        if (it.next()) |value| {
            try self.values.append(value);
        } else {
            try self.values.append("");
        }
        if (it.next()) |_| {
            return OptionError.MoreThanOneEqualInFilter;
        }
    }

    pub fn calculateIndices(self: *Filter, header: ?[][]const u8) !void {
        _ = try self.selectionList.calculateIndices(header);
    }

    pub fn matches(self: *const Filter, fields: [][]const u8) bool {
        for (self.selectionList.indices.?, 0..) |fieldIndex, i| {
            if (!std.mem.eql(u8, fields[fieldIndex], self.values.items[i])) {
                return false;
            }
        }
        return true;
    }
};

const SelectionList = struct {
    allocator: std.mem.Allocator,
    list: std.array_list.Managed(Selection),
    indices: ?[]usize = null,

    pub fn init(allocator: std.mem.Allocator) !SelectionList {
        return .{
            .allocator = allocator,
            .list = std.array_list.Managed(Selection).init(allocator),
        };
    }

    pub fn deinit(self: *const SelectionList) void {
        self.list.deinit();
        if (self.indices) |indices| {
            self.allocator.free(indices);
        }
    }

    pub fn append(self: *SelectionList, field: []const u8) !void {
        if (isRange(field)) |minusPos| {
            try addRange(&self.list, field, minusPos);
        } else if (toNumber(field)) |index| {
            try self.list.append(.{ .index = index - 1 });
        } else if (field[0] == '\\') {
            try self.list.append(.{ .name = field[1..] });
        } else {
            try self.list.append(.{ .name = field });
        }
    }

    pub fn calculateIndices(self: *SelectionList, header: ?[][]const u8) ![]usize {
        self.indices = try self.allocator.alloc(usize, self.list.items.len);
        for (self.list.items, 0..) |item, i| {
            switch (item) {
                .index => |index| self.indices.?[i] = index,
                .name => |name| self.indices.?[i] = try getHeaderIndex(header, name),
            }
        }
        return self.indices.?;
    }

    fn isRange(field: []const u8) ?usize {
        if (field.len < 3) return null;
        var minusPos: ?usize = null;
        for (field, 0..) |char, index| {
            if (std.mem.indexOfScalar(u8, "0123456789-", char)) |pos| {
                if (pos == 10 and index > 0 and index < field.len - 1) {
                    minusPos = index;
                }
            } else {
                return null;
            }
        }
        return minusPos;
    }

    fn addRange(list: *std.array_list.Managed(Selection), field: []const u8, miusPos: usize) !void {
        if (toNumber(field[0..miusPos])) |from| {
            if (toNumber(field[miusPos + 1 ..])) |to| {
                for (from..to + 1) |index| {
                    try list.append(.{ .index = index - 1 });
                }
            }
        }
    }

    fn toNumber(field: []const u8) ?usize {
        return std.fmt.parseInt(usize, field, 10) catch null;
    }

    fn getHeaderIndex(header: ?[][]const u8, search: []const u8) OptionError!usize {
        if (header == null) {
            return OptionError.NoHeader;
        }

        return for (header.?, 0..) |field, index| {
            if (std.mem.eql(u8, field, search)) {
                break index;
            }
        } else OptionError.NoSuchField;
    }
};
