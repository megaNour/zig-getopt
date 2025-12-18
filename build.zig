const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const mod = b.addModule("jump", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/test_jump.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "jump", .module = mod },
        },
    });

    const exe = b.addExecutable(.{
        .name = "jump",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "jump", .module = mod },
            },
        }),
    });

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{
        .root_module = test_mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const run_exe_tests = b.addRunArtifact(exe);
    run_exe_tests.addArgs(&.{
        "-vv",
        "-vvvv",
        "my positional",
        "my other positional",
        "--",
        "-vvvv=forbidden",
        "--=",
        "-ve",
        "aaa",
        "bbb",
        "--",
        "-v",
        "ddd",
        "-d",
        "--unknown",
        "value-identified-as-positional-after-unknown-flag-rejection",
        "-v=forbidden_value",
    });

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
