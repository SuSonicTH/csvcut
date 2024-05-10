const std = @import("std");

pub const Separator = struct {
    const comma: u8 = ',';
    const semicolon: u8 = ';';
    const tab: u8 = '\t';
    const pipe: u8 = '|';
};

pub const Quoute = struct {
    const single: u8 = '\'';
    const double: u8 = '"';
    const none: ?u8 = null;
};

pub const Options = struct {
    separator: u8 = Separator.comma,
    quoute: ?u8 = Quoute.none,
    fields: usize = 16,
};

pub const ParserError = error{
    FoundEndOfLineAfterOpeningQuoute,
    OutOfMemory,
};

pub const Parser = struct {
    allocator: std.mem.Allocator,
    options: Options,
    fields: [][]const u8,
    reserved: usize,

    pub fn init(allocator: std.mem.Allocator, options: Options) !Parser {
        return .{
            .allocator = allocator,
            .options = options,
            .reserved = options.fields,
            .fields = try allocator.alloc([]const u8, options.fields),
        };
    }

    pub fn free(self: *Parser) void {
        self.allocator.free(self.fields);
    }

    pub fn parse(self: *Parser, line: []const u8) ParserError![][]const u8 {
        var index: usize = 0;
        var pos: usize = 0;
        var start: usize = 0;
        var end: usize = 0;
        var last_was_separator: bool = false;

        while (!end_of_line(line, pos)) {
            if (start_of_quouted_string(line, pos, self.options.quoute)) |quoute_pos| {
                start = quoute_pos;
                end = end_of_quoted_string(line, quoute_pos, self.options.quoute.?);
                if (end_of_line(line, end)) return ParserError.FoundEndOfLineAfterOpeningQuoute;
                pos = next_separator(line, end, self.options.separator) + 1;
            } else {
                start = pos;
                end = next_separator(line, pos, self.options.separator);
                pos = end + 1;
            }
            last_was_separator = end < line.len and line[end] == self.options.separator;

            try self.add_field(line[start..end], index);
            index += 1;
        }

        if (last_was_separator) {
            try self.add_field("", index);
            index += 1;
        }

        return self.fields[0..index];
    }

    fn start_of_quouted_string(line: []const u8, start: usize, quoute: ?u8) ?usize {
        if (quoute == null) return null;

        var pos = start;
        while (pos < line.len and line[pos] == ' ') {
            pos += 1;
        }

        if (line[pos] == quoute.?) {
            pos = pos + 1;
            return pos;
        }
        return null;
    }

    fn end_of_quoted_string(line: []const u8, start: usize, quoute: u8) usize {
        var pos = start;
        while (!end_of_line(line, pos) and line[pos] != quoute) {
            pos += 1;
        }
        return pos;
    }

    fn add_field(self: *Parser, field: []const u8, index: usize) !void {
        if (index >= self.reserved) {
            self.reserved *= 2;
            self.fields = try self.allocator.realloc(self.fields, self.reserved);
        }
        self.fields[index] = field;
    }

    fn end_of_line(line: []const u8, pos: usize) bool {
        return pos >= line.len or line[pos] == '\r' or line[pos] == '\n';
    }

    fn next_separator(line: []const u8, start: usize, separator: u8) usize {
        var pos = start;
        while (!end_of_line(line, pos) and line[pos] != separator) {
            pos += 1;
        }
        return pos;
    }
};

const hpa = std.heap.page_allocator;
const testing = std.testing;

fn expectEqualStringsArray(expected: []const []const u8, actual: [][]const u8) !void {
    try testing.expectEqual(expected.len, actual.len);
    for (expected, 0..) |exp, idx| {
        try testing.expectEqualStrings(exp, actual[idx]);
    }
}

test "basic parsing" {
    var parser: Parser = try Parser.init(hpa, .{});
    defer parser.free();
    try expectEqualStringsArray(&[_][]const u8{ "1", "2", "3" }, try parser.parse("1,2,3"));
}

test "basic parsing - first empty" {
    var parser: Parser = try Parser.init(hpa, .{});
    defer parser.free();
    try expectEqualStringsArray(&[_][]const u8{ "", "2", "3" }, try parser.parse(",2,3"));
}

test "basic parsing - middle empty" {
    var parser: Parser = try Parser.init(hpa, .{});
    defer parser.free();
    try expectEqualStringsArray(&[_][]const u8{ "1", "", "3" }, try parser.parse("1,,3"));
}

test "basic parsing - last empty" {
    var parser: Parser = try Parser.init(hpa, .{});
    defer parser.free();
    try expectEqualStringsArray(&[_][]const u8{ "1", "2", "" }, try parser.parse("1,2,"));
}

test "basic parsing - all empty" {
    var parser: Parser = try Parser.init(hpa, .{});
    defer parser.free();
    try expectEqualStringsArray(&[_][]const u8{ "", "", "" }, try parser.parse(",,"));
}

test "basic parsing with tab separator" {
    var parser: Parser = try Parser.init(hpa, .{ .separator = Separator.tab });
    defer parser.free();
    try expectEqualStringsArray(&[_][]const u8{ "1", "2", "3" }, try parser.parse("1\t2\t3"));
}

test "basic parsing with semicolon separator" {
    var parser: Parser = try Parser.init(hpa, .{ .separator = Separator.semicolon });
    defer parser.free();
    try expectEqualStringsArray(&[_][]const u8{ "1", "2", "3" }, try parser.parse("1;2;3"));
}

test "basic parsing with pipe separator" {
    var parser: Parser = try Parser.init(hpa, .{ .separator = Separator.pipe });
    defer parser.free();
    try expectEqualStringsArray(&[_][]const u8{ "1", "2", "3" }, try parser.parse("1|2|3"));
}

test "basic quouted parsing" {
    var parser: Parser = try Parser.init(hpa, .{ .quoute = Quoute.single });
    defer parser.free();
    try expectEqualStringsArray(&[_][]const u8{ "1", "2", "3" }, try parser.parse("'1','2','3'"));
}

test "basic quouted parsing - spaces in fields" {
    var parser: Parser = try Parser.init(hpa, .{ .quoute = Quoute.single });
    defer parser.free();
    try expectEqualStringsArray(&[_][]const u8{ " 1", "2 ", " 3 " }, try parser.parse("' 1','2 ',' 3 '"));
}

test "basic quouted parsing - spaces outside fields" {
    var parser: Parser = try Parser.init(hpa, .{ .quoute = Quoute.single });
    defer parser.free();
    try expectEqualStringsArray(&[_][]const u8{ "1", "2", "3" }, try parser.parse("   '1','2' , '3'    "));
}

test "quouted parsing - expect error for non closed quoute" {
    var parser: Parser = try Parser.init(hpa, .{ .quoute = Quoute.single });
    defer parser.free();
    try testing.expectError(ParserError.FoundEndOfLineAfterOpeningQuoute, parser.parse("'1,2,3"));
}
