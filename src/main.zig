const std = @import("std");
const ArgIterator = std.process.ArgIterator;
const jump = @import("jump.zig");

pub fn main() void {
    const iterator = try std.process.argsWithAllocator(std.heap.page_allocator);
    var myOpt = jump.Over(ArgIterator).init(iterator, 'v', &.{ "verbose", "ver" }, .forbidden, "get useful debug output");
    var aggregateMyOpt = myOpt;
    var myOptionalOpt = jump.Over(ArgIterator).init(iterator, 'c', &.{ "color", "col" }, .allowed, "store value in there");
    var myValuedOpt = jump.Over(ArgIterator).init(iterator, 'd', &.{ "data", "dat" }, .required, "store value in there");

    while (myOpt.next()) |flag| {
        std.debug.print("found verbose level {d}!\n", .{flag[0]});
    }
    const aggreg = aggregateMyOpt.count();
    if (aggreg > 0) std.debug.print("aggregate them: {d}!\n", .{aggreg});
    while (myOpt.next()) |flag| {
        std.debug.print("found verbose level {d}!\n", .{flag[0]});
    }
    while (myOptionalOpt.next()) |color| {
        if (color.len == 1)
            std.debug.print("found color flag! Data is: {d}\n", .{color[0]})
        else
            std.debug.print("found color flag! Data is: {s}\n", .{color});
    }
    while (myValuedOpt.next()) |data| {
        std.debug.print("found data flag! Data is: {s}\n", .{data});
    }
    var myPos = jump.OverPos(ArgIterator).init(iterator);
    while (myPos.next()) |pos| {
        std.debug.print("found pos: {s}\n", .{pos});
    }
}
