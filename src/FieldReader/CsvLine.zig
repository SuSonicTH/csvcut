const std = @import("std");

pub const Separator = struct {
    const comma: u8 = ',';
    const semicolon: u8 = ';';
    const tab: u8 = '\t';
    const pipe: u8 = '|';
};

pub const Quote = struct {
    const single: u8 = '\'';
    const double: u8 = '"';
    const none: ?u8 = null;
};

pub const Options = struct {
    separator: u8 = Separator.comma,
    quote: ?u8 = Quote.none,
    fields: usize = 16,
    trim: bool = false,
};

pub const ParserError = error{
    FoundEndOfLineAfterOpeningQuote,
    OutOfMemory,
};

const Self = @This();

allocator: std.mem.Allocator,
options: Options,
fields: [][]const u8,
unescapeBuffer: []u8 = &.{},

pub fn init(allocator: std.mem.Allocator, options: Options) !Self {
    return .{
        .allocator = allocator,
        .options = options,
        .fields = try allocator.alloc([]const u8, options.fields),
    };
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.fields);
    if (self.unescapeBuffer.len > 0) {
        self.allocator.free(self.unescapeBuffer);
    }
}

pub fn parse(self: *Self, line: []const u8) ParserError![][]const u8 {
    var index: usize = 0;
    var pos: usize = 0;
    var start: usize = 0;
    var end: usize = 0;
    var last_was_separator: bool = false;
    var unescapedUsed: usize = 0;

    while (!end_of_line(line, pos)) {
        var quoted = false;
        if (start_of_quoted_string(line, pos, self.options.quote)) |quote_pos| {
            quoted = true;
            start = quote_pos;
            end = end_of_quoted_string(line, quote_pos, self.options.quote.?);
            if (end_of_line(line, end)) return ParserError.FoundEndOfLineAfterOpeningQuote;
            pos = next_separator(line, end, self.options.separator) + 1;
        } else {
            start = pos;
            end = next_separator(line, pos, self.options.separator);
            pos = end + 1;
        }
        last_was_separator = pos > 0 and pos <= line.len and line[pos - 1] == self.options.separator;

        var value = line[start..end];
        if (quoted) {
            const quote = self.options.quote.?;
            if (std.mem.indexOf(u8, value, &.{ quote, quote }) != null) {
                try self.ensureUnescapeCapacity(line.len);
                const destination = self.unescapeBuffer[unescapedUsed..];
                var out: usize = 0;
                var i: usize = 0;
                while (i < value.len) {
                    if (value[i] == quote and i + 1 < value.len and value[i + 1] == quote) {
                        destination[out] = quote;
                        out += 1;
                        i += 2;
                    } else {
                        destination[out] = value[i];
                        out += 1;
                        i += 1;
                    }
                }
                value = destination[0..out];
                unescapedUsed += out;
            }
        }

        if (self.options.trim) {
            try self.add_field(std.mem.trim(u8, value, " \t"), index);
        } else {
            try self.add_field(value, index);
        }

        index += 1;
    }

    if (last_was_separator) {
        try self.add_field("", index);
        index += 1;
    }

    return self.fields[0..index];
}

fn ensureUnescapeCapacity(self: *Self, size: usize) !void {
    if (self.unescapeBuffer.len >= size) return;
    if (self.unescapeBuffer.len == 0) {
        self.unescapeBuffer = try self.allocator.alloc(u8, size);
    } else {
        self.unescapeBuffer = try self.allocator.realloc(self.unescapeBuffer, size);
    }
}

inline fn start_of_quoted_string(line: []const u8, start: usize, quote: ?u8) ?usize {
    if (quote == null) {
        return null;
    }
    var pos = start;
    while (pos < line.len and line[pos] == ' ') {
        pos += 1;
    }
    if (pos >= line.len) {
        return null;
    }

    if (line[pos] == quote.?) {
        pos = pos + 1;
        return pos;
    }
    return null;
}

inline fn end_of_quoted_string(line: []const u8, start: usize, quote: u8) usize {
    var pos = start;
    while (!end_of_line(line, pos)) {
        if (line[pos] == quote) {
            if (pos + 1 < line.len and line[pos + 1] == quote) {
                pos += 2;
                continue;
            }
            return pos;
        }
        pos += 1;
    }
    return pos;
}

inline fn add_field(self: *Self, field: []const u8, index: usize) !void {
    if (index >= self.fields.len) {
        self.fields = try self.allocator.realloc(self.fields, @max(self.fields.len * 2, 1));
    }
    self.fields[index] = field;
}

inline fn end_of_line(line: []const u8, pos: usize) bool {
    return pos >= line.len or line[pos] == '\r' or line[pos] == '\n';
}

fn next_separator(line: []const u8, start: usize, separator: u8) usize {
    var pos = start;
    while (!end_of_line(line, pos) and line[pos] != separator) {
        pos += 1;
    }
    return pos;
}

// Tests

const testing = std.testing;

fn expectEqualStringsArray(expected: []const []const u8, actual: [][]const u8) !void {
    try testing.expect(expected.len <= actual.len);
    for (expected, 0..) |exp, idx| {
        try testing.expectEqualStrings(exp, actual[idx]);
    }
    try testing.expectEqual(expected.len, actual.len);
}

test "basic parsing" {
    var csvLine = try init(testing.allocator, .{});
    defer csvLine.deinit();
    try expectEqualStringsArray(&[_][]const u8{ "1", "2", "3" }, try csvLine.parse("1,2,3"));
}

test "basic parsing - first empty" {
    var csvLine = try init(testing.allocator, .{});
    defer csvLine.deinit();
    try expectEqualStringsArray(&[_][]const u8{ "", "2", "3" }, try csvLine.parse(",2,3"));
}

test "basic parsing - middle empty" {
    var csvLine = try init(testing.allocator, .{});
    defer csvLine.deinit();
    try expectEqualStringsArray(&[_][]const u8{ "1", "", "3" }, try csvLine.parse("1,,3"));
}

test "basic parsing - last empty" {
    var csvLine = try init(testing.allocator, .{});
    defer csvLine.deinit();
    try expectEqualStringsArray(&[_][]const u8{ "1", "2", "" }, try csvLine.parse("1,2,"));
}

test "basic parsing - all empty" {
    var csvLine = try init(testing.allocator, .{});
    defer csvLine.deinit();
    try expectEqualStringsArray(&[_][]const u8{ "", "", "" }, try csvLine.parse(",,"));
}

test "basic parsing with tab separator" {
    var csvLine = try init(testing.allocator, .{ .separator = Separator.tab });
    defer csvLine.deinit();
    try expectEqualStringsArray(&[_][]const u8{ "1", "2", "3" }, try csvLine.parse("1\t2\t3"));
}

test "basic parsing with semicolon separator" {
    var csvLine = try init(testing.allocator, .{ .separator = Separator.semicolon });
    defer csvLine.deinit();
    try expectEqualStringsArray(&[_][]const u8{ "1", "2", "3" }, try csvLine.parse("1;2;3"));
}

test "basic parsing with pipe separator" {
    var csvLine = try init(testing.allocator, .{ .separator = Separator.pipe });
    defer csvLine.deinit();
    try expectEqualStringsArray(&[_][]const u8{ "1", "2", "3" }, try csvLine.parse("1|2|3"));
}

test "basic quoted parsing" {
    var csvLine = try init(testing.allocator, .{ .quote = Quote.single });
    defer csvLine.deinit();
    try expectEqualStringsArray(&[_][]const u8{ "1", "2", "3" }, try csvLine.parse("'1','2','3'"));
}

test "basic quoted parsing - spaces in fields" {
    var csvLine = try init(testing.allocator, .{ .quote = Quote.single });
    defer csvLine.deinit();
    try expectEqualStringsArray(&[_][]const u8{ " 1", "2 ", " 3 " }, try csvLine.parse("' 1','2 ',' 3 '"));
}

test "basic quoted parsing - spaces outside fields" {
    var csvLine = try init(testing.allocator, .{ .quote = Quote.single });
    defer csvLine.deinit();
    try expectEqualStringsArray(&[_][]const u8{ "1", "2", "3" }, try csvLine.parse("   '1','2' , '3'    "));
}

test "quoted parsing - expect error for non closed quote" {
    var csvLine = try init(testing.allocator, .{ .quote = Quote.single });
    defer csvLine.deinit();
    try testing.expectError(ParserError.FoundEndOfLineAfterOpeningQuote, csvLine.parse("'1,2,3"));
}

test "quoted parsing - escaped quotes" {
    var csvLine = try init(testing.allocator, .{ .quote = Quote.double });
    defer csvLine.deinit();
    try expectEqualStringsArray(&[_][]const u8{ "say \"hi\"", "a" }, try csvLine.parse("\"say \"\"hi\"\"\",a"));
    try expectEqualStringsArray(&[_][]const u8{ "a\"", "b" }, try csvLine.parse("\"a\"\"\",b"));
}

test "quoted parsing - line with only spaces" {
    var csvLine = try init(testing.allocator, .{ .quote = Quote.double });
    defer csvLine.deinit();
    try expectEqualStringsArray(&[_][]const u8{"   "}, try csvLine.parse("   "));
}

test "trailing separator after a quoted field" {
    var csvLine = try init(testing.allocator, .{ .quote = Quote.double });
    defer csvLine.deinit();
    try expectEqualStringsArray(&[_][]const u8{ "x,y", "" }, try csvLine.parse("\"x,y\","));
    try expectEqualStringsArray(&[_][]const u8{ "a", "b" }, try csvLine.parse("\"a\",b"));
    try expectEqualStringsArray(&[_][]const u8{ "", "b" }, try csvLine.parse(",\"b\""));
}

test "whitespace trimming" {
    var csvLine = try init(testing.allocator, .{ .trim = true });
    defer csvLine.deinit();
    try expectEqualStringsArray(&[_][]const u8{ "1", "2", "3", "", "", "" }, try csvLine.parse("\t1,2 , \t 3\t , ,\t,  \t \t"));
}
