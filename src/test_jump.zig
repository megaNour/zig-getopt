const std = @import("std");
const ArgIterator = std.process.ArgIterator;
const jump = @import("jump.zig");

pub const StringIterator = struct {
    stock: []const [:0]const u8,
    pos: usize = 0,

    pub fn next(self: *StringIterator) ?[:0]const u8 {
        var res: ?[:0]const u8 = null;
        if (self.pos < self.stock.len) {
            res = self.stock[self.pos];
            self.pos += 1;
        }
        return res;
    }
};

test {
    const iterator = StringIterator{ .stock = &.{ "-v", "--verbose" } };
    var jumper = jump.Over(StringIterator).init(iterator, 'v', &.{"verbose"}, .forbidden, "verbose logs");
    var aggregator = jumper;
    while (jumper.next()) |val| {
        std.debug.print("found: {d} verbose flag!", .{val[0]});
    }
    std.debug.print("total verbose flags: {d}", .{aggregator.count()});
}
