const std = @import("std");
const CsvLine = @import("CsvLine").CsvLine;

pub const Filter = struct {
    field: []const u8 = undefined,
    value: []const u8 = undefined,
    index: usize = undefined,
};

pub const OutputFormat = enum {
    Csv,
    LazyMarkdown,
    LazyJira,
};

const SelectionType = enum {
    name,
    index,
};

const Selection = struct {
    type: SelectionType,
    field: []const u8,
};

const OptionError = error{
    NoSuchField,
    NoHeader,
    MoreThanOneEqualInFilter,
};

pub const Options = struct {
    csvLine: ?CsvLine = null,
    allocator: std.mem.Allocator,
    input_separator: [1]u8 = .{','},
    input_quoute: ?[1]u8 = null,
    output_separator: [1]u8 = .{','},
    output_quoute: ?[1]u8 = null,
    fileHeader: bool = true,
    header: ?[][]const u8 = null,
    outputHeader: bool = true,
    selectedFields: ?std.ArrayList(Selection) = null,
    selectionIndices: ?[]usize = null,
    trim: bool = false,
    filterFields: ?std.ArrayList(Filter) = null,
    outputFormat: OutputFormat = .Csv,
    listHeader: bool = false,
    useStdin: bool = false,
    inputFiles: std.ArrayList([]const u8),
    skipLine: ?std.AutoHashMap(usize, bool) = null,

    pub fn init(allocator: std.mem.Allocator) !Options {
        return .{
            .allocator = allocator,
            .inputFiles = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Options) void {
        self.inputFiles.deinit();
        if (self.selectedFields) |selectedFields| {
            selectedFields.deinit();
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
        self.fileHeader = false;
    }

    fn getCsvLine(self: *Options) !*CsvLine {
        if (self.csvLine == null) {
            self.csvLine = try CsvLine.init(self.allocator, .{ .trim = self.trim });
        }
        return &(self.csvLine.?);
    }

    pub fn addIndex(self: *Options, selectionType: SelectionType, fields: []u8) !void {
        if (self.selectedFields == null) {
            self.selectedFields = std.ArrayList(Selection).init(self.allocator);
        }
        for ((try (try self.getCsvLine()).parse(fields))) |field| {
            try self.selectedFields.?.append(.{ .type = selectionType, .field = field });
        }
    }

    pub fn setSelectionIndices(self: *Options) !void {
        if (self.selectedFields == null or self.selectionIndices != null) return;
        self.selectionIndices = try self.allocator.alloc(usize, self.selectedFields.?.items.len);

        for (self.selectedFields.?.items, 0..) |item, i| {
            switch (item.type) {
                .index => self.selectionIndices.?[i] = (try std.fmt.parseInt(usize, item.field, 10)) - 1,
                .name => self.selectionIndices.?[i] = try getHeaderIndex(self, item.field),
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
};
