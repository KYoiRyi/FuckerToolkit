const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "ftk",
        .root_source_file = b.path("src/ftk.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib.linkLibC();
    b.installArtifact(lib);

    const check_step = b.step("check", "Compile the toolkit library");
    check_step.dependOn(&lib.step);

    const tests = b.addTest(.{
        .root_source_file = b.path("src/ftk.zig"),
        .optimize = optimize,
    });
    tests.linkLibC();

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run host unit tests");
    test_step.dependOn(&run_tests.step);
}
