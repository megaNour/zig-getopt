const std = @import("std");

pub const std_options: std.Options = .{
    .log_level = .debug,
};

my_switch_enabled: bool = false,

pub fn main() void {
    parse();
}

pub const Naming = union(enum) {
    single: [:0]const u8,
    multiple: [][:0]const u8,
};

pub fn OptionFlag() type {
    return struct {
        naming: Naming,
        description: []const u8,
        max_args: u8,
        count: u8,
    };
}

pub fn OptionValue(comptime T: type) type {
    return struct {
        naming: Naming,
        description: []const u8,
        max_args: u8,
        value: T,
    };
}

pub fn OptionValueMultiple(comptime T: type) type {
    return struct {
        naming: Naming,
        occurences: u8,
        max_args: u8,
        value: []T,
    };
}

const options = enum {};

pub fn parse() void {
    const pa = std.heap.page_allocator;
    var iterator = try std.process.argsWithAllocator(pa);
    defer iterator.deinit();
    var i: u8 = 0;
    while (iterator.next()) |arg| : (i += 1) {
        std.log.debug("arg {d}\t\"{s}\"", .{ i, arg });
    }
}
