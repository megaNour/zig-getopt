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
    const run_exe = b.addRunArtifact(exe);
    run_step.dependOn(&run_exe.step);

    if (b.args) |args| {
        run_exe.addArgs(args);
    }

    const mod_tests = b.addTest(.{
        .root_module = test_mod,
    });

    const test_step = b.step("test", "Run tests");
    const run_mod_tests = b.addRunArtifact(mod_tests);
    test_step.dependOn(&run_mod_tests.step);

    const demo_step = b.step("demo", "Run demo");
    const run_exe_demo = b.addRunArtifact(exe);
    run_exe_demo.addArgs(&.{
        "--data",
        "my detached data",
        "-vv",
        "-vvvv",
        "positional 1",
        "positional 2",
        "--",
        "-vvvv=forbidden",
        "--=",
        "aaa",
        "-ve",
        "bbb",
        "--",
        "-v",
        "ddd",
        "-d",
        "--unknown",
        "value-identified-as-positional-after-unknown-flag-rejection",
        "-v=forbidden_value",
        "--",
        "-v=this value is way too long to fit in the Diag hint buffer so it is truncated",
    });
    demo_step.dependOn(&run_exe_demo.step);
}
