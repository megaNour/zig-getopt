const std = @import("std");
const ArgIterator = std.process.ArgIterator;

pub const LocalParsingError = error{
    ForbiddenValue,
    MissingValue,
};

pub const GlobalParsingError = error{
    MalformedFlag,
    UnknownFlag,
} || LocalParsingError;

/// Provides the centralized 'smart' behavior and flexibility people expect.
pub fn Register(comptime T: type) type {
    return struct {
        diag: Diag = Diag{ .debug_buf = undefined, .debug_hint = undefined },

        pub fn init() @This() {
            var this = @This(){};
            this.diag.init();
            return this;
        }

        /// Validates all params in until next command.
        pub fn validate(self: *@This(), jumpers: []const Over(T), iterator: *T) GlobalParsingError!void {
            while (self.nextPos(jumpers, iterator)) |opt| {
                if (opt) |_| continue else break;
            } else |err| return err;
        }

        /// This is the reliable way to get positional arguments
        /// i.e. you write any required value detached from the flag: "--option value" instead of "--option=value"
        pub fn nextPos(self: *@This(), jumpers: []const Over(T), iterator: *T) GlobalParsingError!?[]const u8 {
            while (iterator.next()) |arg| {
                if (arg.len < 2 or arg[0] != '-') return arg else if (std.mem.startsWith(u8, arg, "-=") or std.mem.startsWith(u8, arg, "--=")) {
                    self.diag.hint(arg);
                    return GlobalParsingError.MalformedFlag;
                } else if (arg[1] == '-') { // the arg is a long opt we do a regular match trial
                    if (self.try_match(jumpers, iterator, arg)) |opt| _ = opt orelse return null else |err| return err;
                } else { // the arg is a short opt(s) chain and we need to try matching each char
                    for (arg[1..]) |char| {
                        // FIX: see how we handle the '=' case when we don't pass the whole chain...
                        const dashed: [2]u8 = .{ '-', char }; // adding the '-' here allows Over.match() to only consider raw form args.
                        if (self.try_match(jumpers, iterator, &dashed)) |opt| _ = opt orelse return null else |err| return err;
                    }
                }
            } else return null;
        }

        fn try_match(self: *@This(), jumpers: []const Over(T), iterator: *T, arg: []const u8) GlobalParsingError!?void {
            for (jumpers) |jumper| {
                switch (jumper.match(arg)) { // so, we could make match() "smarter" but that would be coupling the simple parser with the Register
                    .skip => continue,
                    .short => {
                        _ = jumper.parseFlagChain(arg) catch |err| {
                            _ = peekAtNextArgForValue(self, iterator, jumper.req_lvl, arg, err) catch |peek_err| return peek_err;
                        };
                        break;
                    },
                    .long => {
                        _ = jumper.parseArg(arg) catch |err| {
                            _ = peekAtNextArgForValue(self, iterator, jumper.req_lvl, arg, err) catch |peek_err| return peek_err;
                        };
                        break;
                    },
                    .terminator => {
                        return null;
                    },
                }
            } else {
                self.diag.hint(arg);
                return GlobalParsingError.UnknownFlag;
            }
        }

        fn peekAtNextArgForValue(self: *@This(), iterator: *T, req_lvl: Level, arg: []const u8, err: LocalParsingError) LocalParsingError!void {
            if (req_lvl != .required) {
                self.diag.hint(arg);
                return err; // not interested in looking, only required level may have a detached value
            } else switch (err) {
                LocalParsingError.MissingValue => {
                    var throw_away_iter = iterator.*; // NOTE: if this fails, we don't want the next arg consumed, so we work on a copy first
                    if (throw_away_iter.next()) |next| {
                        if (next.len > 1 and next[0] == '-') {
                            self.diag.hint(arg);
                            return err;
                        }
                    }
                    _ = iterator.next(); // the next arg is safe and required to consume as it is a value for current arg.
                },
                LocalParsingError.ForbiddenValue => unreachable,
            }
        }
    };
}

fn assertIterator(comptime T: type) void {
    if (@TypeOf(T.next) == fn (*T) ?[:0]const u8 or @TypeOf(T.next) == fn (*T) ?[]const u8) {
        // fine
    } else {
        @compileError("T.next must match: fn(self: *T) ?[]const u8 or fn(self: *T) ?[:0]const u8");
    }
}

/// Advance to the next subcommand if any
pub fn OverCommand(comptime T: type, iter: *T) void {
    assertIterator(T);
    while (iter.*.next()) |arg| {
        if (std.mem.eql(u8, arg, "--")) break;
    }
}

/// Jumps over the next positional argument.
/// This is the Jump original way. No fat loop to decide if this is a positional or value.
/// You can only use this if you promise to always put '=' after your option values, never ' '.
/// Although it allows lazy and parallel parsing, this is not about performance.
/// It's about giving the user total control over: how and when he aggregates, casts or handles errors without allocation.
pub fn OverPosLean(comptime T: type) type {
    assertIterator(T);
    return struct {
        iter: T,

        pub fn init(iter: T) @This() {
            return @This(){ .iter = iter };
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
    assertIterator(T);
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

        pub fn count(self: *@This()) LocalParsingError!u8 {
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
        pub fn nextGreedy(self: *@This()) LocalParsingError!?[]const u8 {
            return self.next() catch |err| switch (err) {
                LocalParsingError.MissingValue => if (self.peekAtNextArgForValue()) |res| res else err,
                else => err,
            };
        }

        fn peekAtNextArgForValue(self: *@This()) ?[]const u8 {
            if (self.req_lvl == .required) {
                var peeker = self.iter; // make a copy of the iterator to next on it wihout losing our position
                if (peeker.next()) |peekie| {
                    if (peekie.len == 0 or peekie[0] != '-') // A valid value is here for the taking
                        return self.iter.next().?; // and so we do take it
                }
            }
            return null;
        }

        pub fn next(self: *@This()) LocalParsingError!?[]const u8 {
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

        /// At this point we consider the input is raw and starts with "--"
        fn parseArg(self: *const @This(), arg: []const u8) LocalParsingError!?[]const u8 {
            switch (self.req_lvl) {
                Level.required => {
                    if (std.mem.indexOfScalarPos(u8, arg, 3, '=')) |i| {
                        return arg[i + 1 ..];
                    } else {
                        return LocalParsingError.MissingValue;
                    }
                },
                Level.allowed => {
                    return if (std.mem.indexOfScalarPos(u8, arg, 3, '=')) |i| {
                        return arg[i + 1 ..];
                    } else return &.{1};
                },
                Level.forbidden => {
                    if (std.mem.indexOfScalarPos(u8, arg, 3, '=') != null) {
                        return LocalParsingError.ForbiddenValue;
                    } else return &.{1};
                },
            }
        }

        /// At this point we consider the input is raw and starts with '-'
        /// Reaching here proves ".short" field is not null.
        fn parseFlagChain(self: *const @This(), haystack: []const u8) LocalParsingError!?[]const u8 {
            switch (self.req_lvl) {
                Level.required => {
                    return if (std.mem.indexOfScalar(u8, haystack, self.short.?)) |pos| {
                        if (haystack.len >= pos + 2) {
                            return if (haystack[pos + 1] == '=') haystack[pos + 2 ..] else haystack[pos + 1 ..];
                        } else {
                            return LocalParsingError.MissingValue;
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
                            return LocalParsingError.ForbiddenValue;
                        }
                    }
                    return &.{n};
                },
            }
        }
    };
}
