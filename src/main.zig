const std = @import("std");
const LineReader = @import("LineReader").LineReader;
const MemMappedLineReader = @import("LineReader").MemMappedLineReader;
const CsvLine = @import("CsvLine").CsvLine;

const version = "csvcut v0.1\n\n";

const SelectionType = enum {
    name,
    index,
};

const Selection = struct {
    type: SelectionType,
    field: []const u8,
};

const Filter = struct {
    field: []const u8 = undefined,
    value: []const u8 = undefined,
    index: usize = undefined,
};

const OptionError = error{
    NoSuchField,
    NoHeader,
    MoreThanOneEqualInFilter,
};

const OutputFormat = enum {
    Csv,
    LazyMarkdown,
};

const FormattedWriter = *const fn (*const std.io.AnyWriter, *const [][]const u8, *Options, bool) anyerror!void;

const Options = struct {
    csvLine: ?CsvLine = null,
    allocator: std.mem.Allocator,
    input_separator: [1]u8 = .{','},
    input_quoute: ?[1]u8 = null,
    output_separator: [1]u8 = .{','},
    output_quoute: ?[1]u8 = null,
    fileHeader: bool = true,
    header: ?[][]const u8 = null,
    outputHeader: bool = true,
    selectedFields: ?std.ArrayList(Selection) = null,
    selectionIndices: ?[]usize = null,
    trim: bool = false,
    filterFields: ?std.ArrayList(Filter) = null,
    outputFormat: OutputFormat = .Csv,
    listHeader: bool = false,

    pub fn init(allocator: std.mem.Allocator) !Options {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Options) void {
        if (self.selectedFields) |selectedFields| {
            selectedFields.deinit();
        }
        if (self.header) |header| {
            self.allocator.free(header);
        }
        if (self.csvLine != null) {
            self.csvLine.?.free();
        }
    }

    fn setHeader(self: *Options, header: []const u8) !void {
        self.header = try self.allocator.dupe([]const u8, try (try self.getCsvLine()).parse(header));
        self.fileHeader = false;
    }

    fn getCsvLine(self: *Options) !*CsvLine {
        if (self.csvLine == null) {
            self.csvLine = try CsvLine.init(self.allocator, .{ .trim = self.trim });
        }
        return &(self.csvLine.?);
    }

    fn addIndex(self: *Options, selectionType: SelectionType, fields: []u8) !void {
        if (self.selectedFields == null) {
            self.selectedFields = std.ArrayList(Selection).init(self.allocator);
        }
        for ((try (try self.getCsvLine()).parse(fields))) |field| {
            try self.selectedFields.?.append(.{ .type = selectionType, .field = field });
        }
    }

    fn setSelectionIndices(self: *Options) !void {
        if (self.selectedFields == null or self.selectionIndices != null) return;
        self.selectionIndices = try self.allocator.alloc(usize, self.selectedFields.?.items.len);

        for (self.selectedFields.?.items, 0..) |item, i| {
            switch (item.type) {
                .index => self.selectionIndices.?[i] = (try std.fmt.parseInt(usize, item.field, 10)) - 1,
                .name => self.selectionIndices.?[i] = try getHeaderIndex(self, item.field),
            }
        }
    }

    fn setFilterIndices(self: *Options) OptionError!void {
        if (self.filterFields == null) return;
        for (0..self.filterFields.?.items.len) |i| {
            self.filterFields.?.items[i].index = try getHeaderIndex(self, self.filterFields.?.items[i].field);
        }
    }

    fn getHeaderIndex(self: *Options, search: []const u8) OptionError!usize {
        if (self.header == null) {
            return OptionError.NoHeader;
        }

        return for (self.header.?, 0..) |field, index| {
            if (std.mem.eql(u8, field, search)) {
                break index;
            }
        } else OptionError.NoSuchField;
    }

    fn addFilter(self: *Options, filterList: []const u8) !void {
        if (self.filterFields == null) {
            self.filterFields = std.ArrayList(Filter).init(self.allocator);
        }
        for ((try (try self.getCsvLine()).parse(filterList))) |filterString| {
            var filter: Filter = .{};
            var it = std.mem.split(u8, filterString, "=");
            var i: u8 = 0;
            while (it.next()) |value| {
                switch (i) {
                    0 => filter.field = value,
                    1 => filter.value = value,
                    else => return OptionError.MoreThanOneEqualInFilter,
                }
                i += 1;
            }
            try self.filterFields.?.append(filter);
        }
    }
};

const Arguments = enum {
    @"--help",
    @"-v",
    @"--version",
    @"-t",
    @"--tab",
    @"-c",
    @"--comma",
    @"-s",
    @"--semicolon",
    @"-p",
    @"--pipe",
    @"-d",
    @"--doubleQuoute",
    @"-q",
    @"--quoute",
    @"--noQuote",
    @"-h",
    @"--header",
    @"-n",
    @"--noHeader",
    @"-T",
    @"--outputTab",
    @"-C",
    @"--outputComma",
    @"-S",
    @"--outputSemicolon",
    @"-P",
    @"--outputPipe",
    @"-D",
    @"--outputDoubleQuoute",
    @"-Q",
    @"--outputQuoute",
    @"--outputNoQuote",
    @"-N",
    @"--outputNoHeader",
    @"-F",
    @"--fields",
    @"-I",
    @"--indices",
    @"--trim",
    @"--filter",
    @"--format",
    @"-l",
    @"--listHeader",
};

const hpa = std.heap.page_allocator;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var options = try Options.init(allocator);
    defer options.deinit();

    if (args.len == 1) {
        try noArgumentError();
    }

    var skip_next: bool = false;
    for (args[1..], 1..) |arg, index| {
        if (skip_next) {
            skip_next = false;
            continue;
        }
        if (arg[0] == '-' and arg.len > 1) {
            switch (std.meta.stringToEnum(Arguments, arg) orelse {
                try argumentError(arg);
            }) {
                .@"--help" => try printUsage(std.io.getStdOut(), true),
                .@"-v", .@"--version" => try printVersion(),
                .@"-t", .@"--tab" => options.input_separator = .{'\t'},
                .@"-c", .@"--comma" => options.input_separator = .{','},
                .@"-s", .@"--semicolon" => options.input_separator = .{';'},
                .@"-p", .@"--pipe" => options.input_separator = .{'|'},
                .@"-d", .@"--doubleQuoute" => options.input_quoute = .{'"'},
                .@"-q", .@"--quoute" => options.input_quoute = .{'\''},
                .@"--noQuote" => options.input_quoute = null,
                .@"-T", .@"--outputTab" => options.output_separator = .{'\t'},
                .@"-C", .@"--outputComma" => options.output_separator = .{','},
                .@"-S", .@"--outputSemicolon" => options.output_separator = .{';'},
                .@"-P", .@"--outputPipe" => options.output_separator = .{'|'},
                .@"-D", .@"--outputDoubleQuoute" => options.output_quoute = .{'"'},
                .@"-Q", .@"--outputQuoute" => options.output_quoute = .{'\''},
                .@"--outputNoQuote" => options.output_quoute = null,
                .@"--trim" => options.trim = true,
                .@"-l", .@"--listHeader" => options.listHeader = true,
                .@"--format" => {
                    if (std.meta.stringToEnum(OutputFormat, args[index + 1])) |outputFormat| {
                        options.outputFormat = outputFormat;
                    } else {
                        try argumentValueError(arg, args[index + 1]);
                    }
                    skip_next = true;
                },
                .@"-h", .@"--header" => {
                    try options.setHeader(args[index + 1]); //todo: check if there are more arguments -> error if not
                    skip_next = true;
                },
                .@"-n", .@"--noHeader" => options.fileHeader = false,
                .@"-N", .@"--outputNoHeader" => options.outputHeader = false,
                .@"-F", .@"--fields" => {
                    try options.addIndex(.name, args[index + 1]); //todo: check if there are more arguments -> error if not
                    skip_next = true;
                },
                .@"-I", .@"--indices" => {
                    try options.addIndex(.index, args[index + 1]); //todo: check if there are more arguments -> error if not
                    skip_next = true;
                },
                .@"--filter" => {
                    try options.addFilter(args[index + 1]);
                    skip_next = true;
                },
            }
        } else if (arg[0] == '-' and arg.len == 1) {
            var lineReader = try LineReader.init(std.io.getStdIn().reader(), hpa, .{});
            defer lineReader.deinit();
            try proccessFile(&lineReader, std.io.getStdOut(), &options, allocator);
        } else {
            try processFileByName(arg, &options, allocator);
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
    std.process.exit(2);
}

fn argumentValueError(arg: []u8, val: []u8) !noreturn {
    try printUsage(std.io.getStdErr(), false);
    std.log.err("value '{s}' for argument '{s}' is unknown\n", .{ val, arg });
    std.process.exit(3);
}

fn processFileByName(fileName: []const u8, options: *Options, allocator: std.mem.Allocator) !void {
    const file = try std.fs.cwd().openFile(fileName, .{});
    defer file.close();
    var lineReader = try MemMappedLineReader.init(file, .{});
    //var lineReader = try LineReader.init(file.reader(), allocator, .{});
    defer lineReader.deinit();

    try proccessFile(&lineReader, std.io.getStdOut(), options, allocator);
}

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
    };

    if (options.fileHeader) {
        if (try lineReader.readLine()) |line| {
            try options.setHeader(line);
        }
    }
    if (options.header != null) {
        try options.setSelectionIndices();
    }

    if (options.header != null and options.outputHeader) {
        try formattedWriter(&writer, &options.header.?, options, true);
    }

    if (options.filterFields != null) {
        try options.setFilterIndices();
    }

    if (options.filterFields) |filterFields| {
        while (try lineReader.readLine()) |line| {
            const fields = try csvLine.parse(line);
            if (filterMatches(fields, filterFields.items)) {
                try formattedWriter(&writer, &fields, options, false);
            }
        }
    } else {
        while (try lineReader.readLine()) |line| {
            const fields = try csvLine.parse(line);
            try formattedWriter(&writer, &fields, options, false);
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
            _ = try bufferedWriter.write(fields.*[field]);
            _ = try bufferedWriter.write(" ");
        }
        _ = try bufferedWriter.write("|\n");
    } else {
        for (fields.*) |field| {
            _ = try bufferedWriter.write("| ");
            _ = try bufferedWriter.write(field);
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

inline fn filterMatches(fields: [][]const u8, filterList: []Filter) bool {
    for (filterList) |filter| {
        if (!std.mem.eql(u8, fields[filter.index], filter.value)) {
            return false;
        }
    }
    return true;
}

test {
    std.testing.refAllDecls(@This());
}
