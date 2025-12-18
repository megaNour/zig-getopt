const std = @import("std");
const ArgIterator = std.process.ArgIterator;

const jump = @import("jump");

pub fn main() !void {
    var stdout_buffer: [1024]u8 = undefined;
    var writer = std.fs.File.stdout().writer(&stdout_buffer);
    const out = &writer.interface;

    // Good to know: on POSIX systems, the allocator is never used.
    // on Windows it's used once.
    //
    // The iterator in and of itself is just a book-keeper that we can cheaply copy around.
    // copying the iterator allows to have multiple jumpers starting from the same point but looking for different flags.
    var iterator = try std.process.argsWithAllocator(std.heap.page_allocator);
    var myOpt = jump.Over(ArgIterator).init(iterator, 'v', &.{ "verbose", "ver" }, .forbidden, "get useful debug output");

    // Jumping over a given option lazily consuming everything until end of argv or '--' included
    while (myOpt.next()) |opt| {
        // The character returned is a count **per arg** '-v' returns 1 '-vvv' returns 3
        if (opt) |val| try out.print("option count in same chain: {d}\n", .{val[0]}) else break;
    } else |err| {
        switch (err) { // For now there is only one possible error, but switching protects agains future additions...
            jump.LocalParsingError.ForbiddenValue => try out.print("Values are forbidden here! Found: {s}, {any}\n", .{ myOpt.diag.debug_hint, err }),
            jump.LocalParsingError.MissingValue => unreachable,
        }
    }

    // But what if you want to count them all, regardless if they are in the same arg or not, like -v foo -v abc -vv.
    // You want to know there are n 'v' flags in the subcommand.
    var myOptCounter = jump.Over(ArgIterator).init(iterator, 'v', &.{ "verbose", "ver" }, .forbidden, "get useful debug output");
    if (myOptCounter.count()) |count| { // We consume unitl '--' included or end of argv.
        try out.print("-v counter: {d}\n\n", .{count});
    } else |err| {
        switch (err) {
            jump.LocalParsingError.ForbiddenValue => try out.print("Found an unexpected value while counting: {s}, {any}\n", .{ myOptCounter.diag.debug_hint, err }),
            jump.LocalParsingError.MissingValue => try out.print("Found a flag missing a value while counting: {s}, {any}\n", .{ myOpt.diag.debug_hint, err }),
        }
    }

    // Jumps over positionals in a "lean" fashion.
    // Always writing your option values with an "=" is ideal as it allows more determinism in the parser.
    // However, (if like most people) you sometimes use space, like "--option value" instead of "--option=value",
    // then you cannot use this safely. See Register usage for that matter.
    var myPos = jump.OverPosLean(ArgIterator).init(iterator);
    while (myPos.next()) |val| { // first one will be the file name. The library doesn't decide to auto-discard it for you.
        try out.print("positional: {s}\n", .{val});
    } else {
        try out.print("no (more) positional argument!\n", .{});
    }
    // FIX: add an example for nextGreedy...

    // A Register is a structure meant to provide global capabilites.
    var register = jump.Register(ArgIterator).init();

    try out.print(
        \\
        \\Now let's run validation for the second subcommand.
        \\Validation is a Register capability which is aware
        \\of all the flags for the given validation run.
        \\This will ensure all flags are
        \\- welformed
        \\- known
        \\- have value if they require one
        \\- have no value if they don't take any
        \\Once validation is done and you handle everything the way you wanted,
        \\you can safely iterate over args and positionals without handling errors.
        \\All errors in that subcommand will be enumerated here.
        \\
        \\
    , .{});
    jump.OverCommand(ArgIterator, &iterator); // advancing to next subcommand without raising errors.
    var throw_away_iter = iterator;
    while (true) {
        register.validate(&[_]jump.Over(ArgIterator){myOpt}, &throw_away_iter) catch |err| {
            try out.print(
                \\validation: {any}, hint: {s}
                \\Let's pretend we took action to fix and continue validation.
                \\
                \\
            , .{ err, register.diag.debug_hint });
            continue;
        };
        break;
    }

    try out.print(
        \\All validation for the given subcommand is done.
        \\Now let's start from the same point as validation and just go over positionals one by one.
        \\This will also trigger validation on the go to know if an argument is a detached value
        \\for a flag ("-k v" here "v" is detached from k, unlike the form: "-k=v") or is a real positional.
        \\so we will get the same validation errors if any.
        \\
        \\However, since you have handled any unwanted behavior in the validation call,
        \\here you can consume without worrying about erros
        \\
        \\
    , .{});
    throw_away_iter = iterator;
    while (true) {
        if (register.nextPos(&[_]jump.Over(ArgIterator){myOpt}, &throw_away_iter)) |opt| {
            if (opt) |val| try out.print("pos: {s}\n", .{val}) else break;
        } else |_| {
            try out.print(
                \\Unreachable if you handled validation errors...
                \\continuing happily...
                \\
                \\
            , .{});
        }
    }

    try out.print(
        \\One can also arbitrarily skip a subcommand.
        \\So here we are still starting from the same base point, but we will simply skip
        \\the subcommand we just worked with. This will generate no error.
        \\
        \\
    , .{});
    jump.OverCommand(ArgIterator, &iterator);

    const myOtherOpt = jump.Over(ArgIterator).init(iterator, 'd', &.{ "data", "doughnuts" }, .required, "A flag with a required/mandatory value.");
    // Now in reality, if you didn't handle things in validate, you would rather have that.
    // Here since we are advancing the iterator, this one will validate a next subcommand.
    while (true) {
        if (register.nextPos(&[_]jump.Over(ArgIterator){ myOpt, myOtherOpt }, &iterator)) |opt| {
            if (opt) |val| try out.print("positional from Register: {s}\n", .{val}) else break;
        } else |err| {
            switch (err) { // Obviously I handled errs all the same. Listing here for documentation.
                error.ForbiddenValue => try out.print("pos: {any}, hint: {s}\n", .{ err, register.diag.debug_hint }),
                error.MissingValue => try out.print("pos: {any}, hint: {s}\n", .{ err, register.diag.debug_hint }),
                error.MalformedFlag => try out.print("pos: {any}, hint: {s}\n", .{ err, register.diag.debug_hint }),
                error.UnknownFlag => try out.print("pos: {any}, hint: {s}\n", .{ err, register.diag.debug_hint }),
            }
        }
    }

    try out.print("Args were all evaluated.", .{});
    // defer will not "try" but force handling (catch...) I just want a bubble up...
    try out.flush();
}
