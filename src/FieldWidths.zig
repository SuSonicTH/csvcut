const std = @import("std");
const OutputFormat = @import("options.zig").OutputFormat;
const escape = @import("FormatWriter/escape.zig");
const Fields = @import("Aggregate.zig").Fields;
const CountAggregator = @import("Aggregate.zig").CountAggregator;

const Self = @This();

allocator: ?std.mem.Allocator = null,
widths: []usize = &.{},
maxSpace: usize = 0,

pub fn init(outputFormat: OutputFormat, fileHeader: bool, header: ?[][]const u8, fieldReader: anytype, allocator: std.mem.Allocator) !Self {
    switch (outputFormat) {
        .markdown, .jira, .table => {
            const widths = try collectWidths(fieldReader, header, allocator, outputFormat);
            try resetReader(fieldReader, fileHeader);

            return .{
                .allocator = if (widths.len > 0) allocator else null,
                .widths = widths,
                .maxSpace = calculateMaxSpace(widths),
            };
        },
        else => return .{},
    }
}

pub fn initCountAggregated(outputFormat: OutputFormat, outputHeader: ?[][]const u8, countAggregator: *CountAggregator, allocator: std.mem.Allocator) !Self {
    switch (outputFormat) {
        .markdown, .jira, .table => {
            const widths = try collectCountWidths(outputHeader, countAggregator, allocator, outputFormat);
            return .{
                .allocator = if (widths.len > 0) allocator else null,
                .widths = widths,
                .maxSpace = calculateMaxSpace(widths),
            };
        },
        else => return .{},
    }
}

pub fn deinit(self: *Self) void {
    if (self.allocator) |allocator| {
        allocator.free(self.widths);
    }
}

fn collectWidths(fieldReader: anytype, header: ?[][]const u8, allocator: std.mem.Allocator, outputFormat: OutputFormat) ![]usize {
    var fieldWidths: []usize = &.{};
    if (header) |head| {
        fieldWidths = try allocator.alloc(usize, head.len);
        @memset(fieldWidths, 0);
        updateFieldWidths(outputFormat, head, fieldWidths);
    } else if (try fieldReader.readLine()) |fields| {
        fieldWidths = try allocator.alloc(usize, fields.len);
        @memset(fieldWidths, 0);
        updateFieldWidths(outputFormat, fields, fieldWidths);
    }
    while (try fieldReader.readLine()) |fields| {
        updateFieldWidths(outputFormat, fields, fieldWidths);
    }
    return fieldWidths;
}

fn collectCountWidths(outputHeader: ?[][]const u8, countAggregator: *CountAggregator, allocator: std.mem.Allocator, outputFormat: OutputFormat) ![]usize {
    var fieldWidths: []usize = &.{};
    var iterator = countAggregator.countMap.iterator();

    if (outputHeader) |header| {
        fieldWidths = try allocator.alloc(usize, header.len);
        @memset(fieldWidths, 0);
        updateFieldWidths(outputFormat, header, fieldWidths);
    } else if (iterator.next()) |entry| {
        const fields = try entry.value_ptr.get();
        fieldWidths = try allocator.alloc(usize, fields.*.len);
        @memset(fieldWidths, 0);
        updateFieldWidths(outputFormat, fields.*, fieldWidths);
    }

    while (iterator.next()) |entry| {
        const fields = try entry.value_ptr.get();
        updateFieldWidths(outputFormat, fields.*, fieldWidths);
    }
    return fieldWidths;
}

inline fn updateFieldWidths(outputFormat: OutputFormat, fields: [][]const u8, fieldWidths: []usize) void {
    for (fields, 0..) |field, i| {
        if (i >= fieldWidths.len) break;
        switch (outputFormat) {
            .markdown => fieldWidths[i] = @max(fieldWidths[i], escape.markdownLen(field)),
            .jira => fieldWidths[i] = @max(fieldWidths[i], escape.jiraLen(field)),
            .table => fieldWidths[i] = @max(fieldWidths[i], field.len),
            else => undefined,
        }
    }
}

inline fn resetReader(fieldReader: anytype, fileHeader: bool) !void {
    fieldReader.reset();
    if (fileHeader) {
        try fieldReader.skipHeader();
    }
}

fn calculateMaxSpace(fieldWidths: []usize) usize {
    var maxSpace: usize = 0;
    for (fieldWidths) |width| {
        maxSpace = @max(maxSpace, width);
    }
    return maxSpace;
}
