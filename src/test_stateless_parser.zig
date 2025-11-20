const std = @import("std");
const ArgIterator = std.process.ArgIterator;
const stateless = @import("stateless_parser.zig");

test {
    var pos = stateless.Positional.init(try std.process.argsWithAllocator(std.heap.page_allocator));
    std.debug.print("\nfilename is: {s}\n", .{pos.next().?});
    var c: u8 = 1;
    while (pos.next()) |cap| {
        std.debug.print("arg {d} is: {s}\n", .{ c, cap });
        c += 1;
    }
}
