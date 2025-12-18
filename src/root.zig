const jump = @import("jump.zig");

// Global because aware of all flags
pub const GlobalParsingError = jump.GlobalParsingError;
// Happens even when not other-flags-aware
pub const LocalParsingError = jump.LocalParsingError;

// The regular flag jumper
pub const Over = jump.Over;
// Jump to next subcommand
pub const OverCommand = jump.OverCommand;
// Jump to next positional in the simplest, fastest form.
// Only reliable if you write args as "--option=value" NOT "--option value"
pub const OverPosLean = jump.OverPosLean;
// Can validate all args of a command or get next positional even in "--option value" form
pub const Register = jump.Register;
