const std = @import("std");
const ArgIterator = std.process.ArgIterator;

const ParsingError = error{
    NoSuchFlag,
    MissingValue,
    ForbiddenValue,
    ForbiddenFlagPosition,
};

const Parser = struct {
    iter: ArgIterator,
    options: ?[]Option,
    commands: ?[]Command,

    pub fn init(iter: ArgIterator, options: ?[]Option, commands: ?[]Command) Parser {
        var p = Parser{
            .iter = iter,
            .options = options,
            .commands = commands,
        };
        p.triageArgs(iter); // take a throwable copy to check all flags
    }

    pub fn nextPositional(self: *Parser) ?[]const u8 {
        _ = self;
        // validate()
        // here we Option.matchAndMaybeJump
        // or return a positional
    }

    fn matchOption(self: *Parser, flag: []const u8) ParsingError!Option {
        _ = flag;
        _ = self;
        // check against options if the flag exists
    }

    fn matchShort(self: *Parser, flag: []const u8) ParsingError!Option {
        _ = flag;
        _ = self;
        // check against options if the flag exists
    }

    fn matchLong(self: *Parser, flag: []const u8) ParsingError!Option {
        _ = flag;
        _ = self;
        // check against options if the flag exists
    }

    fn matchCommand(self: *Parser, flag: []const u8) ParsingError!Command {
        _ = flag;
        _ = self;
        // check against options if the flag exists
    }

    fn launcCommand(self: *Parser, iter: ArgIterator, cmd: Command) void {
        _ = self;
        cmd.ptr(iter);
    }

    /// checks all flags are known
    fn triageArgs(iter: ArgIterator) ParsingError!bool {
        while (iter.next()) |arg| {
            if (arg.len > 0 and arg[0] == '-') { // option check needed
                if (arg.len > 1 and arg[1] == '-') { // longs or term
                    if (arg.len == 2) {
                        // terminator
                    } else {
                        // check check longs
                    }
                } else { // flag chain
                    // check if last letter needs a jump
                }
                // error on unknown flag
            } else { // positional
                // return .{ .positional = arg };
            }
        } else return false;
    }
};

pub const Positional = struct {
    iter: ArgIterator,
    value: ?[]const u8,
};

pub const OptionRequirementLevel = enum(u2) {
    forbidden,
    allowed,
    required,
};

pub const Option = struct {
    iter: ArgIterator,
    short: ?u8,
    longs: ?[]const u8,
    req_lvl: OptionRequirementLevel = .forbidden,
    desc: ?[]const u8,

    pub fn init(
        short_name: ?u8,
        long_names: []const u8,
        value_requirement_level: bool,
        description: []const u8,
    ) Option {
        return Option{
            .short = short_name,
            .longs = long_names,
            .req_lvl = value_requirement_level,
            .desc = description,
        };
    }

    pub fn next(self: Option) ?[]const u8 {
        while (self.iter.next()) |arg| {
            if (arg.len > 0 and arg[0] == '-') { // option check needed
                if (arg.len == 1) {
                    return null; // positional
                } else if (arg[1] == '-') { // longs or term
                    if (arg.len == 2) {
                        return null;
                    } else {
                        for (self.longs) |l| {
                            if (std.mem.eql(u8, arg[2..], l)) {
                                parseArg(arg[2..]);
                            }
                        }
                        return null;
                    }
                } else { // flag chain
                    for (arg[1..], 2..) |c, i| {
                        if (c != self.short) {
                            continue;
                        } else switch (self.req_lvl) {
                            OptionRequirementLevel.required => {
                                if (arg.len == i or (arg.len == i + 1 and arg[arg.len - 1] == '=')) {
                                    self.parseArg(arg[1..]);
                                } else {
                                    return ParsingError.ForbiddenFlagPosition;
                                }
                            },
                            OptionRequirementLevel.allowed => {
                                if (arg.len == i + 1 and arg[arg.len - 1] == '=') {
                                    self.parseArg(arg[1..]);
                                } else {
                                    return ParsingError.ForbiddenFlagPosition;
                                }
                            },
                            OptionRequirementLevel.forbidden => {
                                self.parseArg(arg);
                            },
                        }
                    } // check if last letter needs a jump
                }
                // error on unknown flag
            } else { // positional
                // return .{ .positional = arg };
            }
        } else return false;
    }

    fn parseArg(self: *Option, arg: [:0]const u8) ParsingError!?[]const u8 {
        switch (self.req_lvl) {
            OptionRequirementLevel.forbidden => {
                if (std.mem.indexOfScalar(u8, arg, '=')) return ParsingError.ForbiddenValue;
            },
            OptionRequirementLevel.allowed => {
                if (std.mem.indexOfScalar(u8, arg, '=')) |i| {
                    return if (arg[i + 1 ..].len > 0) arg[i + 1 ..] else null;
                }
            },
            OptionRequirementLevel.required => {
                if (std.mem.indexOfScalar(u8, arg, '=')) |i| {
                    if (arg[i + 1 ..].len > 0) return arg[i + 1 ..] else return ParsingError.MissingValue;
                } else {
                    if (self.iter.next()) |val| {
                        if (val.len > 0 and val[0] != '-') {
                            return val;
                        } else return ParsingError.MissingValue;
                    }
                }
            },
        }
    }

    pub fn matchAndMaybeJump(iter: ArgIterator) bool {
        _ = iter;
    }

    fn printError() void {}
};

const Command = struct {
    name: []const u8,
    ptr: *const fn (iter: ArgIterator) void,
};
