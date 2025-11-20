const std = @import("std");
const ArgIterator = std.process.ArgIterator;
const jump = @import("jump.zig");
// const reentrant = @import("reentrant_arg_iterator.zig");
// const Option = @import("option.zig").Option;
// const Parser = @import("parser.zig").Parser;

// pub const std_options: std.Options = .{
//     .log_level = .debug,
// };
//
// const verbose_option: Option = .{
//     .short_name = "v",
//     .long_names = .{"verbose"},
//     .description = "verbose stderr",
// };
// const dryrun_option: Option = .{
//     .short_name = "d",
//     .long_names = .{ "dryRun", "dry-run", "dryrun" },
//     .description = "no op mode",
// };
//
// fn iterateOverArgs(fn_ptr: fn (i: u8, [:0]const u8) void) void {
//     var iterator = try std.process.argsWithAllocator(std.heap.page_allocator);
//     defer iterator.deinit();
//     var i: u8 = 0;
//     _ = iterator.next();
//     while (iterator.next()) |arg| : (i += 1) {
//         fn_ptr(i, arg);
//     }
// }

// test "iterate over args" {
//     const coco = try reentrant.argsWithAllocator(std.heap.page_allocator, true);
//     _ = coco;
// }

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

// fn matchOption(arg: Arg) void {
// //     for (options) |option| {
// //         if (option.processArg(arg)) break;
// //     }
// // }

// var counter_max_positionals: u8 = 0;
//
// fn countMaxPositionals(_: u8, arg: [:0]const u8) void {
//     if (std.mem.eql(u8, "--", arg)) { // exception
//     } else if (arg.len > 1 and arg[0] == '-') return;
//     counter_max_positionals += 1;
//     std.debug.print("arg: {s}\tmax possible positionals is now: {d}\n", .{ arg, counter_max_positionals });
// }
