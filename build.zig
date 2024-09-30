const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lineReader = b.dependency("LineReader", .{
        .target = target,
        .optimize = optimize,
    });

    const csvLine = b.dependency("CsvLine", .{
        .target = target,
        .optimize = optimize,
    });

    const memMapper = b.dependency("MemMapper", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "csvcut",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("LineReader", lineReader.module("LineReader"));
    exe.root_module.addImport("CsvLine", csvLine.module("CsvLine"));
    exe.root_module.addImport("MemMapper", memMapper.module("MemMapper"));

    if (optimize != .Debug) {
        exe.root_module.strip = true;
        exe.root_module.single_threaded = true;
    }

    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    unit_tests.root_module.addImport("LineReader", lineReader.module("LineReader"));
    unit_tests.root_module.addImport("CsvLine", csvLine.module("CsvLine"));

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
