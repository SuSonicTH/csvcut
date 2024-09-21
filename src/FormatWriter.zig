const std = @import("std");
const OutputFormat = @import("options.zig").OutputFormat;
const CsvWriter = @import("FormatWriter/CsvWriter.zig");
const LazyMarkdown = @import("FormatWriter/LazyMarkdown.zig");
const LazyJira = @import("FormatWriter/LazyJira.zig");

pub const NoOption: FormatWriterOptions = .{ .csv = .{} };

pub const FormatWriterOptions = union(OutputFormat) {
    csv: CsvWriter.Options,
    lazyMarkdown: LazyMarkdown.Options,
    lazyJira: LazyJira.Options,
    markdown: MarkdownOptions,
    jira: JiraOptions,
    table: TableOptions,
    html: HtmlOptions,
};

pub const MarkdownOptions = struct {};
pub const JiraOptions = struct {};
pub const TableOptions = struct {};
pub const HtmlOptions = struct {};

pub const FormatWriter = union(OutputFormat) {
    csv: CsvWriter,
    lazyMarkdown: LazyMarkdown,
    lazyJira: LazyJira,
    markdown: MarkdownWriter,
    jira: JiraWriter,
    table: TableWriter,
    html: HtmlWriter,

    pub fn init(format: OutputFormat, options: FormatWriterOptions) !FormatWriter {
        return switch (format) {
            .csv => .{ .csv = try CsvWriter.init(options.csv) },
            .lazyMarkdown => .{ .lazyMarkdown = try LazyMarkdown.init(options.lazyMarkdown) },
            .lazyJira => .{ .lazyJira = try LazyJira.init(options.lazyJira) },
            .markdown => .{ .markdown = try MarkdownWriter.init(options) },
            .jira => .{ .jira = try JiraWriter.init(options) },
            .table => .{ .table = try TableWriter.init(options) },
            .html => .{ .html = try HtmlWriter.init(options) },
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

pub const MarkdownWriter = struct {
    options: FormatWriterOptions,

    pub fn init(options: FormatWriterOptions) !MarkdownWriter {
        return .{
            .options = options,
        };
    }

    pub fn start(self: *MarkdownWriter, writer: *const std.io.AnyWriter) !void {
        _ = self;
        _ = writer;
    }

    pub fn writeHeader(self: *MarkdownWriter, writer: *const std.io.AnyWriter, fields: *const [][]const u8) !void {
        _ = self;
        _ = writer;
        _ = fields;
    }

    pub fn writeData(self: *MarkdownWriter, writer: *const std.io.AnyWriter, fields: *const [][]const u8) !void {
        _ = self;
        _ = writer;
        _ = fields;
    }

    pub fn end(self: *MarkdownWriter, writer: *const std.io.AnyWriter) !void {
        _ = self;
        _ = writer;
    }
};

pub const JiraWriter = struct {
    options: FormatWriterOptions,

    pub fn init(options: FormatWriterOptions) !JiraWriter {
        return .{
            .options = options,
        };
    }

    pub fn start(self: *JiraWriter, writer: *const std.io.AnyWriter) !void {
        _ = self;
        _ = writer;
    }

    pub fn writeHeader(self: *JiraWriter, writer: *const std.io.AnyWriter, fields: *const [][]const u8) !void {
        _ = self;
        _ = writer;
        _ = fields;
    }

    pub fn writeData(self: *JiraWriter, writer: *const std.io.AnyWriter, fields: *const [][]const u8) !void {
        _ = self;
        _ = writer;
        _ = fields;
    }

    pub fn end(self: *JiraWriter, writer: *const std.io.AnyWriter) !void {
        _ = self;
        _ = writer;
    }
};

pub const TableWriter = struct {
    options: FormatWriterOptions,

    pub fn init(options: FormatWriterOptions) !TableWriter {
        return .{
            .options = options,
        };
    }

    pub fn start(self: *TableWriter, writer: *const std.io.AnyWriter) !void {
        _ = self;
        _ = writer;
    }

    pub fn writeHeader(self: *TableWriter, writer: *const std.io.AnyWriter, fields: *const [][]const u8) !void {
        _ = self;
        _ = writer;
        _ = fields;
    }

    pub fn writeData(self: *TableWriter, writer: *const std.io.AnyWriter, fields: *const [][]const u8) !void {
        _ = self;
        _ = writer;
        _ = fields;
    }

    pub fn end(self: *TableWriter, writer: *const std.io.AnyWriter) !void {
        _ = self;
        _ = writer;
    }
};

pub const HtmlWriter = struct {
    options: FormatWriterOptions,

    pub fn init(options: FormatWriterOptions) !HtmlWriter {
        return .{
            .options = options,
        };
    }

    pub fn start(self: *HtmlWriter, writer: *const std.io.AnyWriter) !void {
        _ = self;
        _ = writer;
    }

    pub fn writeHeader(self: *HtmlWriter, writer: *const std.io.AnyWriter, fields: *const [][]const u8) !void {
        _ = self;
        _ = writer;
        _ = fields;
    }

    pub fn writeData(self: *HtmlWriter, writer: *const std.io.AnyWriter, fields: *const [][]const u8) !void {
        _ = self;
        _ = writer;
        _ = fields;
    }

    pub fn end(self: *HtmlWriter, writer: *const std.io.AnyWriter) !void {
        _ = self;
        _ = writer;
    }
};
