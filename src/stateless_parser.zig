const std = @import("std");
const ArgIterator = std.process.ArgIterator;

const ParsingError = error{
    MissingValue,
    ForbiddenValue,
    ForbiddenFlagPosition,
    ForbiddenEqualPosition,
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
                    var flag_counter: u8 = 0;
                    for (arg[1..], 1..) |c, i| {
                        if (i == 1 and c == '=') {
                            std.log.err("{s}: '=' can only precede a value after a valid flag name. Got: '{s}'", .{ @errorName(ParsingError.ForbiddenEqualPosition), arg });
                            std.process.exit(1);
                        } else if (c != self.short) {
                            continue;
                        } else {
                            switch (self.req_lvl) {
                                Level.required => {
                                    if (arg.len > i + 1) {
                                        if (arg[i + 1] == '=') {
                                            return self.parseArg(arg[i..]);
                                        }
                                    }
                                    std.log.err("{s}: '{d}' requires an argument. It can be alone or the last one of a flag chain. Got: '{s}'", .{ @errorName(ParsingError.MissingValue), c, arg });
                                    std.process.exit(1);
                                },
                                Level.allowed => {
                                    if (arg.len > i + 1) { // if not last element in chain, maybe a value
                                        if (arg[i + 1] == '=') { // last element with value
                                            return self.parseArg(arg[i..]);
                                        } else if (arg[i + 1] != '=') { // not last element
                                            std.log.err("{s}: '{d}' can take an argument. It can be alone or the last one of a flag chain. Got: '{s}'", .{ @errorName(ParsingError.MissingValue), c, arg });
                                            std.process.exit(1);
                                        }
                                    } else flag_counter += 1;
                                    continue; // WARN: temporary before boolean casting implementation
                                },
                                Level.forbidden => {
                                    if (arg.len == i + 1) {
                                        flag_counter += 1;
                                        continue; // WARN: temporary before boolean casting implementation

                                    } else if (arg.len > i + 1 and arg[i + 1] == '=') {
                                        std.log.err("{s}: '{s}' cannot take an argument. Got: '{s}'", .{ @errorName(ParsingError.ForbiddenValue), arg[i .. i + 1], arg });
                                        std.process.exit(1);
                                    }
                                    flag_counter += 1;
                                    continue; // WARN: temporary before boolean casting implementation
                                },
                            }
                        }
                    }
                    if (flag_counter > 0) {
                        return &.{flag_counter};
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
                } else "";
            },
            Level.forbidden => {
                if (std.mem.indexOfScalarPos(u8, arg, 1, '=')) |pos| {
                    std.log.err("{s}: '{s}' cannot take an argument. Got: '{s}'", .{ @errorName(ParsingError.ForbiddenValue), arg[0..pos], arg });
                    std.process.exit(1);
                } else return "";
            },
        }
    }
};

const Command = struct {
    name: []const u8,
    ptr: *const fn (iter: ArgIterator) void,
};
