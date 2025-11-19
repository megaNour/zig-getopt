const std = @import("std");
const ArgIterator = std.process.ArgIterator;

const ParsingError = error{
    ForbiddenChain,
    ForbiddenEqualPosition,
    ForbiddenFlagPosition,
    ForbiddenValue,
    ForbiddenValueAtPosition,
    MissingValue,
};

pub const Positional = struct {
    iter: ArgIterator,

    pub fn init(iter: ArgIterator) Positional {
        return Positional{
            .iter = iter,
        };
    }

    pub fn next(self: *Positional) ?[]const u8 {
        while (self.iter.next()) |arg| {
            if (arg.len < 2) {
                return arg;
            } else if (arg[0] != '-') {
                return arg;
            } else if (arg.len == 2 and std.mem.eql(u8, arg, "--")) {
                return null;
            } // continue
        } else return null;
    }
};

pub const Level = enum(u2) {
    forbidden,
    allowed,
    required,
};

pub const Option = struct {
    iter: ArgIterator,
    short: ?u8,
    longs: ?[]const []const u8,
    req_lvl: Level = .forbidden,
    desc: ?[]const u8,

    pub fn init(
        arg_iterator: ArgIterator,
        short_name: ?u8,
        long_names: ?[]const []const u8,
        value_requirement_level: Level,
        description: ?[]const u8,
    ) Option {
        return Option{
            .iter = arg_iterator,
            .short = short_name,
            .longs = long_names,
            .req_lvl = value_requirement_level,
            .desc = description,
        };
    }

    pub fn next(self: *Option) ?[]const u8 {
        while (self.iter.next()) |arg| {
            if (arg.len < 2) {
                continue; // positional
            } else if (arg[0] == '-') { // option check needed
                if (arg[1] == '-') { // longs or term
                    if (arg.len == 2) {
                        return null;
                    } else {
                        if (self.longs) |longs| {
                            for (longs) |l| {
                                if (std.mem.eql(u8, arg[2..], l)) {
                                    return self.parseArg(arg[2..]);
                                }
                            }
                        }
                        continue;
                    }
                } else { // flag chain
                    for (arg[1..], 1..) |c, i| {
                        if (c == '=') {
                            if (i > 0) break; // we don't return null, we need to return flag_counter if it is > 0
                            std.log.err("{s}: '=' can only precede a value after a valid flag name. Got: '{s}'", .{ @errorName(ParsingError.ForbiddenEqualPosition), arg });
                            std.process.exit(1);
                        } else if (c != self.short) {
                            continue;
                        } else {
                            return switch (self.req_lvl) {
                                Level.required => {
                                    return self.parseArg(arg[1..]);
                                },
                                Level.allowed, Level.forbidden => {
                                    return self.parseRepeatableArgInChain(arg[1..], c);
                                },
                                // Level.forbidden => {
                                //     if (arg.len == i + 1) {
                                //         continue; // WARN: temporary before boolean casting implementation
                                //
                                //     } else if (arg.len > i + 1 and arg[i + 1] == '=') {
                                //         std.log.err("{s}: '{s}' cannot take an argument. Got: '{s}'", .{ @errorName(ParsingError.ForbiddenValue), arg[i .. i + 1], arg });
                                //         std.process.exit(1);
                                //     }
                                //     continue; // WARN: temporary before boolean casting implementation
                                // },
                            };
                        }
                    }
                }
            }
        } else return null;
    }

    /// At this point we have a string starting with a valid target flag.
    fn parseArg(self: *Option, arg: []const u8) ?[]const u8 {
        switch (self.req_lvl) {
            Level.required => {
                if (std.mem.indexOfScalarPos(u8, arg, 1, '=')) |i| {
                    if (arg[i + 1 ..].len > 0) return arg[i + 1 ..] else std.log.err("{s}: '{s}' requires a value, but none was provided.", .{ @errorName(ParsingError.MissingValue), arg[0..i] });
                    std.process.exit(1);
                } else std.log.err("{s}: '{s}' requires a value, but none was provided.", .{ @errorName(ParsingError.MissingValue), arg });
                std.process.exit(1);
            },
            Level.allowed => {
                return if (std.mem.indexOfScalarPos(u8, arg, 1, '=')) |i| {
                    if (arg[i + 1 ..].len > 0) return arg[i + 1 ..] else std.log.err("{s}: '{s}' was given with an '=' but no value was provided", .{ @errorName(ParsingError.MissingValue), arg[0..i] });
                    std.process.exit(1);
                } else return &.{1};
            },
            Level.forbidden => {
                if (std.mem.indexOfScalarPos(u8, arg, 1, '=')) |pos| {
                    std.log.err("{s}: '{s}' cannot take an argument. Got: '{s}'", .{ @errorName(ParsingError.ForbiddenValue), arg[0..pos], arg });
                    std.process.exit(1);
                } else return &.{1};
            },
        }
    }

    /// NOTE: count a repeatable flag. If the flag allows values, It can only be counted or valued in the same flag chain (like '-fffvv')
    /// We do not verify all flags in the chain are valid, we only verify that very flag.
    /// So if a poorly written flag comes after a valid one and is never required by the user, the command will not fail.
    /// ---
    /// for example: '-vvvff=blah, 'v' will count 'v' 3 if the user asks for v.
    /// This will only fail if the user requires 'f'.
    /// (it will fail because 'f' cannot be counted (2) and allow a value in the same chain)
    /// Since it is lazily checked, if the user does not requires 'f' in the flow of his command, he will not get an error.
    fn parseRepeatableArgInChain(self: *Option, haystack: []const u8, needle: u8) []const u8 {
        switch (self.req_lvl) {
            Level.required => {
                std.log.err("'parseRepeatableArgInChain' is only for checking flag repetition in a chain. Required value arguments cannot be repeated in a chain as they need to be last.", .{});
                std.process.exit(1);
            },
            Level.allowed => {
                const needle_count: u8 = @truncate(std.mem.count(u8, haystack, &.{needle}));
                const valued_count = std.mem.count(u8, haystack, &.{ needle, '=' });
                return if (needle_count == 0) unreachable else if (needle_count == 1 and valued_count == 1) {
                    return if (std.mem.indexOfScalarPos(u8, haystack, 1, '=')) |pos| haystack[pos + 1 ..] else unreachable;
                } else if (needle_count > 1 and valued_count > 0) {
                    std.log.err("{s}: '{s}' cannot take an count and an argument in the same flag chain. Got: '{s}{s}'", .{ @errorName(ParsingError.ForbiddenChain), &.{needle}, &.{'-'}, haystack });
                    std.process.exit(1);
                } else &.{needle_count};
            },
            Level.forbidden => {
                const needle_count: u8 = @truncate(std.mem.count(u8, haystack, &.{needle}));
                const valued_count = std.mem.count(u8, haystack, &.{ needle, '=' });
                return if (valued_count > 0) {
                    std.log.err("{s}: '{s}' cannot take an argument. Got: '{s}{s}'", .{ @errorName(ParsingError.ForbiddenChain), &.{needle}, &.{'-'}, haystack });
                    std.process.exit(1);
                } else &.{needle_count};
            },
        }
    }
};

const Command = struct {
    name: []const u8,
    ptr: *const fn (iter: ArgIterator) void,
};
