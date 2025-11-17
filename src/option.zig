const std = @import("std");
const reentrant = @import("reentrant_arg_iterator.zig");
const Arg = reentrant.Arg;
const Flag = reentrant.Flag;
const ReentrantArgIterator = reentrant.ReentrantArgIterator;
const ParseIntError = std.fmt.ParseIntError;
const ParseFloatError = std.fmt.ParseFloatError;

fn ValidateBool(merge_fn: fn (?bool, bool) bool) type {
    return struct {
        fn validate(actual: ?bool, new: []const u8) !bool {
            return merge_fn(actual, new.len > 0);
        }
    };
}

fn ValidateString(merge_fn: fn (?[]const u8, []const u8) []const u8) type {
    return struct {
        fn validate(actual: ?[]const u8, new: []const u8) ![]const u8 {
            return merge_fn(actual, new);
        }
    };
}

fn ValidateInt(comptime T: type, base: u8, merge_fn: fn (?T, T) T) type {
    return struct {
        fn validate(actual: ?T, new: []const u8) ParseIntError!T {
            return merge_fn(actual, try std.fmt.parseInt(T, new, base));
        }
    };
}

fn ValidateFloat(comptime T: type, merge_fn: fn (?T, T) T) type {
    return struct {
        fn validate(actual: ?T, new: []const u8) ParseFloatError!T {
            return merge_fn(actual, try std.fmt.parseFloat(T, new));
        }
    };
}

fn MergeReplace(comptime T: type) type {
    return struct {
        pub fn merge(actual: ?T, new: T) T {
            _ = actual;
            return new;
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
    const myStringMergingStrategy = MergeReplace([]const u8);
    const myStringValidator = ValidateString(myStringMergingStrategy.merge);
    var names3 = [_][]const u8{"my-chain"};
    var cocoString = Option([]const u8){ .long_names = &names3, .validator = myStringValidator.validate };
    _ = try cocoString.processArg(
        &iterator,
        Arg{
            .long_flag = .{
                .name = "my-chain",
                .value = "tandoury",
            },
        },
    );
    const myBoolMergingStrategy = MergeReplace(bool);
    const myBoolValidator = ValidateBool(myBoolMergingStrategy.merge);
    var names4 = [_][]const u8{"my-bool"};
    var cocoBool = Option(bool){ .long_names = &names4, .validator = myBoolValidator.validate };
    _ = try cocoBool.processArg(
        &iterator,
        Arg{
            .long_flag = .{
                .name = "my-bool",
                .value = "anything_non_null_will_result_in_true",
            },
        },
    );
    std.debug.print("\n", .{});
}

pub fn Option(comptime T: type) type {
    return struct {
        short_name: ?u8 = null,
        long_names: ?[][]const u8 = null,
        description: ?[]const u8 = null,
        required: bool = false,
        validator: *const fn (actual: ?T, new: []const u8) anyerror!T,
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
            // TODO: test purpose, remove
            switch (@TypeOf(self.value.?)) {
                bool => {
                    const label = if (value.len > 0) "true" else "false";
                    std.debug.print("\nvalue is: {s}", .{label});
                },
                u8 => std.debug.print("\nvalue is: {d}", .{self.value.?}),
                f64 => std.debug.print("\nvalue is: {e}", .{self.value.?}),
                []const u8 => std.debug.print("\nvalue is: {s}", .{self.value.?}),
                else => std.debug.print("\nvalue is (non-formatted): {any}", .{self.value.?}),
            }
        }
    };
}
