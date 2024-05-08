const std = @import("std");

const version = "csvcut v0.1\n\n";

const Options = struct {
    separator: u8 = ',',
    quoute: ?u8 = null,
};

const Arguments = enum {
    @"-h",
    @"--help",
    @"-v",
    @"--version",
    @"-T",
    @"--tab",
    @"-C",
    @"--comma",
    @"-S",
    @"--semicolon",
    @"-P",
    @"--pipe",
    @"-D",
    @"--doubleQuoute",
    @"-Q",
    @"--Quoute",
};

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_allocator.allocator();
    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    var options = Options{};

    if (args.len == 1) {
        try noArgumentError();
    }

    for (args[1..]) |arg| {
        if (arg[0] == '-' and arg.len > 1) {
            switch (std.meta.stringToEnum(Arguments, arg) orelse {
                try argumentError(arg);
            }) {
                .@"-h", .@"--help" => try printUsage(std.io.getStdOut(), true),
                .@"-v", .@"--version" => try printVersion(),
                .@"-T", .@"--tab" => options.separator = '\t',
                .@"-C", .@"--comma" => options.separator = ',',
                .@"-S", .@"--semicolon" => options.separator = ';',
                .@"-P", .@"--pipe" => options.separator = '|',
                .@"-D", .@"--doubleQuoute" => options.quoute = '"',
                .@"-Q", .@"--Quoute" => options.quoute = '\'',
            }
        } else if (arg[0] == '-' and arg.len == 1) {
            try proccessFile(std.io.getStdIn().reader(), std.io.getStdOut().writer(), options);
        } else {
            try processFileByName(arg, options);
        }
    }
}

fn printUsage(file: std.fs.File, exit: bool) !void {
    const help = @embedFile("USAGE.txt");
    try file.writeAll(version ++ help);
    if (exit) {
        std.process.exit(0);
    }
}

fn printVersion() !void {
    const license = @embedFile("LICENSE.txt");
    try std.io.getStdOut().writeAll(version ++ license);
    std.process.exit(0);
}

fn noArgumentError() !noreturn {
    try printUsage(std.io.getStdErr(), false);
    std.log.err("no argument given, expecting at least one option", .{});
    std.process.exit(1);
}

fn argumentError(arg: []u8) !noreturn {
    try printUsage(std.io.getStdErr(), false);
    std.log.err("argument '{s}' is unknown\n", .{arg});
    std.process.exit(1);
}

fn processFileByName(name: []const u8, options: Options) !void {
    var path_buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const path = try std.fs.realpath(name, &path_buffer);
    const file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();

    try proccessFile(file.reader(), std.io.getStdOut().writer(), options);
}

fn proccessFile(reader: std.fs.File.Reader, writer: std.fs.File.Writer, options: Options) !void {
    var buffered_reader = std.io.bufferedReader(reader);
    var buffered_writer = std.io.bufferedWriter(writer);
    var buffer: [1024]u8 = undefined;
    var splitter: Splitter = Splitter.init(options.separator, options.quoute);

    while (try buffered_reader.reader().readUntilDelimiterOrEof(&buffer, '\n')) |line| {
        splitter.iterate(line);
        while (try splitter.next()) |field| {
            _ = try buffered_writer.write(field);
            _ = try buffered_writer.write("\t");
        }
        _ = try buffered_writer.write("\n");
    }
}

const SplitterError = error{
    FoundEndOfLineAfterOpeningQuoute,
};

const Splitter = struct {
    separator: u8 = undefined,
    quoute: ?u8 = null,
    line: []const u8 = undefined,
    pos: usize = 0,

    pub fn init(separator: u8, quoute: ?u8) Splitter {
        return .{
            .separator = separator,
            .quoute = quoute,
        };
    }

    pub fn iterate(self: *Splitter, line: []const u8) void {
        self.line = line;
        self.pos = 0;
    }

    pub fn next(self: *Splitter) SplitterError!?[]const u8 {
        if (self.end_of_line()) return null;

        var start: usize = undefined;
        var end: usize = undefined;

        if (self.quoute != null and self.find_quote()) {
            start = self.pos;

            self.till_end_of_quote();
            if (self.end_of_line()) return SplitterError.FoundEndOfLineAfterOpeningQuoute;

            end = self.pos;
            self.till_separator();
        } else {
            start = self.pos;
            self.till_separator();
            end = self.pos;
        }

        self.pos += 1;
        return self.line[start..end];
    }

    fn end_of_line(self: *Splitter) bool {
        return self.pos >= self.line.len or self.line[self.pos] == '\r' or self.line[self.pos] == '\n';
    }

    fn find_quote(self: *Splitter) bool {
        var pos = self.pos;
        while (pos < self.line.len and self.line[pos] == ' ') {
            pos += 1;
        }
        if (self.line[pos] == self.quoute.?) {
            self.pos = pos + 1;
            return true;
        }
        return false;
    }

    fn till_end_of_quote(self: *Splitter) void {
        while (!self.end_of_line() and self.line[self.pos] != self.quoute.?) {
            self.pos += 1;
        }
    }

    fn till_separator(self: *Splitter) void {
        while (!self.end_of_line() and self.line[self.pos] != self.separator) {
            self.pos += 1;
        }
    }
};

const testing = std.testing;

test "basic splitting values" {
    var splitter = Splitter.init(',', null);
    splitter.iterate("1,2,3");
    try expect_one_two_three_null(&splitter);
}

fn expect_one_two_three_null(splitter: *Splitter) !void {
    try testing.expectEqualStrings("1", (try splitter.next()).?);
    try testing.expectEqualStrings("2", (try splitter.next()).?);
    try testing.expectEqualStrings("3", (try splitter.next()).?);
    try testing.expect((try splitter.next()) == null);
}

test "basic splitting values with CR" {
    var splitter = Splitter.init(',', null);
    splitter.iterate("1,2,3\r");
    try expect_one_two_three_null(&splitter);
}

test "basic splitting values with LF" {
    var splitter = Splitter.init(',', null);
    splitter.iterate("1,2,3\n");
    try expect_one_two_three_null(&splitter);
}

test "basic splitting by tab" {
    var splitter = Splitter.init('\t', null);
    splitter.iterate("1\t2\t3");
    try expect_one_two_three_null(&splitter);
}

test "basic splitting with separator inside quotes" {
    var splitter = Splitter.init(',', '"');
    splitter.iterate("\"1,0\",\"2,1\",\"3,2\"");

    try testing.expectEqualStrings("1,0", (try splitter.next()).?);
    try testing.expectEqualStrings("2,1", (try splitter.next()).?);
    try testing.expectEqualStrings("3,2", (try splitter.next()).?);
    try testing.expect((try splitter.next()) == null);
}

test "splitting with quotes and spaces" {
    var splitter = Splitter.init(',', '"');
    splitter.iterate("  \"1\"  , \" 2 \" ,   \"3\"   ");

    try testing.expectEqualStrings("1", (try splitter.next()).?);
    try testing.expectEqualStrings(" 2 ", (try splitter.next()).?);
    try testing.expectEqualStrings("3", (try splitter.next()).?);
    try testing.expect((try splitter.next()) == null);
}

test "error on splitting with open quote" {
    var splitter = Splitter.init(',', '"');
    splitter.iterate("1,\"2,3");

    try testing.expectEqualStrings("1", (try splitter.next()).?);
    try testing.expectError(SplitterError.FoundEndOfLineAfterOpeningQuoute, splitter.next());
}
