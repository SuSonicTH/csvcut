const std = @import("std");
const OutputFormat = @import("options.zig").OutputFormat;
const CsvWriter = @import("FormatWriter/CsvWriter.zig");
const LazyMarkdown = @import("FormatWriter/LazyMarkdown.zig");
const LazyJira = @import("FormatWriter/LazyJira.zig");
const Html = @import("FormatWriter/Html.zig");
const Table = @import("FormatWriter/Table.zig");
const Markdown = @import("FormatWriter/Markdown.zig");
const Jira = @import("FormatWriter/Jira.zig");

pub const FormatWriterOptions = union(OutputFormat) {
    csv: CsvWriter.Options,
    lazyMarkdown: LazyMarkdown.Options,
    lazyJira: LazyJira.Options,
    markdown: Markdown.Options,
    jira: Jira.Options,
    table: Table.Options,
    html: Html.Options,
};

pub const JiraOptions = struct {};

pub const FormatWriter = union(OutputFormat) {
    csv: CsvWriter,
    lazyMarkdown: LazyMarkdown,
    lazyJira: LazyJira,
    markdown: Markdown,
    jira: Jira,
    table: Table,
    html: Html,

    pub fn init(format: OutputFormat, options: FormatWriterOptions) !FormatWriter {
        return switch (format) {
            .csv => .{ .csv = try CsvWriter.init(options.csv) },
            .lazyMarkdown => .{ .lazyMarkdown = try LazyMarkdown.init(options.lazyMarkdown) },
            .lazyJira => .{ .lazyJira = try LazyJira.init(options.lazyJira) },
            .markdown => .{ .markdown = try Markdown.init(options.markdown) },
            .jira => .{ .jira = try Jira.init(options.jira) },
            .table => .{ .table = try Table.init(options.table) },
            .html => .{ .html = try Html.init(options.html) },
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
