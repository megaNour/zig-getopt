const std = @import("std");
const ArgIterator = std.process.ArgIterator;

pub const ParsingError = error{
    ForbiddenEqualPosition,
    ForbiddenFlagPosition,
    ForbiddenValue,
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

    pub fn count(self: *Option) u8 {
        var aggregate: u8 = 0;
        while (self.next()) |found| {
            aggregate +|= found[0];
        }
        return aggregate;
    }

    pub fn next(self: *Option) ?[]const u8 {
        while (self.iter.next()) |arg| {
            if (arg.len < 2) {
                continue; // positional
            } else if (arg[0] == '-') { // option check needed
                if (arg[1] == '-') { // longs or term
                    if (arg.len == 2) {
                        return null;
                    } else if (self.longs) |longs| {
                        for (longs) |l| {
                            if (std.mem.eql(u8, arg[2..], l)) {
                                return self.parseArg(arg[2..]);
                            }
                        }
                    } else continue;
                } else { // flag chain
                    for (arg[1..], 1..) |c, i| {
                        if (c == '=') {
                            if (i > 0) return null else {
                                std.log.err(
                                    "{s}: '=' can only precede a value after a valid flag name. Got: '{s}'",
                                    .{ @errorName(ParsingError.ForbiddenEqualPosition), arg },
                                );
                                std.process.exit(1);
                            }
                        } else if (c != self.short) {
                            continue;
                        } else {
                            return switch (self.req_lvl) {
                                Level.required => {
                                    return self.parseFlagChain(arg[1..], c);
                                },
                                Level.allowed, Level.forbidden => {
                                    return self.parseFlagChain(arg[1..], c);
                                },
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
                    if (arg[i + 1 ..].len > 0) {
                        return arg[i + 1 ..];
                    } else {
                        std.log.err(
                            "{s}: '{s}' requires a value, but none was provided.",
                            .{ @errorName(ParsingError.MissingValue), arg[0..i] },
                        );
                        std.process.exit(1);
                    }
                } else std.log.err(
                    "{s}: '{s}' requires a value, but none was provided.",
                    .{ @errorName(ParsingError.MissingValue), arg },
                );
                std.process.exit(1);
            },
            Level.allowed => {
                return if (std.mem.indexOfScalarPos(u8, arg, 1, '=')) |i| {
                    if (arg[i + 1 ..].len > 0) {
                        return arg[i + 1 ..];
                    } else {
                        std.log.err(
                            "{s}: '{s}' was given with an '=' but no value was provided.",
                            .{ @errorName(ParsingError.MissingValue), arg[0..i] },
                        );
                    }
                    std.process.exit(1);
                } else return &.{1};
            },
            Level.forbidden => {
                if (std.mem.indexOfScalarPos(u8, arg, 1, '=')) |pos| {
                    std.log.err(
                        "{s}: '{s}' cannot take an argument. Got: '{s}'",
                        .{ @errorName(ParsingError.ForbiddenValue), arg[0..pos], arg },
                    );
                    std.process.exit(1);
                } else return &.{1};
            },
        }
    }

    /// The input at this point needs to be a flag chain without leading '-'.
    /// The needle needs to be guaranteed != '=' and seen before any '='
    fn parseFlagChain(self: *Option, haystack: []const u8, needle: u8) []const u8 {
        switch (self.req_lvl) {
            Level.required => {
                if (std.mem.indexOfScalar(u8, haystack, needle)) |pos| {
                    if (haystack.len >= pos + 2) {
                        if (haystack[pos + 1] == '=') {
                            if (haystack.len == pos + 2) {
                                std.log.err(
                                    "{s}: '{s}' requires a non-empty value. Got: '-{s}'.",
                                    .{ @errorName(ParsingError.MissingValue), &.{needle}, haystack },
                                );
                                std.process.exit(1);
                            }
                            return haystack[pos + 2 ..];
                        } else {
                            std.log.err(
                                "{s}: '{s}' requires '=' affectation. It can only be last in a flag chain. Got: '-{s}'.",
                                .{ @errorName(ParsingError.ForbiddenFlagPosition), &.{needle}, haystack },
                            );
                            std.process.exit(1);
                        }
                    } else {
                        std.log.err(
                            "{s}: '{s}' requires '=' affectation. Got: '-{s}'.",
                            .{ @errorName(ParsingError.MissingValue), &.{needle}, haystack },
                        );
                        std.process.exit(1);
                    }
                } else unreachable;
            },
            Level.allowed => {
                if (std.mem.indexOfScalar(u8, haystack, needle)) |pos| {
                    if (haystack.len == pos + 1) {
                        return &.{1};
                    } else if (haystack[pos + 1] == '=') {
                        if (haystack.len == pos + 2) {
                            std.log.err(
                                "{s}: {s} has an empty '=' affectation which is ambiguous. Got: '-{s}'.",
                                .{ @errorName(ParsingError.ForbiddenFlagPosition), &.{needle}, haystack },
                            );
                            std.process.exit(1);
                        }
                        return haystack[pos + 2 ..];
                    } else {
                        std.log.err(
                            "{s}: {s} supports '=' affectation. It can only be last in a flag chain. Got: '-{s}'.",
                            .{ @errorName(ParsingError.ForbiddenFlagPosition), &.{needle}, haystack },
                        );
                        std.process.exit(1);
                    }
                } else unreachable;
                std.log.err(
                    "'parseFlagChain' is only for checking flag repetition in a chain. {s}",
                    .{"Only args without value do repeat in the same flag chain."},
                );
                std.process.exit(1);
            },
            Level.forbidden => {
                var n: u8 = 0;
                for (haystack, 0..) |c, i| {
                    if (c == needle) {
                        n += 1;
                    } else if (c == '=' and haystack[i - 1] == needle) {
                        std.log.err(
                            "{s}: {s} does not support '=' affectation. Got: '-{s}'",
                            .{ @errorName(ParsingError.ForbiddenValue), &.{needle}, haystack },
                        );
                        std.process.exit(1);
                    }
                }
                return &.{n};
            },
        }
    }
};

const Command = struct {
    name: []const u8,
    ptr: *const fn (iter: ArgIterator) void,
};
