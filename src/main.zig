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

const Fields = struct {
    allocator: std.mem.Allocator,
    fields: [][]const u8,
    count: usize,

    pub fn init(fields: *const [][]const u8, options: *Options, allocator: std.mem.Allocator) !Fields {
        var self: Fields = (try allocator.alloc(Fields, 1))[0];
        self.allocator = allocator;
        self.count = 1;

        if (options.selectionIndices) |indices| {
            self.fields = try allocator.alloc([]u8, indices.len + 1);
            for (indices, 0..) |field, i| {
                self.fields[i] = try allocator.dupe(u8, fields.*[field]);
            }
        } else {
            self.fields = try allocator.alloc([]u8, fields.len + 1);
            for (fields.*, 0..) |field, i| {
                self.fields[i] = try allocator.dupe(u8, field);
            }
        }
        return self;
    }

    pub fn get(self: *const Fields) !*const [][]const u8 {
        self.fields[self.fields.len - 1] = try std.fmt.allocPrint(self.allocator, "{d}", .{self.count});
        return &self.fields;
    }
};

fn proccessFile(lineReader: anytype, outputFile: std.fs.File, options: *Options, allocator: std.mem.Allocator) !void {
    var csvLine = try CsvLine.init(allocator, .{ .separator = options.input_separator[0], .trim = options.trim, .quoute = if (options.input_quoute) |quote| quote[0] else null });
    defer csvLine.free();

    if (options.listHeader) {
        try listHeader(lineReader, &csvLine);
        return;
    }

    var bufferedWriter = std.io.bufferedWriter(outputFile.writer());
    const formattedWriter = switch (options.outputFormat) {
        .Csv => &writeOutputCsv,
        .LazyMarkdown => &writeOutputLazyMarkdown,
        .LazyJira => &writeOutputLazyJira,
    };
    var lineBuffer = try std.ArrayList(u8).initCapacity(allocator, 1024);
    defer lineBuffer.deinit();
    const lineWriter = lineBuffer.writer().any();

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
        if (options.count) {
            const header = try (try Fields.init(&options.header.?, options, allocator)).get();
            header.*[header.*.len - 1] = "Count";
            const selectionIndices = options.selectionIndices;
            options.selectionIndices = null;
            try formattedWriter(&lineWriter, header, options, false);
            options.selectionIndices = selectionIndices;
        } else {
            try formattedWriter(&lineWriter, &options.header.?, options, false);
        }
        _ = try bufferedWriter.write(lineBuffer.items);
    }

    if (options.filterFields != null) {
        try options.setFilterIndices();
    }

    var uniqueSet: ?std.StringHashMap(u1) = null;
    if (options.unique) {
        uniqueSet = std.StringHashMap(u1).init(allocator);
    }

    var countMap: std.StringHashMap(Fields) = undefined;
    var keyBuffer: std.ArrayList(u8) = undefined;
    if (options.count) {
        countMap = std.StringHashMap(Fields).init(allocator);
        keyBuffer = try std.ArrayList(u8).initCapacity(allocator, 1024);
    }

    while (try lineReader.readLine()) |line| {
        lineNumber += 1;
        if (options.skipLine == null or options.skipLine.?.contains(lineNumber) == false) {
            const fields = try csvLine.parse(line);

            if (options.filterFields == null or filterMatches(fields, options.filterFields.?.items)) {
                if (options.unique) {
                    lineBuffer.clearRetainingCapacity();
                    try formattedWriter(&lineWriter, &fields, options, false);

                    if (!uniqueSet.?.contains(lineBuffer.items)) {
                        try uniqueSet.?.put(try allocator.dupe(u8, lineBuffer.items), 1);
                        _ = try bufferedWriter.write(lineBuffer.items);
                    }
                } else if (options.count) {
                    if (countMap.getEntry(try getKey(&keyBuffer, &fields, options))) |entry| {
                        entry.value_ptr.*.count += 1;
                    } else {
                        try countMap.put(try allocator.dupe(u8, keyBuffer.items), try Fields.init(&fields, options, allocator));
                    }
                } else {
                    lineBuffer.clearRetainingCapacity();
                    try formattedWriter(&lineWriter, &fields, options, false);
                    _ = try bufferedWriter.write(lineBuffer.items);
                }
            }
        }
    }

    if (options.count) {
        options.selectionIndices = null;
        var iterator = countMap.iterator();
        while (iterator.next()) |entry| {
            lineBuffer.clearRetainingCapacity();
            try formattedWriter(&lineWriter, try entry.value_ptr.get(), options, false);
            _ = try bufferedWriter.write(lineBuffer.items);
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

fn getKey(keyBuffer: *std.ArrayList(u8), fields: *const [][]const u8, options: *Options) ![]u8 {
    keyBuffer.clearRetainingCapacity();
    if (options.selectionIndices) |indices| {
        for (indices) |field| {
            try keyBuffer.appendSlice(fields.*[field]);
            try keyBuffer.append('|');
        }
    } else {
        for (fields.*) |field| {
            try keyBuffer.appendSlice(field);
            try keyBuffer.append('|');
        }
    }
    return keyBuffer.items;
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
