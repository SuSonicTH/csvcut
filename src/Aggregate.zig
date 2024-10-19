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
    uniqueSet: std.StringHashMap(u1),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) UniqueAgregator {
        return .{
            .allocator = allocator,
            .uniqueSet = std.StringHashMap(u1).init(allocator),
        };
    }

    pub fn deinit(self: *UniqueAgregator) void {
        //todo: keys are not freed, use arena?
        self.uniqueSet.deinit();
    }

    pub inline fn isNew(self: *UniqueAgregator, line: []u8) !bool {
        if (!self.uniqueSet.contains(line)) {
            try self.uniqueSet.put(try self.allocator.dupe(u8, line), 1);
            return true;
        }
        return false;
    }
};

pub const CountAggregator = struct {
    allocator: std.mem.Allocator,
    countMap: std.StringHashMap(Fields),
    keyBuffer: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) !CountAggregator {
        return .{
            .allocator = allocator,
            .countMap = std.StringHashMap(Fields).init(allocator),
            .keyBuffer = try std.ArrayList(u8).initCapacity(allocator, 1024),
        };
    }

    pub fn add(self: *CountAggregator, fields: *const [][]const u8) !void {
        if (self.countMap.getEntry(try self.getKey(fields))) |entry| {
            entry.value_ptr.*.count += 1;
        } else {
            try self.countMap.put(try self.allocator.dupe(u8, self.keyBuffer.items), try Fields.init(fields, self.allocator));
        }
    }

    fn getKey(self: *CountAggregator, fields: *const [][]const u8) ![]u8 {
        self.keyBuffer.clearRetainingCapacity();
        for (fields.*) |field| {
            try self.keyBuffer.appendSlice(field);
            try self.keyBuffer.append('|');
        }
        return self.keyBuffer.items;
    }
};
