const std = @import("std");

const LineReaderError = error{
    OptionError,
};
pub const Options = struct {
    size: usize = 4096,
    includeEof: bool = false,
};

pub const LineReader = struct {
    reader: std.fs.File.Reader,
    allocator: std.mem.Allocator,
    size: usize,
    read_size: usize,
    buffer: []u8,
    start: usize = 0,
    next: usize = 0,
    end: usize = 0,
    eof: bool = false,
    includeEof: bool,

    pub fn init(reader: std.fs.File.Reader, allocator: std.mem.Allocator, options: Options) !LineReader {
        if (options.size == 0) {
            return LineReaderError.OptionError;
        }
        var read_size: usize = options.size;
        if (read_size == 0) {
            read_size = 4096;
        }
        const alloc_size = read_size * 2;
        var line_reader: LineReader = .{
            .reader = reader,
            .allocator = allocator,
            .size = alloc_size,
            .read_size = read_size,
            .buffer = try allocator.alloc(u8, alloc_size),
            .includeEof = options.includeEof,
        };
        errdefer free(&line_reader);
        _ = try line_reader.fill_buffer();
        return line_reader;
    }

    pub fn free(self: *LineReader) void {
        self.allocator.free(self.buffer);
    }

    pub fn read_line(self: *LineReader) !?[]const u8 {
        var pos: usize = 0;
        var skip: usize = 1;
        self.start = self.next;

        if (self.start > self.end) {
            return null;
        }

        var window = self.buffer[self.start..self.end];
        while (true) {
            if (pos == window.len) {
                if (try self.fill_buffer() == 0) {
                    if (pos == 0) {
                        return null;
                    }
                    break;
                }
                window = self.buffer[self.start..self.end];
            }
            const current = window[pos];
            if (current == '\r') {
                if (pos == window.len - 1) {
                    if (try self.fill_buffer() == 0) {
                        break;
                    }
                    window = self.buffer[self.start..self.end];
                }
                if (window[pos + 1] == '\n') {
                    skip = 2;
                }
                break;
            } else if (current == '\n') {
                break;
            }
            pos += 1;
        }
        self.next = self.start + pos + skip;
        return self.buffer[self.start .. self.start + pos]; //todo: include EOL in the returned string
    }

    fn fill_buffer(self: *LineReader) !usize {
        if (self.eof) {
            return 0;
        }

        var space: usize = self.size - self.end;
        if (space < self.read_size) {
            if (self.start > 0) {
                std.mem.copyBackwards(u8, self.buffer, self.buffer[self.start..self.end]);
                self.end = self.end - self.start;
                self.start = 0;
                space = self.size - self.end;
            }
            if (space < self.read_size) {
                self.size += self.read_size;
                self.buffer = try self.allocator.realloc(self.buffer, self.size);
            }
        }
        const read = try self.reader.read(self.buffer[self.end .. self.end + self.read_size]);
        if (read < self.read_size) {
            self.eof = true;
        }
        self.end += read;
        return read;
    }
};

const hpa = std.heap.page_allocator;
const testing = std.testing;
const test_lf_csv =
    "ONE,TWO,THREE\n" ++
    "1,2,3\n" ++
    "4,5,6\n";

const test_lf_no_last_csv =
    "ONE,TWO,THREE\n" ++
    "1,2,3\n" ++
    "4,5,6";

const test_cr_csv =
    "ONE,TWO,THREE\r" ++
    "1,2,3\r" ++
    "4,5,6\r";

const test_cr_lf_csv =
    "ONE,TWO,THREE\r\n" ++
    "1,2,3\r\n" ++
    "4,5,6\r\n";

fn write_file(file_name: []const u8, data: []const u8) !void {
    const file = try std.fs.cwd().createFile(file_name, .{});
    defer file.close();
    _ = try file.write(data);
}

fn open_file(file_name: []const u8) !std.fs.File {
    var path_buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const path = try std.fs.realpath(file_name, &path_buffer);
    return try std.fs.openFileAbsolute(path, .{});
}

var test_initialized = false;
fn test_init() !void {
    if (!test_initialized) {
        test_initialized = true;
        try write_file("test/test_lf.csv", test_lf_csv);
        try write_file("test/test_cr.csv", test_cr_csv);
        try write_file("test/test_cr_lf.csv", test_cr_lf_csv);
        try write_file("test/test_lf_no_last.csv", test_lf_no_last_csv);
    }
}

test "init" {
    try test_init();
    const file = try open_file("test/test_lf.csv");
    defer file.close();

    var line_reader = try LineReader.init(file.reader(), hpa, .{ .size = 30 });
    defer line_reader.free();

    try testing.expectEqual(0, line_reader.start);
    try testing.expectEqual(26, line_reader.end);
    try testing.expectEqual(30, line_reader.read_size);
    try testing.expectEqual(60, line_reader.size);

    try testing.expectEqualStrings(test_lf_csv, line_reader.buffer[line_reader.start..line_reader.end]);
}

fn expectLines(line_reader: *LineReader) !void {
    try testing.expectEqualStrings("ONE,TWO,THREE", (try line_reader.read_line()).?);
    try testing.expectEqualStrings("1,2,3", (try line_reader.read_line()).?);
    try testing.expectEqualStrings("4,5,6", (try line_reader.read_line()).?);
    try testing.expectEqual(null, try line_reader.read_line());
}

test "read lines all in buffer" {
    try test_init();
    const file = try open_file("test/test_lf.csv");
    defer file.close();

    var line_reader = try LineReader.init(file.reader(), hpa, .{ .size = 30 });
    defer line_reader.free();
    try expectLines(&line_reader);
}

test "read lines partial lines in buffer" {
    try test_init();
    const file = try open_file("test/test_lf.csv");
    defer file.close();

    var line_reader = try LineReader.init(file.reader(), hpa, .{ .size = 1 });
    defer line_reader.free();

    try expectLines(&line_reader);
    try testing.expectEqual(null, try line_reader.read_line());
    try testing.expectEqual(14, line_reader.size);
}

test "read lines no last eol" {
    try test_init();
    const file = try open_file("test/test_lf_no_last.csv");
    defer file.close();

    var line_reader = try LineReader.init(file.reader(), hpa, .{ .size = 30 });
    defer line_reader.free();
    try expectLines(&line_reader);
}

test "read lines with cr as eol" {
    try test_init();
    const file = try open_file("test/test_cr.csv");
    defer file.close();

    var line_reader = try LineReader.init(file.reader(), hpa, .{ .size = 30 });
    defer line_reader.free();
    try expectLines(&line_reader);
}

test "read lines with crlf as eol" {
    try test_init();
    const file = try open_file("test/test_cr_lf.csv");
    defer file.close();

    var line_reader = try LineReader.init(file.reader(), hpa, .{ .size = 30 });
    defer line_reader.free();
    try expectLines(&line_reader);
}
