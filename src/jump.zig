const std = @import("std");
const ArgIterator = std.process.ArgIterator;

pub const ParsingError = error{
    ForbiddenEqualPosition,
    ForbiddenFlagPosition,
    ForbiddenValue,
    MissingValue,
};

pub fn OverPos(comptime T: type) type {
    comptime if (@TypeOf(T.next) == fn (*T) ?[:0]const u8 or @TypeOf(T.next) == fn (*T) ?[]const u8) {
        // fine
    } else {
        @compileError("T.next must match: fn(self: *T) ?[]const u8 or fn(self: *T) ?[:0]const u8");
    };
    return struct {
        iter: T,

        pub fn init(iter: T) @This() {
            return @This(){
                .iter = iter,
            };
        }

        pub fn next(self: *@This()) ?[]const u8 {
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
}

pub const Level = enum(u2) {
    forbidden,
    allowed,
    required,
};

pub fn Over(comptime T: type) type {
    comptime if (@TypeOf(T.next) == fn (*T) ?[:0]const u8 or @TypeOf(T.next) == fn (*T) ?[]const u8) {
        // fine
    } else {
        @compileError("T.next must match: fn(self: *T) ?[]const u8 or fn(self: *T) ?[:0]const u8");
    };
    return struct {
        iter: T,
        short: ?u8,
        longs: ?[]const []const u8,
        req_lvl: Level = .forbidden,
        desc: ?[]const u8,

        pub fn init(
            arg_iterator: T,
            short_name: ?u8,
            long_names: ?[]const []const u8,
            value_requirement_level: Level,
            description: ?[]const u8,
        ) @This() {
            return @This(){
                .iter = arg_iterator,
                .short = short_name,
                .longs = long_names,
                .req_lvl = value_requirement_level,
                .desc = description,
            };
        }

        pub fn count(self: *@This()) u8 {
            var aggregate: u8 = 0;
            while (self.next()) |found| {
                aggregate +|= found[0];
            }
            return aggregate;
        }

        pub fn next(self: *@This()) ParsingError!?[]const u8 {
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
                                        "'=' can only precede a value after a valid flag name. Got: '{s}'",
                                        .{arg},
                                    );
                                    return ParsingError.ForbiddenEqualPosition;
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
        fn parseArg(self: *@This(), arg: []const u8) ParsingError![]const u8 {
            switch (self.req_lvl) {
                Level.required => {
                    if (std.mem.indexOfScalarPos(u8, arg, 1, '=')) |i| {
                        if (arg[i + 1 ..].len > 0) {
                            return arg[i + 1 ..];
                        } else {
                            std.log.err(
                                "'{s}' requires a value, but none was provided.",
                                .{arg[0..i]},
                            );
                            return ParsingError.MissingValue;
                        }
                    } else std.log.err(
                        "'{s}' requires a value, but none was provided.",
                        .{arg},
                    );
                    return ParsingError.MissingValue;
                },
                Level.allowed => {
                    return if (std.mem.indexOfScalarPos(u8, arg, 1, '=')) |i| {
                        if (arg[i + 1 ..].len > 0) {
                            return arg[i + 1 ..];
                        } else {
                            std.log.err(
                                "'{s}' was given with an '=' but no value was provided.",
                                .{arg[0..i]},
                            );
                        }
                        return ParsingError.MissingValue;
                    } else return &.{1};
                },
                Level.forbidden => {
                    if (std.mem.indexOfScalarPos(u8, arg, 1, '=')) |pos| {
                        std.log.err(
                            "'{s}' cannot take an argument. Got: '{s}'",
                            .{ arg[0..pos], arg },
                        );
                        return ParsingError.ForbiddenValue;
                    } else return &.{1};
                },
            }
        }

        /// The input at this point needs to be a flag chain without leading '-'.
        /// The needle needs to be guaranteed != '=' and seen before any '='
        fn parseFlagChain(self: *@This(), haystack: []const u8, needle: u8) ParsingError![]const u8 {
            switch (self.req_lvl) {
                Level.required => {
                    if (std.mem.indexOfScalar(u8, haystack, needle)) |pos| {
                        if (haystack.len >= pos + 2) {
                            if (haystack[pos + 1] == '=') {
                                if (haystack.len == pos + 2) {
                                    std.log.err(
                                        "'{s}' requires a non-empty value. Got: '-{s}'.",
                                        .{ &.{needle}, haystack },
                                    );
                                    return ParsingError.MissingValue;
                                }
                                return haystack[pos + 2 ..];
                            } else {
                                std.log.err(
                                    "'{s}' requires '=' affectation. It can only be last in a flag chain. Got: '-{s}'.",
                                    .{ &.{needle}, haystack },
                                );
                                return ParsingError.ForbiddenFlagPosition;
                            }
                        } else {
                            std.log.err(
                                "'{s}' requires '=' affectation. Got: '-{s}'.",
                                .{ &.{needle}, haystack },
                            );
                            return ParsingError.MissingValue;
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
                                    "{s} has an empty '=' affectation which is ambiguous. Got: '-{s}'.",
                                    .{ &.{needle}, haystack },
                                );
                                ParsingError.MissingValue;
                            }
                            return haystack[pos + 2 ..];
                        } else {
                            std.log.err(
                                "{s} supports '=' affectation. It can only be last in a flag chain. Got: '-{s}'.",
                                .{ &.{needle}, haystack },
                            );
                            return ParsingError.ForbiddenFlagPosition;
                        }
                    } else unreachable;
                },
                Level.forbidden => {
                    var n: u8 = 0;
                    for (haystack, 0..) |c, i| {
                        if (c == needle) {
                            n += 1;
                        } else if (c == '=' and haystack[i - 1] == needle) {
                            std.log.err(
                                "{s} does not support '=' affectation. Got: '-{s}'",
                                .{ &.{needle}, haystack },
                            );
                            return ParsingError.ForbiddenValue;
                        }
                    }
                    return &.{n};
                },
            }
        }
    };
}
