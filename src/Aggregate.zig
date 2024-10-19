const std = @import("std");

pub const Fields = struct {
    allocator: std.mem.Allocator,
    fields: [][]const u8,
    count: usize,
    ready: bool = false,

    pub fn init(fields: *const [][]const u8, allocator: std.mem.Allocator) !Fields {
        var self: Fields = (try allocator.alloc(Fields, 1))[0];
        self.allocator = allocator;
        self.count = 1;
        self.fields = try allocator.alloc([]u8, fields.len + 1);
        for (fields.*, 0..) |field, i| {
            self.fields[i] = try allocator.dupe(u8, field);
        }
        return self;
    }

    pub fn get(self: *Fields) !*const [][]const u8 {
        if (!self.ready) {
            self.fields[self.fields.len - 1] = try std.fmt.allocPrint(self.allocator, "{d}", .{self.count});
            self.ready = true;
        }
        return &self.fields;
    }
};

pub const UniqueAgregator = struct {
    var uniqueSet: ?std.StringHashMap(u1) = null;
    var initialized = false;
    var allocator: std.mem.Allocator = undefined;

    pub fn init(unique: bool, alloc: std.mem.Allocator) void {
        if (unique) {
            allocator = alloc;
            if (!initialized) {
                uniqueSet = std.StringHashMap(u1).init(allocator);
                initialized = true;
            } else {
                uniqueSet.?.clearRetainingCapacity();
            }
        }
    }

    pub inline fn isNew(line: []u8) !bool {
        if (!uniqueSet.?.contains(line)) {
            try uniqueSet.?.put(try allocator.dupe(u8, line), 1);
            return true;
        }
        return false;
    }
};

pub const CountAggregator = struct {
    var allocator: std.mem.Allocator = undefined;
    pub var countMap: std.StringHashMap(Fields) = undefined;
    var keyBuffer: std.ArrayList(u8) = undefined;
    var initialized = false;

    pub fn init(alloc: std.mem.Allocator) !void {
        if (!initialized) {
            allocator = alloc;
            countMap = std.StringHashMap(Fields).init(allocator);
            keyBuffer = try std.ArrayList(u8).initCapacity(allocator, 1024);
            initialized = true;
        } else {
            countMap.clearRetainingCapacity();
            keyBuffer.clearRetainingCapacity();
        }
    }

    pub fn add(fields: *const [][]const u8) !void {
        if (countMap.getEntry(try getKey(fields))) |entry| {
            entry.value_ptr.*.count += 1;
        } else {
            try countMap.put(try allocator.dupe(u8, keyBuffer.items), try Fields.init(fields, allocator));
        }
    }

    fn getKey(fields: *const [][]const u8) ![]u8 {
        keyBuffer.clearRetainingCapacity();
        for (fields.*) |field| {
            try keyBuffer.appendSlice(field);
            try keyBuffer.append('|');
        }
        return keyBuffer.items;
    }
};
