const std = @import("std");

const version = "csvcut v0.1\n\n";

const Options = packed struct {
    outputNumbers: bool = false,
    outputNumbersNonEmpty: bool = false,
    showEnds: bool = false,
    squeezeBlank: bool = false,
    showTabs: bool = false,
};

const Arguments = enum {
    @"--help",
    @"-h",
    @"--version",
    @"-v",
};

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_allocator.allocator();
    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    //var options = Options{};
    const options = Options{};

    if (args.len == 1) {
        try noArgumentError();
    }

    for (args[1..]) |arg| {
        if (arg[0] == '-' and arg.len > 1) {
            switch (std.meta.stringToEnum(Arguments, arg) orelse {
                try argumentError(arg);
            }) {
                .@"--help", .@"-h" => try printUsage(std.io.getStdOut(), true),
                .@"--version", .@"-v" => try printVersion(),
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
    _ = reader;
    _ = writer;
    _ = options;
    //todo: implement
}

const Splitter = struct {
    separator: u8 = undefined,
    quoute: ?u8 = null,
    line: []const u8 = undefined,
    pos: usize = 0,

    pub fn init(separator: u8, quoute: ?u8, line: []const u8) Splitter {
        return .{
            .separator = separator,
            .quoute = quoute,
            .line = line,
        };
    }

    pub fn next(self: *Splitter) ?[]const u8 {
        if (self.pos > self.line.len) return null;

        var start: usize = undefined;
        var end: usize = undefined;

        if (self.quoute != null and self.find_quote()) {
            start = self.pos;

            //todo check for EOL return error
            self.till_end_of_quote();
            //todo check if we hit a quote else error

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
        while (self.pos < self.line.len and self.line[self.pos] != self.quoute.?) {
            self.pos += 1;
        }
    }

    fn till_separator(self: *Splitter) void {
        while (self.pos < self.line.len and self.line[self.pos] != self.separator) {
            self.pos += 1;
        }
    }
};

const testing = std.testing;

test "basic splitting values" {
    var splitter = Splitter.init(',', null, "1,2,3");

    try testing.expectEqualStrings("1", splitter.next().?);
    try testing.expectEqualStrings("2", splitter.next().?);
    try testing.expectEqualStrings("3", splitter.next().?);
    try testing.expect(splitter.next() == null);
}

test "basic splitting by tab" {
    var splitter = Splitter.init('\t', null, "1\t2\t3");

    try testing.expectEqualStrings("1", splitter.next().?);
    try testing.expectEqualStrings("2", splitter.next().?);
    try testing.expectEqualStrings("3", splitter.next().?);
    try testing.expect(splitter.next() == null);
}

test "basic splitting with separator inside quotes" {
    var splitter = Splitter.init(',', '"', "\"1,0\",\"2,1\",\"3,2\"");

    try testing.expectEqualStrings("1,0", splitter.next().?);
    try testing.expectEqualStrings("2,1", splitter.next().?);
    try testing.expectEqualStrings("3,2", splitter.next().?);
    try testing.expect(splitter.next() == null);
}

test "splitting with quotes and spaces" {
    var splitter = Splitter.init(',', '"', "  \"1\"  , \" 2 \" ,   \"3\"   ");

    try testing.expectEqualStrings("1", splitter.next().?);
    try testing.expectEqualStrings(" 2 ", splitter.next().?);
    try testing.expectEqualStrings("3", splitter.next().?);
    try testing.expect(splitter.next() == null);
}
