const std = @import("std");

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

    pub fn init(reader: std.fs.File.Reader, allocator: std.mem.Allocator, size: usize) !LineReader {
        var read_size: usize = size;
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
        self.start = self.next;

        while (true) {
            if (self.start + pos + 1 >= self.end and try self.fill_buffer() == 0) {
                if (pos == 0) {
                    return null;
                }
                break;
            }
            const current = self.buffer[self.start + pos];
            if (current == '\r' or current == '\n') {
                //todo: handle \r\n
                pos += 1;
                break;
            }
            pos += 1;
        }
        self.next = self.start + pos + 1;
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
const test_csv: []const u8 = @embedFile("test.csv");

fn open_file(file_name: []const u8) !std.fs.File {
    var path_buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const path = try std.fs.realpath(file_name, &path_buffer);
    return try std.fs.openFileAbsolute(path, .{});
}

test "init" {
    const file = try open_file("src/test.csv");
    defer file.close();

    var line_reader = try LineReader.init(file.reader(), hpa, 30);
    defer line_reader.free();

    try testing.expectEqual(0, line_reader.start);
    try testing.expectEqual(26, line_reader.end);
    try testing.expectEqual(30, line_reader.read_size);
    try testing.expectEqual(60, line_reader.size);

    try testing.expectEqualStrings(test_csv, line_reader.buffer[line_reader.start .. line_reader.end - line_reader.start]);
}

test "read lines all in buffer" {
    const file = try open_file("src/test.csv");
    defer file.close();

    var line_reader = try LineReader.init(file.reader(), hpa, 30);
    defer line_reader.free();

    try testing.expectEqualStrings("ONE,TWO,THREE", (try line_reader.read_line()).?);
    try testing.expectEqualStrings("1,2,3", (try line_reader.read_line()).?);
    try testing.expectEqualStrings("4,5,6", (try line_reader.read_line()).?);
    try testing.expectEqual(null, try line_reader.read_line());
}

test "read lines partial lines in buffer" {
    const file = try open_file("src/test.csv");
    defer file.close();

    var line_reader = try LineReader.init(file.reader(), hpa, 1);
    defer line_reader.free();

    try testing.expectEqualStrings("ONE,TWO,THREE", (try line_reader.read_line()).?);
    try testing.expectEqualStrings("1,2,3", (try line_reader.read_line()).?);
    try testing.expectEqualStrings("4,5,6", (try line_reader.read_line()).?);
    try testing.expectEqual(null, try line_reader.read_line());
    try testing.expectEqual(15, line_reader.size);
}
