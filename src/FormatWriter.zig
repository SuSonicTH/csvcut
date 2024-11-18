const std = @import("std");
const OutputFormat = @import("options.zig").OutputFormat;
const Options = @import("options.zig").Options;
const FieldWidths = @import("FieldWidths.zig");

const CsvWriter = @import("FormatWriter/CsvWriter.zig");
const LazyMarkdown = @import("FormatWriter/LazyMarkdown.zig");
const LazyJira = @import("FormatWriter/LazyJira.zig");
const Markdown = @import("FormatWriter/Markdown.zig");
const Jira = @import("FormatWriter/Jira.zig");
const Table = @import("FormatWriter/Table.zig");
const Html = @import("FormatWriter/Html.zig");
const HtmlHandson = @import("FormatWriter/HtmlHandson.zig");
const Json = @import("FormatWriter/Json.zig");
const JsonArray = @import("FormatWriter/JsonArray.zig");
const ExcelXml = @import("FormatWriter/ExcelXml.zig");

pub const FormatWriter = union(OutputFormat) {
    csv: CsvWriter,
    lazyMarkdown: LazyMarkdown,
    lazyJira: LazyJira,
    markdown: Markdown,
    jira: Jira,
    table: Table,
    html: Html,
    htmlHandson: HtmlHandson,
    json: Json,
    jsonArray: JsonArray,
    excelXml: ExcelXml,

    var anonymizeIndices: ?[]usize = null;
    var anonymizefields: []std.ArrayList(u8) = undefined;

    pub fn init(options: Options, allocator: std.mem.Allocator, fieldWidths: FieldWidths, anonymize: ?[]usize) !FormatWriter {
        
        if (anonymize!=null) {
            anonymizeIndices = anonymize;
            anonymizefields = allocator.alloc(std.ArrayList(u8), anonymize.?.len);
            for (anonymizeIndices,0..) | _,i | {
                anonymizefields[i].init(allocator);
            }
        }

        return switch (options.outputFormat) {
            .csv => .{ .csv = try CsvWriter.init(.{ .separator = options.outputSeparator, .quoute = options.outputQuoute }) },
            .lazyMarkdown => .{ .lazyMarkdown = try LazyMarkdown.init() },
            .lazyJira => .{ .lazyJira = try LazyJira.init() },
            .markdown => .{ .markdown = try Markdown.init(allocator, fieldWidths) },
            .jira => .{ .jira = try Jira.init(allocator, fieldWidths) },
            .table => .{ .table = try Table.init(allocator, fieldWidths) },
            .html => .{ .html = try Html.init(.{}) },
            .htmlHandson => .{ .htmlHandson = try HtmlHandson.init() },
            .json => .{ .json = try Json.init(allocator) },
            .jsonArray => .{ .jsonArray = try JsonArray.init() },
            .excelXml => .{ .excelXml = try ExcelXml.init(allocator) },
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

    fn anonymizeFields(fields: *const [][]const u8) *const [][]const u8 {
        if (anonymizeIndices==null) {    
            return fields;     
        }
        
    }
};