const std = @import("std");
const Option = @import("option.zig");
const main = @import("main.zig");

test "Option compilation" {
    const opt = Option(u8);
    _ = opt;
}

test "accept Arg" {
    const items = [_][:0]const u8{ "--my-flag=coco baby", "-f", "--my-space-separated pizza", "--forgotten-value=" };
    std.debug.print("\n", .{});
    for (items) |arg| {
        switch (main.triageArg(arg)) {
            .flag => |flag| std.debug.print("name: {s}\t\n", .{flag}),
            .valued => |val| std.debug.print("name: {s}\t value: {s}\n", .{ val.name, if (val.value) |v| v else "" }),
            .positional => |pos| std.debug.print("postitional:\t{s}\n", .{pos}),
        }
    }
}
