const std = @import("std");

pub const markdownCharacters = "\\`*_{}[]<>()#+-.!|";
pub const jiraCharacters = "*_-{|^+?#";

pub inline fn jiraLen(field: []const u8) usize {
    return escapedLen(field, jiraCharacters);
}

pub inline fn markdownLen(field: []const u8) usize {
    return escapedLen(field, markdownCharacters);
}

pub fn writeJira(writer: *std.Io.Writer, field: []const u8) !void {
    try writeEscaped(writer, field, jiraCharacters);
}

pub fn writeMarkdown(writer: *std.Io.Writer, field: []const u8) !void {
    try writeEscaped(writer, field, markdownCharacters);
}

pub fn writeJsonString(writer: *std.Io.Writer, field: []const u8) !void {
    try writer.writeByte('"');
    var i: usize = 0;
    while (i < field.len) {
        const c = field[i];
        switch (c) {
            '"' => {
                try writer.writeAll("\\\"");
                i += 1;
            },
            '\\' => {
                try writer.writeAll("\\\\");
                i += 1;
            },
            '\n' => {
                try writer.writeAll("\\n");
                i += 1;
            },
            '\r' => {
                try writer.writeAll("\\r");
                i += 1;
            },
            '\t' => {
                try writer.writeAll("\\t");
                i += 1;
            },
            0x08 => {
                try writer.writeAll("\\b");
                i += 1;
            },
            0x0c => {
                try writer.writeAll("\\f");
                i += 1;
            },
            '<' => {
                try writer.writeAll("\\u003c");
                i += 1;
            },
            '>' => {
                try writer.writeAll("\\u003e");
                i += 1;
            },
            '&' => {
                try writer.writeAll("\\u0026");
                i += 1;
            },
            else => {
                if (c < 0x20) {
                    try writer.print("\\u{x:0>4}", .{c});
                    i += 1;
                } else if (c < 0x80) {
                    try writer.writeByte(c);
                    i += 1;
                } else {
                    const sequenceLength = std.unicode.utf8ByteSequenceLength(c) catch {
                        try writer.writeAll("\\ufffd");
                        i += 1;
                        continue;
                    };
                    if (i + sequenceLength <= field.len and std.unicode.utf8ValidateSlice(field[i .. i + sequenceLength])) {
                        try writer.writeAll(field[i .. i + sequenceLength]);
                        i += sequenceLength;
                    } else {
                        try writer.writeAll("\\ufffd");
                        i += 1;
                    }
                }
            },
        }
    }
    try writer.writeByte('"');
}

pub fn writeHtml(writer: *std.Io.Writer, field: []const u8) !void {
    var i: usize = 0;
    while (i < field.len) {
        const c = field[i];
        switch (c) {
            '&' => {
                try writer.writeAll("&amp;");
                i += 1;
            },
            '<' => {
                try writer.writeAll("&lt;");
                i += 1;
            },
            '>' => {
                try writer.writeAll("&gt;");
                i += 1;
            },
            '"' => {
                try writer.writeAll("&quot;");
                i += 1;
            },
            '\'' => {
                try writer.writeAll("&#39;");
                i += 1;
            },
            else => {
                if (c < 0x20 and c != '\t' and c != '\n' and c != '\r') {
                    try writer.writeAll("&#xFFFD;");
                    i += 1;
                } else if (c < 0x80) {
                    try writer.writeByte(c);
                    i += 1;
                } else {
                    const sequenceLength = std.unicode.utf8ByteSequenceLength(c) catch {
                        try writer.writeAll("&#xFFFD;");
                        i += 1;
                        continue;
                    };
                    if (i + sequenceLength <= field.len and std.unicode.utf8ValidateSlice(field[i .. i + sequenceLength])) {
                        const codepoint = std.unicode.utf8Decode(field[i .. i + sequenceLength]) catch 0xFFFD;
                        if (isInvalidXmlCodepoint(codepoint)) {
                            try writer.writeAll("&#xFFFD;");
                        } else {
                            try writer.writeAll(field[i .. i + sequenceLength]);
                        }
                        i += sequenceLength;
                    } else {
                        try writer.writeAll("&#xFFFD;");
                        i += 1;
                    }
                }
            },
        }
    }
}

fn isInvalidXmlCodepoint(codepoint: u21) bool {
    if (codepoint == 0xFFFE or codepoint == 0xFFFF) {
        return true;
    }
    if (codepoint >= 0xFDD0 and codepoint <= 0xFDEF) {
        return true;
    }
    const planeTail = codepoint & 0xFFFF;
    return planeTail == 0xFFFE or planeTail == 0xFFFF;
}

fn escapedLen(field: []const u8, comptime specialCharacters: []const u8) usize {
    var len = field.len;
    for (field) |c| {
        if (std.mem.indexOfScalar(u8, specialCharacters, c) != null) {
            len += 1;
        }
    }
    return len;
}

fn writeEscaped(writer: *std.Io.Writer, field: []const u8, comptime specialCharacters: []const u8) !void {
    var start: usize = 0;
    for (field, 0..) |c, i| {
        if (std.mem.indexOfScalar(u8, specialCharacters, c) != null) {
            if (i > start) {
                try writer.writeAll(field[start..i]);
            }
            try writer.writeByte('\\');
            try writer.writeByte(c);
            start = i + 1;
        }
    }
    if (start < field.len) {
        try writer.writeAll(field[start..]);
    }
}

// Tests

const testing = std.testing;

fn expectEscaped(expected: []const u8, field: []const u8, comptime escapeFn: anytype) !void {
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try escapeFn(&writer, field);
    try testing.expectEqualStrings(expected, writer.buffered());
}

test "jira returns field if no escape is needed" {
    try expectEscaped("unescaped", "unescaped", writeJira);
    try testing.expectEqual(@as(usize, 9), jiraLen("unescaped"));
}

test "markdown escapes special characters with backslash" {
    const field = "unescaped* -test [1-3] #Test end";
    try expectEscaped("unescaped\\* \\-test \\[1\\-3\\] \\#Test end", field, writeMarkdown);
    try testing.expectEqual(field.len + 6, markdownLen(field));
}

test "json string escaping" {
    try expectEscaped("\"a\\\"b\\\\c\\nd\\u001f\"", "a\"b\\c\nd\x1f", writeJsonString);
    try expectEscaped("\"\\u003cscript\\u003e\"", "<script>", writeJsonString);
}

test "html escaping" {
    try expectEscaped("&lt;b&gt;&amp;&quot;&#39;", "<b>&\"'", writeHtml);
}

test "json keeps valid utf8 and replaces invalid bytes" {
    try expectEscaped("\"äöü\"", "äöü", writeJsonString);
    try expectEscaped("\"a\\ufffdb\"", "a\xffb", writeJsonString);
}

test "html replaces control and invalid bytes" {
    try expectEscaped("a&#xFFFD;b&#xFFFD;", "a\x01b\xff", writeHtml);
}

test "html replaces xml noncharacters" {
    try expectEscaped("&#xFFFD;", "\u{FFFE}", writeHtml);
    try expectEscaped("&#xFFFD;", "\u{1FFFE}", writeHtml);
    try expectEscaped("&#xFFFD;", "\u{FDD0}", writeHtml);
}
