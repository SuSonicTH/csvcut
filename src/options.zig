const std = @import("std");
const CsvLine = @import("FieldReader/CsvLine.zig");
const ExitCode = @import("exitCode.zig").ExitCode;
const mvzr = @import("mvzr");

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
    NoEqualOrTildeInFilter,
    RegexCompileError,
    IncludeAndExcludeTogether,
    InvalidIndex,
    InvalidRange,
    InvalidLength,
    InvalidNumber,
    EmptyField,
};

pub const Options = struct {
    csvLine: ?CsvLine = null,
    allocator: std.mem.Allocator,
    inputSeparator: [1]u8 = .{','},
    inputQuote: ?[1]u8 = null,
    outputSeparator: [1]u8 = .{','},
    outputQuote: ?[1]u8 = null,
    fileHeader: bool = true,
    header: ?[][]const u8 = null,
    headerOwned: bool = false,
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
            if (self.headerOwned) self.allocator.free(header);
        }
        if (self.csvLine != null) {
            self.csvLine.?.deinit();
        }
        if (self.skipLine != null) {
            self.skipLine.?.deinit();
        }
        if (self.lengths) |lengths| {
            lengths.deinit();
        }
    }

    pub fn setHeader(self: *Options, header: []const u8) !void {
        if (self.headerOwned) {
            if (self.header) |old| self.allocator.free(old);
        }
        self.header = try self.allocator.dupe([]const u8, try (try self.getCsvLine()).parse(header));
        self.headerOwned = true;
    }

    pub fn setHeaderFields(self: *Options, fields: [][]const u8) !void {
        if (self.headerOwned) {
            if (self.header) |old| self.allocator.free(old);
        }
        self.header = try self.allocator.dupe([]const u8, fields);
        self.headerOwned = true;
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
        if (self.excludedIndices) |*indices| {
            indices.deinit();
            self.excludedIndices = null;
        }

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
            const lineNumber = std.fmt.parseInt(usize, item, 10) catch return OptionError.InvalidNumber;
            try self.skipLine.?.put(lineNumber, true);
        }
    }

    pub fn setInputLimit(self: *Options, value: []const u8) !void {
        self.inputLimit = std.fmt.parseInt(usize, value, 10) catch return OptionError.InvalidNumber;
    }

    pub fn setOutputLimit(self: *Options, value: []const u8) !void {
        self.outputLimit = std.fmt.parseInt(usize, value, 10) catch return OptionError.InvalidNumber;
    }

    pub fn setLenghts(self: *Options, value: []const u8) !void {
        const list = try (try self.getCsvLine()).parse(value);
        if (list.len == 0) return OptionError.InvalidLength;

        var total: usize = 0;
        for (list) |len| {
            const width = std.fmt.parseInt(usize, len, 10) catch return OptionError.InvalidLength;
            if (width == 0) return OptionError.InvalidLength;
            total = std.math.add(usize, total, width) catch return OptionError.InvalidLength;
        }

        var lengths = try std.array_list.Managed(usize).initCapacity(self.allocator, list.len);
        errdefer lengths.deinit();
        for (list) |len| {
            try lengths.append(try std.fmt.parseInt(usize, len, 10));
        }

        if (self.lengths) |old| {
            old.deinit();
        }
        self.lengths = lengths;
    }
};

const FilterType = enum { equal, regex };
const FilterValue = struct {
    value: []const u8,
    type: FilterType,
    regex: ?mvzr.Regex,
};

pub const Filter = struct {
    selectionList: SelectionList,
    values: std.array_list.Managed(FilterValue),

    pub fn init(allocator: std.mem.Allocator) !Filter {
        return .{
            .selectionList = try SelectionList.init(allocator),
            .values = std.array_list.Managed(FilterValue).init(allocator),
        };
    }

    pub fn deinit(self: *Filter) void {
        self.selectionList.deinit();
        self.values.deinit();
    }

    pub fn append(self: *Filter, filter: []const u8) !void {
        var eqlPos: usize = 0;
        var filterType: FilterType = undefined;

        const equalPos = std.mem.indexOfScalar(u8, filter, '=');
        const regexPos = std.mem.indexOfScalar(u8, filter, '~');
        const useRegex = if (equalPos) |eq| if (regexPos) |rx| rx < eq else false else regexPos != null;

        if (useRegex) {
            eqlPos = regexPos.?;
            filterType = .regex;
        } else if (equalPos) |pos| {
            eqlPos = pos;
            filterType = .equal;
        } else {
            return OptionError.NoEqualOrTildeInFilter;
        }

        const field = filter[0..eqlPos];
        if (SelectionList.isRange(field) != null) {
            return OptionError.InvalidRange;
        }
        try self.selectionList.append(field);

        const value = filter[eqlPos + 1 ..];
        var regex: ?mvzr.Regex = null;
        if (filterType == .regex) {
            regex = mvzr.compile(value);
            if (regex == null) {
                ExitCode.regexCompileError.printErrorAndExit(.{ value, field });
            }
        }
        try self.values.append(.{ .value = value, .type = filterType, .regex = regex });
    }

    pub fn calculateIndices(self: *Filter, header: ?[][]const u8) !void {
        const indices = try self.selectionList.calculateIndices(header);
        if (header) |fields| {
            for (indices) |index| {
                if (index >= fields.len) {
                    ExitCode.fieldIndexOutOfRange.printErrorAndExit(.{ index + 1, fields.len });
                }
            }
        }
    }

    pub fn matches(self: *const Filter, fields: [][]const u8) bool {
        for (self.selectionList.indices.?, 0..) |fieldIndex, i| {
            if (fieldIndex >= fields.len) {
                return false;
            }
            const value = self.values.items[i];
            switch (value.type) {
                .equal => if (!std.mem.eql(u8, fields[fieldIndex], value.value)) {
                    return false;
                },
                .regex => if (!value.regex.?.isMatch(fields[fieldIndex])) {
                    return false;
                },
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
        if (field.len == 0) {
            return OptionError.EmptyField;
        }
        if (field.len > 1 and field[field.len - 1] == '-' and toNumber(field[0 .. field.len - 1]) != null) {
            return OptionError.InvalidRange;
        }
        if (isRange(field)) |minusPos| {
            try addRange(&self.list, field, minusPos);
        } else if (toNumber(field)) |index| {
            if (index == 0) {
                return OptionError.InvalidIndex;
            }
            try self.list.append(.{ .index = index - 1 });
        } else if (field[0] == '\\') {
            if (field.len == 1) {
                return OptionError.EmptyField;
            }
            try self.list.append(.{ .name = field[1..] });
        } else {
            try self.list.append(.{ .name = field });
        }
    }

    pub fn calculateIndices(self: *SelectionList, header: ?[][]const u8) ![]usize {
        if (self.indices) |indices| {
            self.allocator.free(indices);
        }
        self.indices = try self.allocator.alloc(usize, self.list.items.len);
        for (self.list.items, 0..) |item, i| {
            switch (item) {
                .index => |index| self.indices.?[i] = index,
                .name => |name| self.indices.?[i] = getHeaderIndex(header, name) catch |err| switch (err) {
                    error.NoHeader => ExitCode.noHeaderForSelection.printErrorAndExit(.{}),
                    error.NoSuchField => ExitCode.noSuchField.printErrorAndExit(.{name}),
                    else => return err,
                },
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

    fn addRange(list: *std.array_list.Managed(Selection), field: []const u8, minusPos: usize) !void {
        const from = toNumber(field[0..minusPos]) orelse return OptionError.InvalidRange;
        const to = toNumber(field[minusPos + 1 ..]) orelse return OptionError.InvalidRange;
        if (from == 0 or to == 0 or from > to or to == std.math.maxInt(usize)) return OptionError.InvalidRange;

        for (from..to + 1) |index| {
            try list.append(.{ .index = index - 1 });
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

const testing = std.testing;

test "selection indices are owned by the selection list" {
    var options = try Options.init(testing.allocator);
    defer options.deinit();

    try options.addInclude("1,2");
    var header = [_][]const u8{ "a", "b" };
    options.header = &header;
    options.headerOwned = false;

    try options.calculateFieldIndices();
    try testing.expectEqual(@as(usize, 2), options.selectedIndices.?.len);
    try testing.expectEqual(@as(usize, 0), options.selectedIndices.?[0]);
    try testing.expectEqual(@as(usize, 1), options.selectedIndices.?[1]);
}

test "setting a header twice frees the first one" {
    var options = try Options.init(testing.allocator);
    defer options.deinit();

    try options.setHeader("a,b");
    try options.setHeader("c,d,e");
    try testing.expectEqual(@as(usize, 3), options.header.?.len);
}

test "reject invalid field indices" {
    var options = try Options.init(testing.allocator);
    defer options.deinit();

    try testing.expectError(OptionError.InvalidIndex, options.addInclude("0"));
    try testing.expectError(OptionError.InvalidRange, options.addInclude("2-1"));
    try testing.expectError(OptionError.EmptyField, options.addInclude("1,"));
}

test "reject invalid lengths" {
    var options = try Options.init(testing.allocator);
    defer options.deinit();

    try testing.expectError(OptionError.InvalidLength, options.setLenghts("0"));
    try testing.expectError(OptionError.InvalidLength, options.setLenghts("1,0"));
    try testing.expectError(OptionError.InvalidLength, options.setLenghts("18446744073709551615,1"));

    try options.setLenghts("2,3");
    try testing.expectEqual(@as(usize, 2), options.lengths.?.items.len);
    try testing.expectEqual(@as(usize, 3), options.lengths.?.items[1]);
}

test "filter splits on the first separator" {
    var filter = try Filter.init(testing.allocator);
    defer filter.deinit();

    try filter.append("a~x=y");
    try testing.expectEqual(FilterType.regex, filter.values.items[0].type);
    try testing.expectEqualStrings("x=y", filter.values.items[0].value);

    try filter.append("b=c~d");
    try testing.expectEqual(FilterType.equal, filter.values.items[1].type);
    try testing.expectEqualStrings("c~d", filter.values.items[1].value);
}
