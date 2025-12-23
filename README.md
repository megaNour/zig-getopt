# jump

## What it does

`jump` helps you parse argv efficiently and safely:

- getopt-like syntax.
- chain-awareness: handle combined short flags like "-abc".
- Lazy: parse targeted arguments only when you need them.
- No forced upfront declaration.
- Optional upfront validation.
- No allocation, no reorder, no rewrite: literally jump between targeted args.
- Independent cursors: jumpers can be duplicated, repeated from a given point.
- Works in a strict & effective fashion: '=' required.
- Works In a classic fat loop style: '=' optional.
- Subcommands are supported.
- Full control is given over value interpretation and error handling.
- No State-holding structures are forcefully pushed on you.
- Fits in ~350 lines of code.

## What It Does Not Do

```zig
// not implemented - not planned to be
jump.parseEverythingCastEverythingHandleEveryErrorAllocateWhatYouSeeFit()
```

## How to Use

### A Demo

```sh
$ zig build demo # all you need to know with comprehensive examples
$ zig build test # no-noise, straight to the point behaviors
```

### An Idea

```zig
    var iterator = try std.process.argsWithAllocator(std.heap.page_allocator); // the allocator is never used on POSIX, once on windows...
    var myOpt = jump.Over(ArgIterator).init(iterator, 'v', &.{ "verbose", "ver" }, .forbidden, "get useful debug output");

    while (myOpt.next()) |opt| {
        // The character returned is a count **per arg** '-v' returns 1 '-vvv' returns 3
        if (opt) |val| try out.print("\t'v' count in same chain: {d}\n", .{val[0]}) else break;
    } else |err| {
        switch (err) { // For now there is only one possible error, but switching protects agains future additions...
            jump.LocalParsingError.ForbiddenValue => try out.print("{any}, hint: {s}, {any}\n", .{ err, myOpt.diag.debug_hint }),
            jump.LocalParsingError.MissingValue => unreachable, // the flag was declared with Level.forbidden
        }
    }
```

### Parsing Styles

`jump` has two main ways:

- strict syntax: lean and deterministic: '=' is mandatory between flags and values.

  - `jump.OverPosLean.next()` - only works if '=' is always used
  - `jump.OverCommand()` - jump to next (sub)command.
  - `jump.Over.count()` - count all occurrences of the target flag in the (sub)command
  - `jump.Over.next()` - jump to the next occurrence of the target flag in the (sub)command

- classical, flexible syntax, fat-loop based: '=' is optional but flags must be
  known to discriminate positionals from arg values.

  - `jump.Over.nextGreedy()` - when missing value (no '=' found), peeks at next arg
  - `jump.Register.nextPos()` - instead of `jump.OverPosLean.next()`
  - `jumpRegister.validate()` - validate a whole (sub)command upfront - if desired

### Diag

All parsing structures (`jump.Over*`, `jump.Register`...) have a diag member.
This structure will hold a debug hint in case of error. (see in [An Idea](#an-idea))
