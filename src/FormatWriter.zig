const std = @import("std");
const OutputFormat = @import("options.zig").OutputFormat;
const CsvWriter = @import("FormatWriter/CsvWriter.zig");

pub const FormatWriterOptions = union(OutputFormat) {
    csv: CsvWriter.Options,
    lazyMarkdown: LazyMarkdownOptions,
    lazyJira: LazyJiraOptions,
    markdown: MarkdownOptions,
    jira: JiraOptions,
    table: TableOptions,
    html: HtmlOptions,
};

pub const LazyMarkdownOptions = struct {};
pub const LazyJiraOptions = struct {};
pub const MarkdownOptions = struct {};
pub const JiraOptions = struct {};
pub const TableOptions = struct {};
pub const HtmlOptions = struct {};

pub const FormatWriter = union(OutputFormat) {
    csv: CsvWriter,
    lazyMarkdown: LazyMarkdownWriter,
    lazyJira: LazyJiraWriter,
    markdown: MarkdownWriter,
    jira: JiraWriter,
    table: TableWriter,
    html: HtmlWriter,

    pub fn init(format: OutputFormat, options: FormatWriterOptions) !FormatWriter {
        return switch (format) {
            .csv => .{ .csv = try CsvWriter.init(options.csv) },
            .lazyMarkdown => .{ .lazyMarkdown = try LazyMarkdownWriter.init(options) },
            .lazyJira => .{ .lazyJira = try LazyJiraWriter.init(options) },
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

pub const LazyMarkdownWriter = struct {
    options: FormatWriterOptions,

    pub fn init(options: FormatWriterOptions) !LazyMarkdownWriter {
        return .{
            .options = options,
        };
    }

    pub fn start(self: *LazyMarkdownWriter, writer: *const std.io.AnyWriter) !void {
        _ = self;
        _ = writer;
    }

    pub fn writeHeader(self: *LazyMarkdownWriter, writer: *const std.io.AnyWriter, fields: *const [][]const u8) !void {
        _ = self;
        _ = writer;
        _ = fields;
    }

    pub fn writeData(self: *LazyMarkdownWriter, writer: *const std.io.AnyWriter, fields: *const [][]const u8) !void {
        _ = self;
        _ = writer;
        _ = fields;
    }

    pub fn end(self: *LazyMarkdownWriter, writer: *const std.io.AnyWriter) !void {
        _ = self;
        _ = writer;
    }
};

pub const LazyJiraWriter = struct {
    options: FormatWriterOptions,

    pub fn init(options: FormatWriterOptions) !LazyJiraWriter {
        return .{
            .options = options,
        };
    }

    pub fn start(self: *LazyJiraWriter, writer: *const std.io.AnyWriter) !void {
        _ = self;
        _ = writer;
    }

    pub fn writeHeader(self: *LazyJiraWriter, writer: *const std.io.AnyWriter, fields: *const [][]const u8) !void {
        _ = self;
        _ = writer;
        _ = fields;
    }

    pub fn writeData(self: *LazyJiraWriter, writer: *const std.io.AnyWriter, fields: *const [][]const u8) !void {
        _ = self;
        _ = writer;
        _ = fields;
    }

    pub fn end(self: *LazyJiraWriter, writer: *const std.io.AnyWriter) !void {
        _ = self;
        _ = writer;
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
