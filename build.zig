const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mvzr = b.createModule(.{
        .root_source_file = b.path("vendor/mvzr/mvzr.zig"),
        .target = target,
        .optimize = optimize,
    });

    // `@embedFile` cannot reach outside the module root, so expose the
    // license as a generated module containing a copy of LICENSE.txt.
    const license = blk: {
        const write_files = b.addWriteFiles();
        const root = write_files.add("license.zig", "pub const text = @embedFile(\"license.txt\");\n");
        _ = write_files.addCopyFile(b.path("LICENSE.txt"), "license.txt");
        break :blk b.createModule(.{ .root_source_file = root });
    };

    const exe = b.addExecutable(.{
        .name = "csvcut",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "mvzr", .module = mvzr },
                .{ .name = "license", .module = license },
            },
        }),
    });

    if (optimize != .debug) {
        exe.root_module.strip = true;
    }

    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    run_cmd.addPassthruArgs();

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "mvzr", .module = mvzr },
                .{ .name = "license", .module = license },
            },
        }),
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit and integration tests");
    test_step.dependOn(&run_unit_tests.step);

    // The integration suite executes the built binary, so only run it when the
    // build targets the host platform (and a POSIX shell is available).
    if (builtin.target.os.tag != .windows and
        target.result.os.tag == builtin.target.os.tag and
        target.result.cpu.arch == builtin.target.cpu.arch)
    {
        const integration = b.addSystemCommand(&.{ "bash", "test/integration.sh" });
        integration.has_side_effects = true;
        integration.addArtifactArg(exe);

        const integration_step = b.step("integration", "Run integration tests");
        integration_step.dependOn(&integration.step);

        test_step.dependOn(&integration.step);
    }
}
