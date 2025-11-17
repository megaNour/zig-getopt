const std = @import("std");
const reentrant = @import("reentrant_arg_iterator.zig");
const Arg = reentrant.Arg;
const Flag = reentrant.Flag;
const ReentrantArgIterator = reentrant.ReentrantArgIterator;
const ParseIntError = std.fmt.ParseIntError;

fn ValidateInt(comptime T: type, base: u8, merge_fn: fn (?T, T) T) type {
    return struct {
        fn validate(actual: ?T, new_value: []const u8) ParseIntError!T {
            switch (@typeInfo(T)) {
                .int => {},
                else => @compileError("ValidateInt only validates integers."),
            }
            return merge_fn(actual, try std.fmt.parseInt(T, new_value, base));
        }
    };
}

fn ValidateFloat(comptime T: type, merge_fn: fn (?T, T) T) type {
    return struct {
        fn validate(actual: ?T, new_value: []const u8) ParseIntError!T {
            switch (@typeInfo(T)) {
                .float => {},
                else => @compileError("ValidateInt only validates integers."),
            }
            return merge_fn(actual, try std.fmt.parseFloat(T, new_value));
        }
    };
}

fn MergeReplace(comptime T: type) type {
    return struct {
        pub fn merge(actual: ?T, new_value: T) T {
            _ = actual;
            return new_value;
        }
    };
}

test "test" {
    const myMergingStrategy = MergeReplace(u8);
    const myIntValidator = ValidateInt(u8, 10, myMergingStrategy.merge);
    var names = [_][]const u8{"max-items"};
    var cocoInt = Option(u8){ .long_names = &names, .validator = myIntValidator.validate };
    var iterator = try reentrant.argsWithAllocator(std.heap.page_allocator, true);
    _ = try cocoInt.processArg(
        &iterator,
        Arg{
            .long_flag = .{
                .name = "max-items",
                .value = "10",
            },
        },
    );
    const myFloatMergingStrategy = MergeReplace(f64);
    const myFloatValidator = ValidateFloat(f64, myFloatMergingStrategy.merge);
    var names2 = [_][]const u8{"my-factor"};
    var cocoFloat = Option(f64){ .long_names = &names2, .validator = myFloatValidator.validate };
    _ = try cocoFloat.processArg(
        &iterator,
        Arg{
            .long_flag = .{
                .name = "my-factor",
                .value = "0.3",
            },
        },
    );
}

pub fn Option(comptime T: type) type {
    return struct {
        short_name: ?u8 = null,
        long_names: ?[][]const u8 = null,
        description: ?[]const u8 = null,
        required: bool = false,
        validator: *const fn (actual: ?T, new_value: []const u8) anyerror!T,
        value: ?T = null,

        pub fn processArg(self: *@This(), iterator: *ReentrantArgIterator, arg: Arg) !bool {
            switch (arg) {
                .positional => {
                    return true;
                },
                .short_flag => |short| {
                    if (self.short_name == short.name) {
                        try self.consumeArg(short.value, iterator);
                        return true;
                    }
                    return false;
                },
                .long_flag => |long| {
                    if (self.long_names) |names| {
                        for (names) |name| {
                            if (std.mem.eql(u8, name, long.name)) {
                                try self.consumeArg(long.value, iterator);
                                return true;
                            }
                        }
                    }
                    return false;
                },
            }
        }

        fn consumeArg(self: *@This(), value: []const u8, iterator: *ReentrantArgIterator) !void {
            if (self.required and value.len == 0) { // no "=value": expect next arg to be its value
                if (iterator.first_pass) { // but only affect in first pass
                    self.value = try self.validator(self.value, iterator.next() orelse "");
                } else iterator.skip(); // otherwise, still hold counts
            }
            if (!self.required and self.value == null) {
                if (iterator.first_pass) {
                    self.value = try self.validator(self.value, value);
                }
            }
            std.debug.print("\nvalue is: {d}\n", .{self.value.?});
        }
    };
}

fn printArg(i: u8, arg: [:0]const u8) void {
    std.log.debug("arg {d}\t\"{s}\"", .{ i, arg });
}
