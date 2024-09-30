const std = @import("std");
const CsvLine = @import("CsvLine").CsvLine;
const OutputFormat = @import("options.zig").OutputFormat;
const FieldReader = @import("FieldReader.zig");
const escape = @import("FormatWriter/escape.zig");

const Self = @This();

allocator: ?std.mem.Allocator = null,
widths: []usize = undefined,
maxSpace: usize = undefined,

pub fn init(outputFormat: OutputFormat, fileHeader: bool, header: ?[][]const u8, fieldReader: *FieldReader, allocator: std.mem.Allocator) !Self {
    switch (outputFormat) {
        .markdown, .jira, .table => {
            const widths = try collectWidths(fieldReader, header, allocator, outputFormat);
            try resetReader(fieldReader, fileHeader);

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

fn collectWidths(fieldReader: *FieldReader, header: ?[][]const u8, allocator: std.mem.Allocator, outputFormat: OutputFormat) ![]usize {
    var fieldWidths: []usize = undefined;
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

inline fn resetReader(fieldReader: *FieldReader, fileHeader: bool) !void {
    try fieldReader.reset();
    if (fileHeader) {
        if (try fieldReader.readLine()) |line| {
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
