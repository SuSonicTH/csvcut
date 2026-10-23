const std = @import("std");
const builtin = @import("builtin");

const TargetConfig = struct {
    query: std.Target.Query,
    suffix: []const u8,
};

const release_targets = [_]TargetConfig{
    .{ .query = .{ .cpu_arch = .x86_64, .os_tag = .linux }, .suffix = "x86_64-linux" },
    .{ .query = .{ .cpu_arch = .aarch64, .os_tag = .linux }, .suffix = "aarch64-linux" },
    .{ .query = .{ .cpu_arch = .x86_64, .os_tag = .windows }, .suffix = "x86_64-windows" },
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = compileStep(b, target, optimize, "csvcut");
    b.installArtifact(exe);

    // release
    const release = b.step("release", "Build compressed release binaries for all supported platforms");
    releasebuild(b, release);

    // native
    const native = b.step("native", "Build an optimized, compressed release binary for the host");
    native.dependOn(nativebuild(b));

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    run_cmd.addPassthruArgs();

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_module = compileModule(b, target, optimize),
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

fn releasebuild(b: *std.Build, release: *std.Build.Step) void {
    const zupx = b.dependency("zupx", .{
        .optimize = std.builtin.OptimizeMode.fast,
        .target = b.graph.host,
    });

    for (release_targets) |config| {
        const target = b.resolveTargetQuery(config.query);
        const exe_name = b.fmt("csvcut-{s}", .{config.suffix});
        const install_name = if (config.query.os_tag == .windows)
            b.fmt("{s}.exe", .{exe_name})
        else
            exe_name;
        const exe = compileStep(b, target, std.builtin.OptimizeMode.fast, exe_name);
        const install_artifact = upxInstall(b, zupx, exe, install_name);
        release.dependOn(&install_artifact.step);
    }
}

/// Compresses the compiled executable with upx, installing only the packed
/// output so that the cached artifact is never modified in place.
fn upxInstall(
    b: *std.Build,
    zupx: *std.Build.Dependency,
    exe: *std.Build.Step.Compile,
    exe_name: []const u8,
) *std.Build.Step.InstallFile {
    const upx_cmd = b.addRunArtifact(zupx.artifact("upx"));
    upx_cmd.addArg("--lzma");
    upx_cmd.addArg("-o");
    const packed_path = upx_cmd.addOutputFileArg(exe_name);
    upx_cmd.addFileArg(exe.getEmittedBin());
    return b.addInstallFileWithDir(packed_path, .bin, exe_name);
}

fn nativebuild(b: *std.Build) *std.Build.Step {
    const zupx = b.dependency("zupx", .{
        .optimize = std.builtin.OptimizeMode.fast,
        .target = b.graph.host,
    });

    const exe = compileStep(b, b.graph.host, std.builtin.OptimizeMode.fast, "csvcut");
    const install_name = if (b.graph.host.result.os.tag == .windows) "csvcut.exe" else "csvcut";
    const install_artifact = upxInstall(b, zupx, exe, install_name);
    return &install_artifact.step;
}

fn compileStep(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    exe_name: []const u8,
) *std.Build.Step.Compile {
    return b.addExecutable(.{
        .name = exe_name,
        .root_module = compileModule(b, target, optimize),
    });
}

fn compileModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    const mvzr = b.createModule(.{
        .root_source_file = b.path("vendor/mvzr/mvzr.zig"),
        .target = target,
        .optimize = optimize,
    });

    return b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .strip = optimize != .debug,
        .imports = &.{
            .{ .name = "mvzr", .module = mvzr },
            .{ .name = "license", .module = licenseModule(b, target, optimize) },
        },
    });
}

/// `@embedFile` cannot reach outside the module root, so expose the license as
/// a generated module containing a copy of LICENSE.txt.
fn licenseModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    const write_files = b.addWriteFiles();
    const root = write_files.add("license.zig", "pub const text = @embedFile(\"license.txt\");\n");
    _ = write_files.addCopyFile(b.path("LICENSE.txt"), "license.txt");
    return b.createModule(.{
        .root_source_file = root,
        .target = target,
        .optimize = optimize,
    });
}
