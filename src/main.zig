const std = @import("std");
const ArgIterator = std.process.ArgIterator;

const jump = @import("jump");

// I hope you don't mind a few colors...
const _grn = "\x1b[38;5;2m";
const _yel = "\x1b[38;5;3m";
const _blu = "\x1b[38;5;4m";
const _mag = "\x1b[38;5;5m";
const _gry = "\x1b[38;5;8m";
const _def = "\x1b[38;5;15m";

pub fn main() !void {
    var stdout_buffer: [8192]u8 = undefined;
    var writer = std.fs.File.stdout().writer(&stdout_buffer);
    const out = &writer.interface;

    // Good to know: on POSIX systems, the allocator is never used.
    // on Windows it's used once.
    //
    // The iterator in and of itself is just a book-keeper that we can cheaply copy around.
    // copying the iterator allows to have multiple jumpers starting from the same point but looking for different flags.
    var iterator = try std.process.argsWithAllocator(std.heap.page_allocator);
    defer iterator.deinit();
    var myOpt = jump.Over(ArgIterator).init(iterator, 'v', &.{ "verbose", "ver" }, .forbidden, "get useful debug output");

    try out.print(
        \\{c}{s}Jump demo
        \\
        \\{s}This demo parses args that are defined in `build.zig`.
        \\They are the following:{s}
        \\
        \\
    , .{ '\t', _grn, _gry, _blu });

    //////////////////////////////////////////////////////////
    // This is setup! This is not how we actually use jump! //
    //////////////////////////////////////////////////////////
    var throw_away_iter = iterator;
    var primed = false;
    var com_idx: u8 = 0;
    while (throw_away_iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--")) {
            try out.print("\n", .{});
            com_idx += 1;
            primed = false;
            continue;
        }
        if (primed) try out.print(", \"", .{}) else try out.print("\t[{d}]: [ \"", .{com_idx});
        primed = true;
        try std.zig.stringEscape(arg, out);
        try out.print("\" ", .{});
    } else try out.print("]\n", .{});
    //////////////////////////////////////////////////////////

    try out.print(
        \\
        \\
        \\
        \\{s}{s}Working with command [0]{s}
        \\
        \\Since no parsing is done upfront and it's rather lazy as it's done on demand,
        \\we decide to start by parsing 'v' flags.
        \\When a parser finds "--" it will return null. This allows breaking a loop and siloes commands.
        \\Here chain means for example "-alif" is a chain of 4 distinct short flags: [ 'a', 'l', 'i', 'f' ]
        \\The {s}jump.Over.next(){s} function is meant for that because the 'v' jumper is defined as having {s}.req_lvl == jump.Level.required{s}.
        \\Other Levels are {s}.allowed{s} and {s}.required{s} which return found values instead of a count.
        \\
        \\{s}
    , .{ "\t", _mag, _gry, _grn, _gry, _grn, _gry, _grn, _gry, _grn, _gry, _def });
    while (myOpt.next()) |opt| {
        // The character returned is a count **per arg** '-v' returns 1 '-vvv' returns 3
        if (opt) |val| try out.print("\t'v' count in same chain: {d}\n", .{val[0]}) else break;
    } else |err| {
        switch (err) { // For now there is only one possible error, but switching protects agains future additions...
            jump.LocalParsingError.ForbiddenValue => try out.print("Values are forbidden here! Found: {s}, {any}\n", .{ myOpt.diag.debug_hint, err }),
            jump.LocalParsingError.MissingValue => unreachable,
        }
    }

    try out.print(
        \\
        \\{s}But what if we want to count them all, regardless if they are in the (sub)command, like we have: [ "-v", "foo", "-v", "abc", "-vv" ]
        \\We want to know there are n 'v' flags in the subcommand.
        \\The {s}jump.Over.count(){s} function is meant for that.
        \\If you want to count across all argv, you will have to ignore "--" command terminators.
        \\
        \\{s}
    , .{ _gry, _grn, _gry, _def });
    var myOptCounter = jump.Over(ArgIterator).init(iterator, 'v', &.{ "verbose", "ver" }, .forbidden, "get useful debug output");
    if (myOptCounter.count()) |count| { // We consume unitl '--' included or end of argv.
        try out.print("\t'v' count in same (sub)command: {d}\n", .{count});
    } else |err| {
        switch (err) {
            jump.LocalParsingError.ForbiddenValue => try out.print("\tFound an unexpected value while counting: {s}, {any}\n", .{ myOptCounter.diag.debug_hint, err }),
            jump.LocalParsingError.MissingValue => try out.print("\tFound a flag missing a value while counting: {s}, {any}\n", .{ myOpt.diag.debug_hint, err }),
        }
    }

    try out.print(
        \\
        \\{s}Now let's jump over the positionals. (still in command [0])
        \\We will use {s}jump.OverPosLean.next(){s}
        \\This is the most basic way to iterate over positionals.
        \\if an argument doesn't start with a '-' it will match.
        \\{s}This leads to unwanted behavior if you detach values from flags
        \\(i.e. separate flags and values with other than '=', like "--data value"){s} as you can see below:
        \\"my detached data" is considered positional while it's the value for "--data"
        \\We will see next how we avoid consuming detached flag values as if they were positionals.
        \\
        \\{s}
    , .{ _gry, _grn, _gry, _yel, _gry, _def });
    var myPos = jump.OverPosLean(ArgIterator).init(iterator);
    while (myPos.next()) |val| { // first one will be the file name. The library doesn't decide to auto-discard it for you.
        try out.print("\tpositional: {s}\n", .{val});
    } else {
        try out.print("\tnull: no (more) positional argument! {s}this is where you break to avoid parsing the next command{s}\n", .{ _yel, _gry });
    }

    try out.print(
        \\
        \\Now we want the "my detached data" to be identified as a flag value. Not as a positional.
        \\This is where the "lean" gets "fat"...
        \\
        \\We need to be aware of existing flags. So we use the {s}jump.Register.nextPos(){s}.
        \\Now "my detached data" is recognized as the value of preceding "--data"
        \\
        \\{s}
    , .{ _grn, _gry, _def });
    // Options can be defined anywhere and used then.
    var myDataOpt = jump.Over(ArgIterator).init(iterator, 'd', &.{"data"}, .required, "a flag that requires data!");
    // A Register is a structure meant to provide global capabilites.
    var register = jump.Register(ArgIterator).init();
    throw_away_iter = iterator; // get a new throw away iterator to not modify the reference one.
    while (register.nextPos(&.{ myDataOpt, myOpt }, &throw_away_iter)) |opt| {
        if (opt) |val| {
            try out.print("\tflag-aware positional: {s}\n", .{val});
        } else {
            try out.print("\tnull: no (more) positional argument! {s}this is where you break to avoid parsing the next command{s}\n", .{ _yel, _gry });
            break;
        }
    } else |err| {
        try out.print("\t{any}: {s}\n", .{ err, register.diag.debug_hint });
    }

    try out.print(
        \\
        \\{s}As you can see, we can consume each flag or positional separately. Repeat things differently etc...
        \\This is actually how we consumed 'v' flags as per-chain and then per-command counts!
        \\
        \\{s}Now let's consume 'd', "data" {s} which comes first in the [0] command line.
        \\The jumper for 'd' is defined as requiring a value.
        \\However, we wrote the value detached i.e: "-k v", not "-k=v".
        \\So `jump.Over.next()` will fail:
        \\
        \\{s}
    , .{ _gry, _grn, _gry, _def });
    // prepare a copy at the same position
    var myOtherDataOpt = myDataOpt;

    if (myDataOpt.next()) |opt| {
        _ = opt; // not happening
    } else |err| {
        switch (err) {
            jump.LocalParsingError.ForbiddenValue => unreachable,
            jump.LocalParsingError.MissingValue => try out.print("\t{any}: {s}\n", .{ err, myDataOpt.diag.debug_hint }),
        }
    }

    try out.print(
        \\
        \\{s}Now let's do it again with {s}jump.Over.nextGreedy(){s}
        \\
        \\
    , .{ _gry, _grn, _def });
    if (myOtherDataOpt.nextGreedy()) |opt| {
        if (opt) |val| try out.print("\t--data value is: \"{s}\"\n", .{val});
    } else |err| {
        switch (err) {
            jump.LocalParsingError.ForbiddenValue => unreachable,
            jump.LocalParsingError.MissingValue => try out.print("\t{any}, hint: {s}\n", .{ err, myDataOpt.diag.debug_hint }),
        }
    }

    try out.print(
        \\
        \\{s}We can arbitrarily jump to next (sub)command with {s}jump.OverCommand(){s}.
        \\{s}
    , .{ _gry, _grn, _gry, _def });
    jump.OverCommand(ArgIterator, &iterator); // advancing to next subcommand without raising errors.

    try out.print(
        \\
        \\
        \\
        \\{c}{s}Working with command [1]{s}
        \\
        \\Validation is a Register capability which uses {s}jump.Register.nextPos(){s} under the hood.
        \\So it is aware of all the flags for the given validation run.
        \\It will loop and discard results until the end of the (sub)command or finding an error.
        \\(Since here we want all errors, we loop it, so it continues after finding one)
        \\
        \\This will ensure all flags are:
        \\- known
        \\- well-formed
        \\- have value if they require one
        \\- have no value if they don't take any
        \\
        \\Once validation is done and you handled everything the way you wanted,
        \\you can safely iterate over args and positionals without handling errors.
        \\{s}jump.Register.validate(){s} in a loop will enumerate all errors in the [1] (sub)command:
        \\{s}
    , .{ '\t', _mag, _gry, _grn, _gry, _grn, _gry, _def });
    throw_away_iter = iterator;
    while (true) {
        register.validate(&[_]jump.Over(ArgIterator){myOpt}, &throw_away_iter) catch |err| {
            try out.print(
                \\
                \\{c}{any}, hint: {s} {s}// Let's pretend we took action to fix and continue validation.{s}
                \\
            , .{ '\t', err, register.diag.debug_hint, _gry, _def });
            continue;
        };
        break;
    }

    try out.print(
        \\
        \\{s}All validation for the given subcommand is done.
        \\Now let's start from the same point as validation and just go over positionals one by one.
        \\This will also trigger validation on the go to know if an argument is a detached value
        \\for a flag ("-k v" here "v" is detached from k, unlike the form: "-k=v") or is a real positional.
        \\so we will get the same validation errors if any.
        \\
        \\However, since you have handled any unwanted behavior in the validation call,
        \\here you can consume without worrying about errors.
        \\
    , .{_gry});
    throw_away_iter = iterator;
    while (true) {
        if (register.nextPos(&[_]jump.Over(ArgIterator){myOpt}, &throw_away_iter)) |opt| {
            if (opt) |val| try out.print("\n\tpos: {s}\n", .{val}) else break;
        } else |err| {
            try out.print(
                \\
                \\{c}{s}Unreachable {any}, continuing happily... {s}// We pretended we took action, remember?{s}
                \\
            , .{ '\t', _def, err, _gry, _def });
        }
    }

    try out.print(
        \\
        \\
        \\
        \\{c}{s}Working with command [2]{s}
        \\
        \\Just to show in the code an exhaustive list of possible errors.
        \\Also, by now you may have noticed the "hints" that come with errors. If not, see it in the lines below:
        \\
        \\{s}
    , .{ '\t', _mag, _gry, _def });
    jump.OverCommand(ArgIterator, &iterator);

    const myOtherOpt = jump.Over(ArgIterator).init(iterator, 'd', &.{ "data", "doughnuts" }, .required, "A flag with a required/mandatory value.");
    // Now in reality, if you didn't handle things in validate, you would rather have that.
    // Here since we are advancing the iterator, this one will validate a next subcommand.
    while (true) {
        if (register.nextPos(&[_]jump.Over(ArgIterator){ myOpt, myOtherOpt }, &iterator)) |opt| {
            if (opt) |val| try out.print("\tpositional from Register: {s}\n", .{val}) else break;
        } else |err| {
            switch (err) { // Obviously I handled errs all the same. Listing here for documentation.
                error.ForbiddenValue => try out.print("\tpos: {any}, hint: {s}\n", .{ err, register.diag.debug_hint }),
                error.MissingValue => try out.print("\tpos: {any}, hint: {s}\n", .{ err, register.diag.debug_hint }),
                error.MalformedFlag => try out.print("\tpos: {any}, hint: {s}\n", .{ err, register.diag.debug_hint }),
                error.UnknownFlag => try out.print("\tpos: {any}, hint: {s}\n", .{ err, register.diag.debug_hint }),
            }
        }
    }

    try out.print(
        \\
        \\
        \\
        \\{c}{s}Working with command [3]{s}
        \\
        \\Any parsing structure when it is {s}init(){s} gets a {s}Diag{s} member.
        \\The Diag will save the argument that raised an error.
        \\If it is raised by a Register, the Diag of the Register will hold the error.
        \\If it is raised by a regular jumper, the jumper's Diag will hold the hint...
        \\See it in the code of the demo...
        \\
        \\Hints are truncated to fit in a [32]u8:
        \\
        \\{s}
    , .{ '\t', _mag, _gry, _grn, _gry, _grn, _gry, _def });

    if (register.validate(&.{myOpt}, &iterator)) |_| unreachable else |err| try out.print("\t{any}, hint: {s}\n", .{ err, register.diag.debug_hint });

    try out.print("\n{s}Args were all evaluated.\n", .{_gry});

    try out.flush();
}
