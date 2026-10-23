const std = @import("std");

/// Builds an unambiguous key from a list of fields by prefixing every field
/// with its length. This avoids collisions that a simple separator would cause.
fn appendKey(buffer: *std.array_list.Managed(u8), fields: []const []const u8) !void {
    buffer.clearRetainingCapacity();
    for (fields) |field| {
        var lengthBytes: [8]u8 = undefined;
        std.mem.writeInt(u64, &lengthBytes, field.len, .little);
        try buffer.appendSlice(&lengthBytes);
        try buffer.appendSlice(field);
    }
}

pub const Fields = struct {
    allocator: std.mem.Allocator,
    fields: [][]const u8,
    count: usize,
    countString: ?[]u8 = null,
    cachedCount: usize = 0,

    pub fn init(fields: []const []const u8, allocator: std.mem.Allocator) !Fields {
        const self: Fields = .{
            .allocator = allocator,
            .fields = try allocator.alloc([]const u8, fields.len + 1),
            .count = 1,
        };
        for (fields, 0..) |field, i| {
            self.fields[i] = try allocator.dupe(u8, field);
        }
        return self;
    }

    pub fn deinit(self: *Fields) void {
        for (self.fields[0 .. self.fields.len - 1]) |field| {
            self.allocator.free(field);
        }
        if (self.countString) |countString| {
            self.allocator.free(countString);
        }
        self.allocator.free(self.fields);
    }

    pub fn get(self: *Fields) !*const [][]const u8 {
        if (self.countString == null or self.cachedCount != self.count) {
            if (self.countString) |countString| {
                self.allocator.free(countString);
            }
            self.countString = try self.allocator.print("{d}", .{self.count});
            self.cachedCount = self.count;
            self.fields[self.fields.len - 1] = self.countString.?;
        }
        return &self.fields;
    }
};

pub const UniqueAgregator = struct {
    uniqueSet: std.StringHashMap(u1),
    allocator: std.mem.Allocator,
    keyBuffer: std.array_list.Managed(u8),

    pub fn init(allocator: std.mem.Allocator) UniqueAgregator {
        return .{
            .allocator = allocator,
            .uniqueSet = std.StringHashMap(u1).init(allocator),
            .keyBuffer = std.array_list.Managed(u8).init(allocator),
        };
    }

    pub fn deinit(self: *UniqueAgregator) void {
        var iterator = self.uniqueSet.keyIterator();
        while (iterator.next()) |key| {
            self.allocator.free(key.*);
        }
        self.uniqueSet.deinit();
        self.keyBuffer.deinit();
    }

    pub fn isNew(self: *UniqueAgregator, fields: []const []const u8) !bool {
        try appendKey(&self.keyBuffer, fields);
        if (!self.uniqueSet.contains(self.keyBuffer.items)) {
            try self.uniqueSet.put(try self.allocator.dupe(u8, self.keyBuffer.items), 1);
            return true;
        }
        return false;
    }
};

pub const CountAggregator = struct {
    allocator: std.mem.Allocator,
    countMap: std.array_hash_map.String(Fields),
    keyBuffer: std.array_list.Managed(u8),
    order: std.array_list.Managed([]const u8),

    pub fn init(allocator: std.mem.Allocator) !CountAggregator {
        return .{
            .allocator = allocator,
            .countMap = .empty,
            .keyBuffer = try std.array_list.Managed(u8).initCapacity(allocator, 1024),
            .order = std.array_list.Managed([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *CountAggregator) void {
        var iterator = self.countMap.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit();
        }
        self.countMap.deinit(self.allocator);
        self.keyBuffer.deinit();
        self.order.deinit();
    }

    pub fn add(self: *CountAggregator, fields: []const []const u8) !void {
        try appendKey(&self.keyBuffer, fields);

        if (self.countMap.getEntry(self.keyBuffer.items)) |entry| {
            entry.value_ptr.*.count += 1;
        } else {
            const key = try self.allocator.dupe(u8, self.keyBuffer.items);
            try self.countMap.put(self.allocator, key, try Fields.init(fields, self.allocator));
            try self.order.append(key);
        }
    }
};

// Tests

const testing = std.testing;

test "unique aggregator does not confuse separator characters" {
    var aggregator = UniqueAgregator.init(testing.allocator);
    defer aggregator.deinit();

    const first = [_][]const u8{ "a|b", "c" };
    const second = [_][]const u8{ "a", "b|c" };

    try testing.expect(try aggregator.isNew(&first));
    try testing.expect(try aggregator.isNew(&second));
    try testing.expect(!try aggregator.isNew(&first));
}

test "count aggregator does not confuse separator characters" {
    var aggregator = try CountAggregator.init(testing.allocator);
    defer aggregator.deinit();

    const first = [_][]const u8{ "a|b", "c" };
    const second = [_][]const u8{ "a", "b|c" };

    try aggregator.add(&first);
    try aggregator.add(&second);
    try aggregator.add(&first);
    try testing.expectEqual(@as(usize, 2), aggregator.countMap.count());

    var total: usize = 0;
    var hasDuplicated = false;
    var iterator = aggregator.countMap.iterator();
    while (iterator.next()) |entry| {
        total += entry.value_ptr.*.count;
        if (entry.value_ptr.*.count == 2) hasDuplicated = true;
    }
    try testing.expectEqual(@as(usize, 3), total);
    try testing.expect(hasDuplicated);
}
