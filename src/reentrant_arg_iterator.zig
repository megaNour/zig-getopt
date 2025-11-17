const std = @import("std");
const Allocator = std.mem.Allocator;
const ArgIterator = std.process.ArgIterator;
const InitError = std.process.ArgIterator.InitError;

pub fn argsWithAllocator(allocator: Allocator, first_pass: bool) ArgIterator.InitError!ReentrantArgIterator {
    return ReentrantArgIterator.init(allocator, first_pass);
}

/// init() and deinit() to free eventual internal buffers
pub const ReentrantArgIterator = struct {
    first_pass: bool,
    iter: ArgIterator,

    fn init(allocator: Allocator, first_pass: bool) ArgIterator.InitError!ReentrantArgIterator {
        return ReentrantArgIterator{
            .iter = try std.process.argsWithAllocator(allocator),
            .first_pass = first_pass,
        };
    }

    pub fn deinit(self: *ReentrantArgIterator) void {
        self.iter.deinit();
    }

    pub fn next(self: *ReentrantArgIterator) ?[]const u8 {
        return self.iter.next();
    }

    pub fn skip(self: *ReentrantArgIterator) void {
        _ = self.iter.skip();
    }
};

pub fn Flag(comptime T: type) type {
    return struct {
        name: T,
        value: []const u8,
    };
}

pub const Arg = union(enum) {
    short_flag: Flag(u8),
    long_flag: Flag([]const u8),
    positional: []const u8,
};

fn triageArg(arg: [:0]const u8) Arg {
    if (arg[0] == '-') { // option
        if (arg[1] == '-') { // long or terminator
            if (arg.len == 2) { // -- terminator
                return .{ .positional = arg };
            }
            return parseArg(arg[2..]); // long
        } else { // short
            return parseArg(arg[1..]);
        }
    } else { // positional
        return .{ .positional = arg };
    }
}

fn parseArg(arg: [:0]const u8) Arg {
    if (std.mem.indexOfScalar(u8, arg, '=')) |i| {
        const name: []const u8 = arg[0..i];
        const value: []const u8 = arg[i + 1 .. :0];
        return Arg{ .valued = .{ .name = name, .value = value } };
    } else {
        const name: []const u8 = arg[0.. :0];
        return Arg{ .flag = name };
    }
}
