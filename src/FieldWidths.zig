const std = @import("std");
const CsvLine = @import("CsvLine").CsvLine;
const OutputFormat = @import("options.zig").OutputFormat;
const CsvLineReader = @import("CsvLineReader.zig");
const escape = @import("FormatWriter/escape.zig");

const Self = @This();

allocator: ?std.mem.Allocator = null,
widths: []usize = undefined,
maxSpace: usize = undefined,

pub fn init(outputFormat: OutputFormat, hasHeader: bool, lineReader: *CsvLineReader, allocator: std.mem.Allocator) !Self {
    switch (outputFormat) {
        .markdown, .jira, .table => {
            if (hasHeader) {
                try lineReader.reset();
            }

            const widths = try collectWidths(lineReader, allocator, outputFormat);
            try resetReader(lineReader, hasHeader);

            return .{
                .allocator = allocator,
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

fn collectWidths(lineReader: *CsvLineReader, allocator: std.mem.Allocator, outputFormat: OutputFormat) ![]usize {
    var fieldWidths: []usize = undefined;
    if (try lineReader.readLine()) |fields| {
        fieldWidths = try allocator.alloc(usize, fields.len);
        @memset(fieldWidths, 0);
        updateFieldWidths(outputFormat, fields, fieldWidths);
    }
    while (try lineReader.readLine()) |fields| {
        updateFieldWidths(outputFormat, fields, fieldWidths);
    }
    return fieldWidths;
}

inline fn updateFieldWidths(outputFormat: OutputFormat, fields: [][]const u8, fieldWidths: []usize) void {
    for (fields, 0..) |field, i| {
        switch (outputFormat) {
            .markdown => fieldWidths[i] = @max(fieldWidths[i], (try escape.markdown(field)).len),
            .jira => fieldWidths[i] = @max(fieldWidths[i], (try escape.jira(field)).len),
            .table => fieldWidths[i] = @max(fieldWidths[i], field.len),
            else => undefined,
        }
    }
}

inline fn resetReader(lineReader: *CsvLineReader, hasHeader: bool) !void {
    try lineReader.reset();
    if (hasHeader) {
        if (try lineReader.readLine()) |line| {
            _ = line;
        }
    }
}

fn calculateMaxSpace(fieldWidths: []usize) usize {
    var maxSpace: usize = 0;
    for (fieldWidths) |width| {
        maxSpace = @max(maxSpace, width);
    }
    return maxSpace;
}
