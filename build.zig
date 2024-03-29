const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zap = b.dependency("zap", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "sycl2023app",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.addModule("zap", zap.module("zap"));
    exe.linkLibrary(zap.artifact("facil.io"));
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    if (b.args) |args| {
        run.addArgs(args);
    }

    const run_cmd = b.step("run", "Run the app");
    run_cmd.dependOn(&run.step);

    //
    // frontend dev server
    //
    const devserver = b.addExecutable(.{
        .name = "devserver",
        .root_source_file = .{ .path = "src/frontend_dev_server.zig" },
        .target = target,
        .optimize = optimize,
    });

    devserver.addModule("zap", zap.module("zap"));
    devserver.linkLibrary(zap.artifact("facil.io"));
    b.installArtifact(devserver);

    const run_devserver = b.addRunArtifact(devserver);
    if (b.args) |args| {
        run.addArgs(args);
    }

    const run_devserver_cmd = b.step("run-devserver", "Run the dev server");
    run_devserver_cmd.dependOn(&run_devserver.step);

    //
    // particibot
    //
    const particibot = b.addExecutable(.{
        .name = "particibot",
        .root_source_file = .{ .path = "src/particibot/particibot.zig" },
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(particibot);

    const particibot_step = b.step("particibot", "Build particibot");
    particibot_step.dependOn(&particibot.step);

    const run_particibot = b.addRunArtifact(particibot);
    if (b.args) |args| {
        run.addArgs(args);
    }
    const run_particibot_cmd = b.step("run-particibot", "Run the particibot");
    run_particibot_cmd.dependOn(&run_particibot.step);

    //
    // TESTS
    //
    const participants_test = b.addTest(.{
        .root_source_file = .{ .path = "src/participants.zig" },
        .target = target,
        .optimize = optimize,
    });

    const pwauth_test = b.addTest(.{
        .root_source_file = .{ .path = "src/pwauth.zig" },
        .target = target,
        .optimize = optimize,
    });

    pwauth_test.addModule("zap", zap.module("zap"));

    const run_participants_test = b.addRunArtifact(participants_test);
    const run_pwauth_test = b.addRunArtifact(pwauth_test);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the participant to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_pwauth_test.step);
    test_step.dependOn(&run_participants_test.step);
}
