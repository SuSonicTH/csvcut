const std = @import("std");
const OutputFormat = @import("options.zig").OutputFormat;
const Options = @import("options.zig").Options;
const FieldWidths = @import("FieldWidths.zig");

const CsvWriter = @import("FormatWriter/CsvWriter.zig");
const LazyMarkdown = @import("FormatWriter/LazyMarkdown.zig");
const LazyJira = @import("FormatWriter/LazyJira.zig");
const Html = @import("FormatWriter/Html.zig");
const Table = @import("FormatWriter/Table.zig");
const Markdown = @import("FormatWriter/Markdown.zig");
const Jira = @import("FormatWriter/Jira.zig");
const Json = @import("FormatWriter/Json.zig");
const JsonArray = @import("FormatWriter/JsonArray.zig");

pub const FormatWriter = union(OutputFormat) {
    csv: CsvWriter,
    lazyMarkdown: LazyMarkdown,
    lazyJira: LazyJira,
    markdown: Markdown,
    jira: Jira,
    table: Table,
    html: Html,
    json: Json,
    jsonArray: JsonArray,

    pub fn init(options: Options, allocator: std.mem.Allocator, fieldWidths: FieldWidths) !FormatWriter {
        return switch (options.outputFormat) {
            .csv => .{ .csv = try CsvWriter.init(.{ .separator = options.output_separator, .quoute = options.output_quoute }) },
            .lazyMarkdown => .{ .lazyMarkdown = try LazyMarkdown.init() },
            .lazyJira => .{ .lazyJira = try LazyJira.init() },
            .markdown => .{ .markdown = try Markdown.init(allocator, fieldWidths) },
            .jira => .{ .jira = try Jira.init(allocator, fieldWidths) },
            .table => .{ .table = try Table.init(allocator, fieldWidths) },
            .html => .{ .html = try Html.init(.{}) },
            .json => .{ .json = try Json.init(allocator) },
            .jsonArray => .{ .jsonArray = try JsonArray.init() },
        };
    }

    pub fn start(self: *FormatWriter, writer: *const std.io.AnyWriter) !void {
        switch (self.*) {
            inline else => |*formatWriter| try formatWriter.start(writer),
        }
    }

    pub fn writeHeader(self: *FormatWriter, writer: *const std.io.AnyWriter, fields: *const [][]const u8) !void {
        switch (self.*) {
            inline else => |*formatWriter| try formatWriter.writeHeader(writer, fields),
        }
    }

    pub fn writeData(self: *FormatWriter, writer: *const std.io.AnyWriter, fields: *const [][]const u8) !void {
        switch (self.*) {
            inline else => |*formatWriter| try formatWriter.writeData(writer, fields),
        }
    }

    pub fn end(self: *FormatWriter, writer: *const std.io.AnyWriter) !void {
        switch (self.*) {
            inline else => |*formatWriter| try formatWriter.end(writer),
        }
    }
};
