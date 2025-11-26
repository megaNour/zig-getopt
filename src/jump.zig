const std = @import("std");
const ArgIterator = std.process.ArgIterator;

pub const ParsingError = error{
    ForbiddenValue,
    MissingValue,
};

pub const ValidationError = error{
    MalformedFlag,
    UnknownFlag,
};

/// Provides the centralized 'smart' behavior and flexibility people expect.
pub fn Register(comptime T: type) type {
    return struct {
        iter: T,
        diag: Diag = Diag{ .debug_buf = undefined, .debug_hint = undefined },

        pub fn init(iter: T) @This() {
            var this = @This(){ .iter = iter };
            this.diag.init();
            return this;
        }

        /// If an arg starts with '-', this loops over all jumpers until it matches one or invalidates the arg.
        pub fn validate(self: *@This(), jumpers: []const Over(T)) (ValidationError || ParsingError)!void {
            var throw_away = self.iter;
            validation: while (throw_away.next()) |arg| {
                if (arg.len > 1 and arg[0] == '-') {
                    for (jumpers) |jumper| {
                        if (jumper.req_lvl == .required) {
                            switch (jumper.match(arg)) {
                                .skip => return if (std.mem.startsWith(u8, arg, "-=") or std.mem.startsWith(u8, arg, "--=")) {
                                    self.diag.hint(arg);
                                    return ParsingError.MalformedFlag;
                                } else continue,
                                .short => _ = jumper.parseFlagChain(arg) catch |err| if (self.secondChance(&throw_away, err, arg)) break else return err,
                                .long => _ = jumper.parseArg(arg) catch |err| if (self.secondChance(&throw_away, err, arg)) break else return err,
                                .terminator => break :validation,
                            }
                        }
                    } else {
                        self.diag.hint(arg);
                        return ParsingError.UnknownFlag;
                    }
                }
            }
        }

        fn secondChance(self: *@This(), iterator: *T, err: ParsingError, arg: []const u8) bool {
            if (err == ParsingError.MissingValue) {
                if (iterator.next()) |next| {
                    if (next.len > 1 and next[0] == '-') {
                        self.diag.hint(arg);
                        return false;
                    }
                }
            }
            return true;
        }

        /// This is the reliable way to get positional arguments if you write any required flag value detached from the flag: '-k v' instead of '-k=v'
        pub fn nextPos(self: *@This(), jumpers: []const Over(T)) ParsingError!?[]const u8 {
            find: while (self.iter.next()) |arg| {
                if (arg.len == 0 or arg[0] != '-') return arg else {
                    for (jumpers) |jumper| {
                        if (jumper.req_lvl == .required) {
                            switch (jumper.match(arg)) {
                                .skip => return if (!std.mem.startsWith(u8, arg, "-=") and !std.mem.startsWith(u8, arg, "--=")) arg else {
                                    self.diag.hint(arg);
                                    return ParsingError.MalformedFlag;
                                },
                                .short => _ = jumper.parseFlagChain(arg) catch |err| if (self.secondChance(&self.iter, err, arg)) continue :find else return err,
                                .long => _ = jumper.parseArg(arg) catch |err| if (self.secondChance(&self.iter, err, arg)) continue :find else return err,
                                .terminator => return null,
                            }
                        }
                    }
                    continue :find;
                }
            } else return null;
        }

        /// Since it knows all jumpers, it can also aggregate help.
        pub fn help() ParsingError!?[]const u8 {}
    };
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

        pub fn count(self: *@This()) ParsingError!u8 {
            var aggregate: u8 = 0;
            while (try self.next()) |found| {
                aggregate +|= found[0];
            }
            return aggregate;
        }

        /// Gets the next occurence of the target flag in a greedy fashion or null if none.
        /// Greedy here means if no '=value' part is found, this will use in the next argument for a value.
        /// Checking will be done in a non-altering fashion for the iterator by working on a copy.
        /// Then consumption on success will really happen so the original iterator is up-todate.
        /// DO NOT USE in combination with OverPosLean.next() - use Register.nextPos() instead
        pub fn nextGreedy(self: *@This()) ParsingError!?[]const u8 {
            return self.next() catch |err| switch (err) {
                ParsingError.MissingValue => self.peekAtNextArgForValue(&self.iter, err),
                else => err,
            };
        }

        pub fn peekAtNextArgForValue(self: *@This(), iterator: *T, err: ParsingError) ParsingError!?[]const u8 {
            if (self.req_lvl == .required) {
                var peeker = self.iter; // make a copy of the iterator to next on it wihout losing our position
                const peekie = peeker.next() orelse return err; // return the original error if we can't peek
                if (peekie.len == 0 or peekie[0] != '-') // A valid value is here for the taking
                    return iterator.next().?; // and so we do take it
            }
            return err;
        }

        pub fn next(self: *@This()) ParsingError!?[]const u8 {
            while (self.iter.next()) |arg| {
                switch (self.match(arg)) {
                    .skip => continue,
                    .short => {
                        return self.parseFlagChain(arg) catch |err| {
                            self.diag.hint(arg);
                            return err;
                        };
                    },
                    .long => {
                        return self.parseArg(arg) catch |err| {
                            self.diag.hint(arg);
                            return err;
                        };
                    },
                    .terminator => return null,
                }
            } else return null;
        }

        pub const Action = enum { skip, terminator, short, long };

        pub fn match(self: *const @This(), arg: []const u8) Action {
            if (arg.len < 2) {
                return .skip;
            } else if (arg[0] == '-') { // option check needed
                if (arg[1] == '-') { // longs or term
                    if (arg.len == 2) {
                        return .terminator;
                    } else if (arg[2] == '=') {
                        return .skip;
                    } else if (self.longs) |longs| {
                        for (longs) |l| {
                            if (arg.len >= l.len + 2 and std.mem.eql(u8, arg[2 .. l.len + 2], l)) {
                                return .long;
                            }
                        } else return .skip;
                    }
                } else if (arg[1] == '=') {
                    return .skip;
                } else { // flag chain
                    for (arg[1..]) |c| {
                        if (c == self.short) return .short;
                    }
                    return .skip;
                }
            }
            return .skip;
        }

        /// At this point we need the input to be starting with '--' then a valid target flag.
        fn parseArg(self: *const @This(), arg: []const u8) ParsingError!?[]const u8 {
            switch (self.req_lvl) {
                Level.required => {
                    if (std.mem.indexOfScalarPos(u8, arg, 3, '=')) |i| {
                        return arg[i + 1 ..];
                    } else {
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
                        return ParsingError.ForbiddenValue;
                    } else return &.{1};
                },
            }
        }

        /// The input at this point needs to be a flag chain without leading '-'.
        /// Reaching here means we know the .short field is not null.
        fn parseFlagChain(self: *const @This(), haystack: []const u8) ParsingError!?[]const u8 {
            switch (self.req_lvl) {
                Level.required => {
                    return if (std.mem.indexOfScalar(u8, haystack, self.short.?)) |pos| {
                        if (haystack.len >= pos + 2) {
                            return if (haystack[pos + 1] == '=') haystack[pos + 2 ..] else haystack[pos + 1 ..];
                        } else {
                            return ParsingError.MissingValue;
                        }
                    } else unreachable;
                },
                Level.allowed => {
                    if (std.mem.indexOfScalar(u8, haystack, self.short.?)) |pos| {
                        if (haystack.len == pos + 1) {
                            return &.{1};
                        } else {
                            return if (haystack[pos + 1] == '=') haystack[pos + 2 ..] else haystack[pos + 1 ..];
                        }
                    } else unreachable;
                },
                Level.forbidden => {
                    var n: u8 = 0;
                    for (haystack[1..], 1..) |c, i| {
                        if (c == self.short.?) {
                            n += 1;
                        } else if (c == '=' and haystack[i - 1] == self.short.?) {
                            return ParsingError.ForbiddenValue;
                        }
                    }
                    return &.{n};
                },
            }
        }
    };
}
