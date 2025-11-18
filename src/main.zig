const std = @import("std");
const reentrant = @import("reentrant_arg_iterator.zig");
const Option = @import("option.zig").Option;
const Parser = @import("parser.zig").Parser;

pub const std_options: std.Options = .{
    .log_level = .debug,
};

const verbose_option: Option = .{
    .short_name = "v",
    .long_names = .{"verbose"},
    .description = "verbose stderr",
};
const dryrun_option: Option = .{
    .short_name = "d",
    .long_names = .{ "dryRun", "dry-run", "dryrun" },
    .description = "no op mode",
};

fn iterateOverArgs(fn_ptr: fn (i: u8, [:0]const u8) void) void {
    var iterator = try std.process.argsWithAllocator(std.heap.page_allocator);
    defer iterator.deinit();
    var i: u8 = 0;
    _ = iterator.next();
    while (iterator.next()) |arg| : (i += 1) {
        fn_ptr(i, arg);
    }
}

test "iterate over args" {
    const coco = try reentrant.argsWithAllocator(std.heap.page_allocator, true);
    _ = coco;
}

pub fn main() void {
    const iterator = try std.process.argsWithAllocator(std.heap.page_allocator);
    var p: Parser = Parser.init(iterator);
    while (p.nextShort('v')) |value| {
        if (value.len > 0) {
            std.debug.print("found flag with value: {s}\n", .{value});
        } else {
            std.debug.print("found flag with no value\n", .{});
        }
    } else {
        std.debug.print("end of arguments reached\n", .{});
    }
}
// fn matchOption(arg: Arg) void {
// //     for (options) |option| {
// //         if (option.processArg(arg)) break;
// //     }
// // }

var counter_max_positionals: u8 = 0;

fn countMaxPositionals(_: u8, arg: [:0]const u8) void {
    if (std.mem.eql(u8, "--", arg)) { // exception
    } else if (arg.len > 1 and arg[0] == '-') return;
    counter_max_positionals += 1;
    std.debug.print("arg: {s}\tmax possible positionals is now: {d}\n", .{ arg, counter_max_positionals });
}
