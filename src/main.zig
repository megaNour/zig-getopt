const std = @import("std");
const ArgIterator = std.process.ArgIterator;
const jump = @import("jump.zig");

pub fn main() void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    // Good to know: on POSIX systems, the allocator is never used.
    // on Windows it's used once.
    //
    // The iterator in and of itself is just a book-keeper that we can cheaply copy around.
    // copying the iterator allows to have multiple jumpers starting from the same point but looking for different flags.
    const iterator = try std.process.argsWithAllocator(arena.allocator());
    var myOpt = jump.Over(ArgIterator).init(iterator, 'v', &.{ "verbose", "ver" }, .forbidden, "get useful debug output");

    // Jumping over a given option lazily consumeing everything until end of argv or '--' included
    while (myOpt.next()) |opt| {
        if (opt) |o| std.debug.print("coucou: {d}\n", .{o[0]}) else break; // The character returned is a count **per arg** '-v' returns 1 '-vvv' returns 3
    } else |err| {
        switch (err) { // For now there is only one possible error, but switching protects agains future additions...
            jump.LocalParsingError.ForbiddenValue => std.debug.print("Values are forbidden here! Found: {s}, {any}\n", .{ myOpt.diag.debug_hint, err }),
            jump.LocalParsingError.MissingValue => unreachable,
        }
    }

    // But what if you want to count them all, regardless if they are in the same arg or not, like -v foo -v abc -vv.
    // You want to know there are 4 'v' flags.
    // Why? Because, you can!
    var myOptCounter = jump.Over(ArgIterator).init(iterator, 'v', &.{ "verbose", "ver" }, .forbidden, "get useful debug output");
    if (myOptCounter.count()) |count| {
        std.debug.print("-v counter: {d}\n", .{count}); // We consumed all argv or unitl '--' included
    } else |err| {
        switch (err) {
            jump.LocalParsingError.ForbiddenValue => std.debug.print("Found an unexpected value while counting: {s}, {any}\n", .{ myOptCounter.diag.debug_hint, err }),
            jump.LocalParsingError.MissingValue => std.debug.print("Found a flag missing a value while counting: {s}, {any}\n", .{ myOpt.diag.debug_hint, err }),
        }
    }

    // Jumps over positionals in a "lean" fashion.
    // Always writing your option values with an "=" is ideal as it allows more determinism in the parser.
    // However, (if like most people) you sometimes use space, like "--option value" instead of "--option=value",
    // then you cannot use this safely. See Register usage for that matter.
    var myPos = jump.OverPosLean(ArgIterator).init(iterator);
    while (myPos.next()) |opt| { // first one will be the file name. The library doesn't decide to auto-discard it for you.
        std.debug.print("positional: {s}\n", .{opt});
    } else {
        std.debug.print("no (more) positional argument!\n", .{});
    }
}
