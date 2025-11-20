const std = @import("std");
const ArgIterator = std.process.ArgIterator;
const jump = @import("jump.zig");
const expect = std.testing.expect;

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

test "jump flags with forbidden value affectation" {
    const iterator = StringIterator{ .stock = &.{ "--verbose", "alif", "--ba", "-ta", "-vv", "-av", "--", "-vvv" } };
    //                                             |   1                                2       1    --      3|
    //                                             |————————————————————————— 4 —————————————————————|—— 3 ———|
    var jumper = jump.Over(StringIterator).init(iterator, 'v', &.{"verbose"}, .forbidden, "verbose logs");
    var copyOfJumper = jumper; // start from the same point
    try expect(4 == copyOfJumper.count());
    try expect(1 == jumper.next().?[0]);
    try expect(2 == jumper.next().?[0]);
    try expect(1 == jumper.next().?[0]);
    try expect(null == jumper.next()); // unlike next(), count() already hit it and swallowed it
    try expect(3 == jumper.next().?[0]);
    try expect(3 == copyOfJumper.count());
}

test "jump flags with wrong value affectation" {
    const iterator = StringIterator{ .stock = &.{ "--verbose=a", "alif", "--ba", "-ta", "-vv=", "-av", "--", "-v=vv" } };
    var jumper = jump.Over(StringIterator).init(iterator, 'v', &.{"verbose"}, .forbidden, "verbose logs");
    std.debug.print("{any}", .{jumper.next().?});
    // try expect(2 == jumper.next().?[0]);
    // try expect(1 == jumper.next().?[0]);
    // try expect(null == jumper.next());
    // try expect(3 == jumper.next().?[0]);
}
