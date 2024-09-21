const std = @import("std");

pub inline fn jira(field: []const u8) ![]const u8 {
    return try escape(field, "*_-{|^+?#");
}

pub inline fn markdown(field: []const u8) ![]const u8 {
    return try escape(field, "\\`*_{}[]<>()#+-.!|");
}

var escapeBuffer: [20484]u8 = undefined;

inline fn escape(field: []const u8, comptime specialCharacters: []const u8) ![]const u8 {
    var offset: u16 = 0;
    for (field, 0..) |c, i| {
        if (std.mem.indexOfScalar(u8, specialCharacters, c)) |pos| {
            _ = pos;
            if (offset == 0) {
                std.mem.copyForwards(u8, &escapeBuffer, field[0..i]);
            }
            escapeBuffer[i + offset] = '\\';
            offset += 1;
            escapeBuffer[i + offset] = c;
        } else if (offset > 0) {
            escapeBuffer[i + offset] = c;
        }
    }
    if (offset > 0) {
        return escapeBuffer[0 .. field.len + offset];
    }
    return field;
}
