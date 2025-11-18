const std = @import("std");
const ArgIterator = std.process.ArgIterator;

pub const Parser: type = struct {
    iter: ArgIterator,
    only_positionals: bool = false,

    pub fn init(iter: ArgIterator) Parser {
        return Parser{
            .iter = iter,
        };
    }

    /// deinits the underlying ArgIterator
    pub fn deinit(self: *Parser) void {
        self.iter.deinit();
    }

    pub fn nextPositional(self: *Parser) ?[]const u8 {
        return while (self.iter.next()) |arg| {
            _ = arg;
        };
    }

    pub fn nextShort(self: *Parser, name: u8) ?[]const u8 {
        return while (self.iter.next()) |arg| {
            if (arg.len == 2 and std.mem.eql(u8, "--", arg)) return null;
            if (arg[0] == '-' and arg[1] == name) {
                if (std.mem.indexOfScalarPos(u8, arg, 2, '=')) |i| {
                    break arg[i + 1 ..];
                }
                break "";
            }
        } else null;
    }

    pub fn nextLong(self: *Parser, name: []const u8) ?[]const u8 {
        return while (self.iter.next()) |arg| {
            if (arg.len == 2 and std.mem.eql(u8, "--", arg)) return null;
            if (std.mem.startsWith(u8, "--", arg) and std.mem.eql(u8, arg[2..], name)) {
                if (std.mem.indexOfScalarPos(u8, arg, 2, '=')) |i| {
                    break arg[i + 1 ..];
                }
                break "";
            }
        } else null;
    }

    //
    // fn triageArg(arg: [:0]const u8) Arg {
    //     if (arg[0] == '-') { // option
    //         if (arg[1] == '-') { // long or terminator
    //             if (arg.len == 2) { // -- terminator
    //                 return .{ .positional = arg };
    //             }
    //             return parseArg(arg[2..]); // long
    //         } else { // short
    //             return parseArg(arg[1..]);
    //         }
    //     } else { // positional
    //         return .{ .positional = arg };
    //     }
    // }
    //
    // fn parseArg(arg: [:0]const u8) Arg {
    //     if (std.mem.indexOfScalar(u8, arg, '=')) |i| {
    //         const name: []const u8 = arg[0..i];
    //         const value: []const u8 = arg[i + 1 .. :0];
    //         return Arg{ .valued = .{ .name = name, .value = value } };
    //     } else {
    //         const name: []const u8 = arg[0.. :0];
    //         return Arg{ .flag = name };
    //     }
    // }
    // nextShort(name: u8)
    // nextLong(name: []const u8)
    // nextTerm()
    // nextPositional()
    // aggregateShort(name: u8, allocator: Allocator)
    // aggregateLong(name: []const u8, allocator: Allocator)
};
