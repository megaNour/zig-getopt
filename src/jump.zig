const std = @import("std");
const ArgIterator = std.process.ArgIterator;

pub const ParsingError = error{
    ForbiddenEqualPosition,
    ForbiddenFlagPosition,
    ForbiddenValue,
    MissingValue,
};

/// Provides the centralized 'smart' behavior and flexibility people expect.
pub fn Registry(comptime T: type) type {
    const this: Registry(T) = struct {
        jumpers: []T,
        diag: Diag = Diag{ .debug_buf = undefined, .debug_hint = undefined },

        /// If an arg starts with '-', this loops over all jumpers until it matches one or invalidates the arg.
        pub fn validate() ParsingError!void {}
        /// Since it knows all jumpers, it can also aggregate help.
        pub fn help() ParsingError!?[]const u8 {}
        /// This is the reliable way to get positional arguments if you write your flag values without '='
        pub fn nextPos() ParsingError!?[]const u8 {}
    };

    return this;
}

/// Jumps over the next positional argument.
/// This is the Jump original way. No fat loop to decide if this is a positional or value.
/// You can only use this if you promise to always put '=' after your option values, never ' '.
/// Although it allows lazy and parallel parsing, this is not about performance.
/// It's about giving the user total control over: how and when he aggregates, casts or handles errors without allocation.
pub fn OverPosLean(comptime T: type) type {
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

pub const Diag: type = struct {
    debug_buf: [32]u8,
    debug_hint: []u8,

    pub fn init(self: *Diag) void {
        self.debug_hint = self.debug_buf[0..0];
    }

    pub fn hint(self: *Diag, arg: []const u8) void {
        const max: usize = if (self.debug_buf.len >= arg.len) arg.len else self.debug_buf.len;
        std.mem.copyForwards(u8, &self.debug_buf, arg[0..max]);
        if (self.debug_buf.len < arg.len) {
            self.debug_hint = self.debug_buf[0..self.debug_buf.len];
            std.mem.copyForwards(u8, self.debug_hint[max - 3 ..], "...");
        } else {
            self.debug_hint = self.debug_buf[0..max];
        }
    }
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
        diag: Diag = Diag{ .debug_hint = undefined, .debug_buf = undefined },

        pub fn init(
            arg_iterator: T,
            short_name: ?u8,
            long_names: ?[]const []const u8,
            value_requirement_level: Level,
            description: ?[]const u8,
        ) @This() {
            var this = @This(){
                .iter = arg_iterator,
                .short = short_name,
                .longs = long_names,
                .req_lvl = value_requirement_level,
                .desc = description,
            };
            this.diag.init();
            return this;
        }

        pub fn count(self: *@This()) !u8 {
            var aggregate: u8 = 0;
            while (try self.next()) |found| {
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
                                if (arg.len >= l.len + 2 and std.mem.eql(u8, arg[2 .. l.len + 2], l)) {
                                    return self.parseArg(arg);
                                }
                            }
                        } else continue;
                    } else { // flag chain
                        for (arg[1..], 1..) |c, i| {
                            if (c == '=') {
                                if (i > 0) return null else {
                                    self.diag.hint(arg);
                                    return ParsingError.ForbiddenEqualPosition;
                                }
                            } else if (c != self.short) {
                                continue;
                            } else {
                                return switch (self.req_lvl) {
                                    Level.required => {
                                        return self.parseFlagChain(arg, c);
                                    },
                                    Level.allowed, Level.forbidden => {
                                        return self.parseFlagChain(arg, c);
                                    },
                                };
                            }
                        }
                    }
                }
            } else return null;
        }

        /// At this point we need the input to be starting with '--' then a valid target flag.
        fn parseArg(self: *@This(), arg: []const u8) ParsingError!?[]const u8 {
            switch (self.req_lvl) {
                Level.required => {
                    if (std.mem.indexOfScalarPos(u8, arg, 3, '=')) |i| {
                        return arg[i + 1 ..];
                    } else {
                        self.diag.hint(arg);
                        return ParsingError.MissingValue;
                    }
                },
                Level.allowed => {
                    return if (std.mem.indexOfScalarPos(u8, arg, 3, '=')) |i| {
                        return arg[i + 1 ..];
                    } else return &.{1};
                },
                Level.forbidden => {
                    if (std.mem.indexOfScalarPos(u8, arg, 3, '=') != null) {
                        self.diag.hint(arg);
                        return ParsingError.ForbiddenValue;
                    } else return &.{1};
                },
            }
        }

        /// The input at this point needs to be a flag chain without leading '-'.
        /// The needle needs to be guaranteed != '=' and seen before any '='
        fn parseFlagChain(self: *@This(), haystack: []const u8, needle: u8) ParsingError!?[]const u8 {
            switch (self.req_lvl) {
                Level.required => {
                    if (std.mem.indexOfScalar(u8, haystack, needle)) |pos| {
                        if (haystack.len >= pos + 2) {
                            if (haystack[pos + 1] == '=') {
                                return haystack[pos + 2 ..];
                            } else {
                                self.diag.hint(haystack);
                                return ParsingError.ForbiddenFlagPosition;
                            }
                        } else {
                            self.diag.hint(haystack);
                            return ParsingError.MissingValue;
                        }
                    } else unreachable;
                },
                Level.allowed => {
                    if (std.mem.indexOfScalar(u8, haystack, needle)) |pos| {
                        if (haystack.len == pos + 1) {
                            return &.{1};
                        } else if (haystack[pos + 1] == '=') {
                            return haystack[pos + 2 ..];
                        } else {
                            self.diag.hint(haystack);
                            return ParsingError.ForbiddenFlagPosition;
                        }
                    } else unreachable;
                },
                Level.forbidden => {
                    var n: u8 = 0;
                    for (haystack[1..], 1..) |c, i| {
                        if (c == needle) {
                            n += 1;
                        } else if (c == '=' and haystack[i - 1] == needle) {
                            self.diag.hint(haystack);
                            return ParsingError.ForbiddenValue;
                        }
                    }
                    return &.{n};
                },
            }
        }
    };
}
