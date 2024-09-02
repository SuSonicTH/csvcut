const std = @import("std");
const LineReader = @import("LineReader").LineReader;
const MemMappedLineReader = @import("LineReader").MemMappedLineReader;
const CsvLine = @import("CsvLine").CsvLine;
const Options = @import("options.zig").Options;
const Filter = @import("options.zig").Filter;
const ArgumentParser = @import("arguments.zig").Parser;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var options = try Options.init(allocator);
    defer options.deinit();

    try ArgumentParser.parse(&options, args);

    if (options.useStdin) {
        var lineReader = try LineReader.init(std.io.getStdIn().reader(), allocator, .{});
        defer lineReader.deinit();
        try proccessFile(&lineReader, std.io.getStdOut(), &options, allocator);
    } else {
        for (options.inputFiles.items) |file| {
            try processFileByName(file, &options, allocator);
        }
    }
}

fn processFileByName(fileName: []const u8, options: *Options, allocator: std.mem.Allocator) !void {
    const file = try std.fs.cwd().openFile(fileName, .{});
    defer file.close();
    var lineReader = try MemMappedLineReader.init(file, .{});
    //var lineReader = try LineReader.init(file.reader(), allocator, .{});
    defer lineReader.deinit();

    try proccessFile(&lineReader, std.io.getStdOut(), options, allocator);
}

const FormattedWriter = *const fn (*const std.io.AnyWriter, *const [][]const u8, *Options, bool) anyerror!void;

fn proccessFile(lineReader: anytype, outputFile: std.fs.File, options: *Options, allocator: std.mem.Allocator) !void {
    var csvLine = try CsvLine.init(allocator, .{ .separator = options.input_separator[0], .trim = options.trim, .quoute = if (options.input_quoute) |quote| quote[0] else null });
    defer csvLine.free();

    if (options.listHeader) {
        try listHeader(lineReader, &csvLine);
        return;
    }

    var bufferedWriter = std.io.bufferedWriter(outputFile.writer());
    const writer: std.io.AnyWriter = bufferedWriter.writer().any();

    const formattedWriter: FormattedWriter = switch (options.outputFormat) {
        .Csv => &writeOutputCsv,
        .LazyMarkdown => &writeOutputLazyMarkdown,
        .LazyJira => &writeOutputLazyJira,
    };

    var lineNumber: usize = 0;

    if (options.fileHeader) {
        while (options.skipLine != null and options.skipLine.?.get(lineNumber) != null) {
            lineNumber += 1;
            if ((try lineReader.readLine()) == null) {
                return;
            }
        }
        if (try lineReader.readLine()) |line| {
            try options.setHeader(line);
        }
    }

    try options.setSelectionIndices();

    if (options.header != null and options.outputHeader) {
        try formattedWriter(&writer, &options.header.?, options, true);
    }

    if (options.filterFields != null) {
        try options.setFilterIndices();
    }

    if (options.filterFields) |filterFields| {
        while (try lineReader.readLine()) |line| {
            lineNumber += 1;
            if (options.skipLine == null or options.skipLine.?.get(lineNumber) == null) {
                const fields = try csvLine.parse(line);
                if (filterMatches(fields, filterFields.items)) {
                    try formattedWriter(&writer, &fields, options, false);
                }
            }
        }
    } else {
        while (try lineReader.readLine()) |line| {
            lineNumber += 1;
            if (options.skipLine == null or options.skipLine.?.get(lineNumber) == null) {
                const fields = try csvLine.parse(line);
                try formattedWriter(&writer, &fields, options, false);
            }
        }
    }

    try bufferedWriter.flush();
}

fn listHeader(lineReader: anytype, csvLine: *CsvLine) !void {
    const out = std.io.getStdOut();
    if (try lineReader.readLine()) |line| {
        for (try csvLine.parse(line)) |field| {
            _ = try out.write(field);
            _ = try out.write("\n");
        }
    }
}

fn writeOutputCsv(bufferedWriter: *const std.io.AnyWriter, fields: *const [][]const u8, options: *Options, isHeader: bool) !void {
    _ = isHeader;
    if (options.selectionIndices) |indices| {
        for (indices, 0..) |field, index| {
            if (index > 0) {
                _ = try bufferedWriter.write(&options.output_separator);
            }
            if (options.output_quoute != null) {
                _ = try bufferedWriter.write(&options.output_quoute.?);
            }
            _ = try bufferedWriter.write(fields.*[field]);
            if (options.output_quoute != null) {
                _ = try bufferedWriter.write(&options.output_quoute.?);
            }
        }
        _ = try bufferedWriter.write("\n");
    } else {
        for (fields.*, 0..) |field, index| {
            if (index > 0) {
                _ = try bufferedWriter.write(&options.output_separator);
            }
            if (options.output_quoute != null) {
                _ = try bufferedWriter.write(&options.output_quoute.?);
            }
            _ = try bufferedWriter.write(field);
            if (options.output_quoute != null) {
                _ = try bufferedWriter.write(&options.output_quoute.?);
            }
        }
        _ = try bufferedWriter.write("\n");
    }
}

fn writeOutputLazyMarkdown(bufferedWriter: *const std.io.AnyWriter, fields: *const [][]const u8, options: *Options, isHeader: bool) !void {
    if (options.selectionIndices) |indices| {
        for (indices) |field| {
            _ = try bufferedWriter.write("| ");
            _ = try bufferedWriter.write(try escapeMarkup(fields.*[field], markdownSpecial));
            _ = try bufferedWriter.write(" ");
        }
        _ = try bufferedWriter.write("|\n");
    } else {
        for (fields.*) |field| {
            _ = try bufferedWriter.write("| ");
            _ = try bufferedWriter.write(try escapeMarkup(field, markdownSpecial));
            _ = try bufferedWriter.write(" ");
        }
        _ = try bufferedWriter.write("|\n");
    }
    if (isHeader) {
        if (options.selectionIndices) |indices| {
            for (indices) |field| {
                _ = field;
                _ = try bufferedWriter.write("| --- ");
            }
            _ = try bufferedWriter.write("|\n");
        } else {
            for (fields.*) |field| {
                _ = field;
                _ = try bufferedWriter.write("| --- ");
            }
            _ = try bufferedWriter.write("|\n");
        }
    }
}

var escapeBuffer: [1024]u8 = undefined;
const markdownSpecial: []const u8 = "\\`*_{}[]<>()#+-.!|";
const jiraSpecial: []const u8 = "*_-{|^+?#";

inline fn escapeMarkup(field: []const u8, comptime specialCharacters: []const u8) ![]const u8 {
    var offset: u16 = 0;
    for (field, 0..) |c, i| {
        if (std.mem.indexOfScalar(u8, specialCharacters, c)) |pos| {
            _ = pos;
            if (offset == 0) {
                std.mem.copyForwards(u8, &escapeBuffer, field[0..i]);
            }
            escapeBuffer[i + offset] = '\\';
            offset += 1;
            escapeBuffer[i + offset] = c;
        } else if (offset > 0) {
            escapeBuffer[i + offset] = c;
        }
    }
    if (offset > 0) {
        return escapeBuffer[0 .. field.len + offset];
    }
    return field;
}

fn writeOutputLazyJira(bufferedWriter: *const std.io.AnyWriter, fields: *const [][]const u8, options: *Options, isHeader: bool) !void {
    if (!isHeader) {
        if (options.selectionIndices) |indices| {
            for (indices) |field| {
                _ = try bufferedWriter.write("| ");
                _ = try bufferedWriter.write(try escapeMarkup(fields.*[field], jiraSpecial));
                _ = try bufferedWriter.write(" ");
            }
            _ = try bufferedWriter.write("|\n");
        } else {
            for (fields.*) |field| {
                _ = try bufferedWriter.write("| ");
                _ = try bufferedWriter.write(try escapeMarkup(field, jiraSpecial));
                _ = try bufferedWriter.write(" ");
            }
            _ = try bufferedWriter.write("|\n");
        }
    } else {
        if (options.selectionIndices) |indices| {
            for (indices) |field| {
                _ = try bufferedWriter.write("|| ");
                _ = try bufferedWriter.write(try escapeMarkup(fields.*[field], jiraSpecial));
                _ = try bufferedWriter.write(" ");
            }
            _ = try bufferedWriter.write("||\n");
        } else {
            for (fields.*) |field| {
                _ = try bufferedWriter.write("|| ");
                _ = try bufferedWriter.write(try escapeMarkup(field, jiraSpecial));
                _ = try bufferedWriter.write(" ");
            }
            _ = try bufferedWriter.write("||\n");
        }
    }
}

inline fn filterMatches(fields: [][]const u8, filterList: []Filter) bool {
    for (filterList) |filter| {
        if (!std.mem.eql(u8, fields[filter.index], filter.value)) {
            return false;
        }
    }
    return true;
}

test "escapeMarkdown returns filed if no escape is needed" {
    const unescaped: []const u8 = "unescaped";
    const res = try escapeMarkup(unescaped);
    try std.testing.expectEqualStrings(unescaped, res);
    try std.testing.expectEqual(unescaped.ptr, res.ptr);
}

test "escapeMarkdown escapes special characters with backslash" {
    const unescaped: []const u8 = "unescaped* -test [1-3] #Test end";
    const res = try escapeMarkup(unescaped);
    try std.testing.expectEqualStrings("unescaped\\* \\-test \\[1\\-3\\] \\#Test end", res);
    try std.testing.expectEqual(&escapeBuffer, res.ptr);
}
