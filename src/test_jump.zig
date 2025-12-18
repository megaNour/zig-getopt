const std = @import("std");
const ArgIterator = std.process.ArgIterator;
const expect = std.testing.expect;
const expectError = std.testing.expectError;

const jump = @import("jump.zig");

pub const StringIterator = struct {
    stock: []const []const u8,
    pos: usize = 0,

    pub fn next(self: *StringIterator) ?[]const u8 {
        var res: ?[]const u8 = null;
        if (self.pos < self.stock.len) {
            res = self.stock[self.pos];
            self.pos += 1;
        }
        return res;
    }
};

test "jump flags with forbidden value affectation" {
    // Simulate argv, we will parse -v, --verbose on it
    // This iterator is const because we only use it as a base point to make variable copies that start from that point.
    const iterator = StringIterator{ .stock = &.{ "--verbose", "alif", "--ba", "-ta", "-vv", "-av", "--", "-vvv" } };
    //                                             |    1                               2       1    --      3|
    //                                             |————————————————————————— 4 —————————————————————||—— 3 ——|

    // declare a jumper
    var jumper = jump.Over(StringIterator).init(iterator, 'v', &.{"verbose"}, .forbidden, "verbose logs");

    // define another starting from the same point
    var copyOfJumper = jumper;

    // get your verbose level
    try expect(4 == try copyOfJumper.count());

    // or read the elements one by one
    try expect(1 == (try jumper.next()).?[0]);
    try expect(2 == (try jumper.next()).?[0]);
    try expect(1 == (try jumper.next()).?[0]);

    // hit the '--' terminator
    try expect(null == try jumper.next());
    try expect(3 == (try jumper.next()).?[0]);

    // count() already did consume it so you can count the next segment directly
    try expect(3 == try copyOfJumper.count());

    // reach the end
    try expect(null == try jumper.next());
}

test "jump flags with wrong value affectation" {
    const iterator = StringIterator{ .stock = &.{ "--verbose=a", "alif", "--ba", "-ta", "-vv=", "-av", "-v=vv" } };
    var jumper = jump.Over(StringIterator).init(iterator, 'v', &.{"verbose"}, .forbidden, "verbose logs");

    try expectError(jump.LocalParsingError.ForbiddenValue, jumper.next());
    try expect(std.mem.eql(u8, jumper.diag.debug_hint, "--verbose=a"));

    // You can still continue parsing
    try expectError(jump.LocalParsingError.ForbiddenValue, jumper.next());
    try expect(std.mem.eql(u8, jumper.diag.debug_hint, "-vv="));

    try expect(1 == (try jumper.next()).?[0]); // '-av'

    try expectError(jump.LocalParsingError.ForbiddenValue, jumper.next());
    try expect(std.mem.eql(u8, jumper.diag.debug_hint, "-v=vv"));
}

test "jump failure provides debug hints" {
    const iterator = StringIterator{ .stock = &.{ "-v", "-v=123", "-abcdefghijklmnopqrstuv=very_long_option_name_is_here_for_you" } };
    var jumper = jump.Over(StringIterator).init(iterator, 'v', &.{"verbose"}, .forbidden, "verbose logs");

    // success case
    try expect(1 == (try jumper.next()).?[0]);
    // no error, no debug hint
    try expect(jumper.diag.debug_hint.len == 0);

    // failure case
    try expectError(jump.LocalParsingError.ForbiddenValue, jumper.next());
    try expect(std.mem.eql(u8, jumper.diag.debug_hint, "-v=123"));

    // hints are truncated to not go over 32 chars
    try expectError(jump.LocalParsingError.ForbiddenValue, jumper.next());
    try expect(std.mem.eql(u8, jumper.diag.debug_hint, "-abcdefghijklmnopqrstuv=very_..."));
}

test "jump flags with allowed value affectation" {
    const iterator = StringIterator{ .stock = &.{ "-vc=auto", "-vvvc", "-bac=", "--color=", "-cthis '=' is in a value" } };
    var jumper = jump.Over(StringIterator).init(iterator, 'c', &.{"color"}, .allowed, "activate colored output. Default is auto.");

    try expect(std.mem.eql(u8, (try jumper.next()).?, "auto"));
    try expect(1 == (try jumper.next()).?[0]);

    // '=' with no value results in an emtpy string. Be it a short or long flag
    try expect(std.mem.eql(u8, (try jumper.next()).?, ""));
    try expect(std.mem.eql(u8, (try jumper.next()).?, ""));

    // short form of a allowed value flag will automatically take everything on the right as its value
    try expect(std.mem.eql(u8, (try jumper.next()).?, "this '=' is in a value"));
}

test "jump flags with required value affectation" {
    const iterator = StringIterator{ .stock = &.{ "-d=alif", "-vd=va", "-d", "-d=", "--data=", "-dthis '=' is in a value" } };
    var jumper = jump.Over(StringIterator).init(iterator, 'd', &.{"data"}, .required, "data flag, you must point to a valid file.");

    // restricted is close to allowed, it can't be in the middle of a flag chain
    try expect(std.mem.eql(u8, (try jumper.next()).?, "alif"));
    try expect(std.mem.eql(u8, (try jumper.next()).?, "va"));

    try expectError(jump.LocalParsingError.MissingValue, jumper.next());
    try expect(std.mem.eql(u8, jumper.diag.debug_hint, "-d"));

    // '=' with no value results in an emtpy string. Be it a short or long flag
    try expect(std.mem.eql(u8, (try jumper.next()).?, ""));
    try expect(std.mem.eql(u8, (try jumper.next()).?, ""));

    // short form of a required value flag will automatically take everything on the right as its value
    try expect(std.mem.eql(u8, (try jumper.next()).?, "this '=' is in a value"));
}

test "jump greedy" {
    const iterator = StringIterator{ .stock = &.{ "-d", "alif", "--data=", "ba", "--data", "-d", "-d=", "--data", "abc" } };
    var jumper = jump.Over(StringIterator).init(iterator, 'd', &.{"data"}, .required, "data flag, you must point to a valid file.");

    try expect(std.mem.eql(u8, (try jumper.nextGreedy()).?, "alif"));
    try expect(std.mem.eql(u8, (try jumper.nextGreedy()).?, ""));

    try expectError(jump.LocalParsingError.MissingValue, jumper.next());
    try expect(std.mem.eql(u8, jumper.diag.debug_hint, "--data"));

    try expectError(jump.LocalParsingError.MissingValue, jumper.next());
    try expect(std.mem.eql(u8, jumper.diag.debug_hint, "-d"));

    try expect(std.mem.eql(u8, (try jumper.nextGreedy()).?, ""));
    try expect(std.mem.eql(u8, (try jumper.nextGreedy()).?, "abc"));
}

test "edge cases" {
    var iterator = StringIterator{ .stock = &.{ "-=abcdef", "--=abcdef", "=abcdef" } };
    var jumper = jump.Over(StringIterator).init(iterator, 'a', &.{"alif"}, .required, "a random flag");
    var pos = jump.OverPosLean(StringIterator).init(iterator);

    try expect((try jumper.count()) == 0);
    try expect(std.mem.eql(u8, pos.next().?, "=abcdef"));

    const jumpers = [_]jump.Over(StringIterator){jumper};
    var register = jump.Register(StringIterator).init();
    try expectError(jump.GlobalParsingError.MalformedFlag, register.validate(&jumpers, &iterator));
}

test "jump over command" {
    // if you have subcommands you can make your reference iterator a var, so you can set it at the start of a subcommand
    // and then give it as a base for all your jumpers
    var iterator = StringIterator{ .stock = &.{ "-d", "alif", "--data=", "ba", "--", "hello" } };
    jump.OverCommand(StringIterator, &iterator);
    var next_command = jump.OverPosLean(StringIterator).init(iterator);
    try expect(std.mem.eql(u8, next_command.next().?, "hello"));
}

// The Register is a different beast.
// It has a global knowledge of flags, allowing to make '=' optional in some case
// and it detect flag typos (not value pertinence).
// Register tests act on the whole list of arguments, they require some init... redoing it by test was the most straight-forward way...
test "register validation OK" {
    var iterator = StringIterator{ .stock = &.{ "-d", "alif", "--data", "-" } };
    const jumper = jump.Over(StringIterator).init(iterator, 'd', &.{"data"}, .required, "data flag, you must point to a valid file.");
    const other = jump.Over(StringIterator).init(iterator, 'e', &.{"extra"}, .required, "just so we don't have a 1 element array of jumpers");
    const jumpers = [_]jump.Over(StringIterator){ jumper, other };
    var register = jump.Register(StringIterator).init();
    register.validate(&jumpers, &iterator) catch |err| {
        std.debug.print("err: {any}, hint: {s}\n", .{ err, register.diag.debug_hint });
        return err;
    };
}

test "register validation UnknownFlag error" {
    var iterator = StringIterator{ .stock = &.{ "-d", "alif", "--dota", "-" } };
    const jumper = jump.Over(StringIterator).init(iterator, 'd', &.{"data"}, .required, "data flag, you must point to a valid file.");
    const other = jump.Over(StringIterator).init(iterator, 'e', &.{"extra"}, .required, "just so we don't have a 1 element array of jumpers");
    const jumpers = [_]jump.Over(StringIterator){ jumper, other };
    var register = jump.Register(StringIterator).init();
    try expectError(jump.GlobalParsingError.UnknownFlag, register.validate(&jumpers, &iterator));
    try expect(std.mem.eql(u8, register.diag.debug_hint, "--dota"));
}

test "register validation MalformedFlag error" {
    var iterator = StringIterator{ .stock = &.{ "-d", "alif", "--=", "-" } };
    const jumper = jump.Over(StringIterator).init(iterator, 'd', &.{"data"}, .required, "data flag, you must point to a valid file.");
    const other = jump.Over(StringIterator).init(iterator, 'e', &.{"extra"}, .required, "just so we don't have a 1 element array of jumpers");
    const jumpers = [_]jump.Over(StringIterator){ jumper, other };
    var register = jump.Register(StringIterator).init();
    try expectError(jump.GlobalParsingError.MalformedFlag, register.validate(&jumpers, &iterator));
    try expect(std.mem.eql(u8, register.diag.debug_hint, "--="));
}

test "register validation only affects current subcommand" {
    var iterator = StringIterator{ .stock = &.{ "-d", "alif", "--data", "ba", "--", "-e", "ok", "-x", "not ok" } };
    const jumper = jump.Over(StringIterator).init(iterator, 'd', &.{"data"}, .required, "data flag, you must point to a valid file.");
    const other = jump.Over(StringIterator).init(iterator, 'e', &.{"extra"}, .required, "just so we don't have a 1 element array of jumpers");
    const jumpers = [_]jump.Over(StringIterator){ jumper, other };
    var register = jump.Register(StringIterator).init();
    // validate the first subcommand only
    var throw_away_iterator = iterator;
    try register.validate(&jumpers, &throw_away_iterator);
    // now suppose I know I want the second subcommand but I don't want to validate the previous one.
    jump.OverCommand(StringIterator, &iterator); // now the first subcommand is behind
    // and I can validate the next one
    try expectError(jump.GlobalParsingError.UnknownFlag, register.validate(&jumpers, &iterator));
    try expect(std.mem.eql(u8, register.diag.debug_hint, "-x"));
}

test "next pos with optional '='" {
    var iterator = StringIterator{ .stock = &.{ "-d", "alif", "positional", "-vx", "--xoxo", "ba", "--data", "ta", "--data=tha", "-d", "jiim", "last" } };
    const jumper = jump.Over(StringIterator).init(iterator, 'd', &.{"data"}, .required, "data flag, you must point to a valid file.");
    const other = jump.Over(StringIterator).init(iterator, 'v', &.{"verbose"}, .forbidden, "just so we don't have a 1 element array of jumpers");
    const jumpers = [_]jump.Over(StringIterator){ jumper, other };
    var register = jump.Register(StringIterator).init();
    try expect(std.mem.eql(u8, (try register.nextPos(&jumpers, &iterator)).?, "positional"));
    try expectError(jump.GlobalParsingError.UnknownFlag, register.nextPos(&jumpers, &iterator));
    try expect(std.mem.eql(u8, register.diag.debug_hint, "-x")); // unknown flag will not consume next.
    try expectError(jump.GlobalParsingError.UnknownFlag, register.nextPos(&jumpers, &iterator));
    try expect(std.mem.eql(u8, register.diag.debug_hint, "--xoxo")); // unknown flag will not consume next.
    try expect(std.mem.eql(u8, (try register.nextPos(&jumpers, &iterator)).?, "ba"));
    try expect(std.mem.eql(u8, (try register.nextPos(&jumpers, &iterator)).?, "last"));
}
