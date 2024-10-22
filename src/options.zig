const std = @import("std");
const CsvLine = @import("CsvLine").CsvLine;

pub const Filter = struct {
    field: []const u8 = undefined,
    value: []const u8 = undefined,
    index: usize = undefined,
};

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
    includedFields: ?std.ArrayList(Selection) = null,
    excludedFields: ?std.ArrayList(Selection) = null,
    selectedIndices: ?[]usize = null,
    excludedIndices: ?std.AutoHashMap(usize, bool) = null,
    trim: bool = false,
    filterFields: ?std.ArrayList(Filter) = null,
    outputFormat: OutputFormat = .csv,
    listHeader: bool = false,
    useStdin: bool = false,
    inputFiles: std.ArrayList([]const u8),
    skipLine: ?std.AutoHashMap(usize, bool) = null,
    unique: bool = false,
    count: bool = false,
    inputLimit: usize = 0,
    outputLimit: usize = 0,
    lengths: ?std.ArrayList(usize) = null,
    extraLineEnd: u2 = 0,
    outputName: ?[]const u8 = null,
    time: bool = false,

    pub fn init(allocator: std.mem.Allocator) !Options {
        return .{
            .allocator = allocator,
            .inputFiles = std.ArrayList([]const u8).init(allocator),
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
            self.csvLine.?.free();
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
            self.includedFields = std.ArrayList(Selection).init(self.allocator);
        }
        for ((try (try self.getCsvLine()).parse(fields))) |field| {
            if (toNumber(field)) |index| {
                try self.includedFields.?.append(.{ .index = index - 1 });
            } else if (field[0] == '\\') {
                try self.includedFields.?.append(.{ .name = field[1..] });
            } else {
                try self.includedFields.?.append(.{ .name = field });
            }
        }
    }

    pub fn addExclude(self: *Options, fields: []const u8) !void {
        if (self.includedFields != null) {
            return error.IncludeAndExcludeTogether;
        } else if (self.excludedFields == null) {
            self.excludedFields = std.ArrayList(Selection).init(self.allocator);
        }
        for ((try (try self.getCsvLine()).parse(fields))) |field| {
            if (toNumber(field)) |index| {
                try self.excludedFields.?.append(.{ .index = index - 1 });
            } else if (field[0] == '\\') {
                try self.excludedFields.?.append(.{ .name = field[1..] });
            } else {
                try self.excludedFields.?.append(.{ .name = field });
            }
        }
    }

    fn toNumber(field: []const u8) ?usize {
        return std.fmt.parseInt(usize, field, 10) catch null;
    }

    pub fn calculateSelectedIndices(self: *Options) !void {
        if ((self.includedFields == null and self.excludedFields == null) or self.selectedIndices != null or self.excludedIndices != null) return;

        if (self.includedFields != null) {
            self.selectedIndices = try self.allocator.alloc(usize, self.includedFields.?.items.len);
            for (self.includedFields.?.items, 0..) |item, i| {
                switch (item) {
                    .index => |index| self.selectedIndices.?[i] = index,
                    .name => |name| self.selectedIndices.?[i] = try getHeaderIndex(self, name),
                }
            }
        } else {
            self.excludedIndices = std.AutoHashMap(usize, bool).init(self.allocator);
            for (self.excludedFields.?.items) |item| {
                switch (item) {
                    .index => |index| try self.excludedIndices.?.put(index, true),
                    .name => |name| try self.excludedIndices.?.put(try getHeaderIndex(self, name), true),
                }
            }
        }
    }

    pub fn setFilterIndices(self: *Options) OptionError!void {
        if (self.filterFields == null) return;
        for (0..self.filterFields.?.items.len) |i| {
            self.filterFields.?.items[i].index = try getHeaderIndex(self, self.filterFields.?.items[i].field);
        }
    }

    fn getHeaderIndex(self: *Options, search: []const u8) OptionError!usize {
        if (self.header == null) {
            return OptionError.NoHeader;
        }

        return for (self.header.?, 0..) |field, index| {
            if (std.mem.eql(u8, field, search)) {
                break index;
            }
        } else OptionError.NoSuchField;
    }

    pub fn addFilter(self: *Options, filterList: []const u8) !void {
        if (self.filterFields == null) {
            self.filterFields = std.ArrayList(Filter).init(self.allocator);
        }
        for ((try (try self.getCsvLine()).parse(filterList))) |filterString| {
            var filter: Filter = .{};
            var it = std.mem.split(u8, filterString, "=");
            var i: u8 = 0;
            while (it.next()) |value| {
                switch (i) {
                    0 => filter.field = value,
                    1 => filter.value = value,
                    else => return OptionError.MoreThanOneEqualInFilter,
                }
                i += 1;
            }
            try self.filterFields.?.append(filter);
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
        self.lengths = try std.ArrayList(usize).initCapacity(self.allocator, 16);
        for (try (try self.getCsvLine()).parse(value)) |len| {
            try self.lengths.?.append(try std.fmt.parseInt(usize, len, 10));
        }
    }
};
