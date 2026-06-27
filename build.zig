const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const minhook_root = b.option([]const u8, "minhook-root", "Path to a MinHook source checkout");
    const shadowhook_root = b.option([]const u8, "shadowhook-root", "Path to an android-inline-hook source checkout");
    const tinyhook_root = b.option([]const u8, "tinyhook-root", "Path to a tinyhook source checkout");

    const lib = b.addStaticLibrary(.{
        .name = "ftk",
        .root_source_file = b.path("src/ftk.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib.linkLibC();
    addHookBackendSources(b, lib, target, minhook_root, shadowhook_root, tinyhook_root);
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

fn addHookBackendSources(
    b: *std.Build,
    lib: *std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
    minhook_root: ?[]const u8,
    shadowhook_root: ?[]const u8,
    tinyhook_root: ?[]const u8,
) void {
    switch (target.result.os.tag) {
        .windows => {
            const root = minhook_root orelse @panic("Windows builds require -Dminhook-root=/path/to/minhook");
            addMinHook(b, lib, root, target);
        },
        .ios, .macos => {
            const root = tinyhook_root orelse @panic("Apple builds require -Dtinyhook-root=/path/to/tinyhook");
            addTinyHook(b, lib, root);
        },
        .linux => {
            if (isAndroid(target)) {
                const root = shadowhook_root orelse @panic("Android builds require -Dshadowhook-root=/path/to/android-inline-hook");
                addShadowHook(b, lib, root);
            }
        },
        else => {},
    }
}

fn addMinHook(b: *std.Build, lib: *std.Build.Step.Compile, root: []const u8, target: std.Build.ResolvedTarget) void {
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ root, "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ root, "src", "hde" }) });

    const hde_file = if (target.result.cpu.arch == .x86) "hde32.c" else "hde64.c";
    const files = [_][]const u8{
        b.pathJoin(&.{ root, "src", "buffer.c" }),
        b.pathJoin(&.{ root, "src", "hook.c" }),
        b.pathJoin(&.{ root, "src", "trampoline.c" }),
        b.pathJoin(&.{ root, "src", "hde", hde_file }),
    };
    lib.addCSourceFiles(.{
        .files = &files,
        .flags = &.{
            "-std=c11",
            "-DWIN32_LEAN_AND_MEAN",
        },
    });
}

fn addShadowHook(b: *std.Build, lib: *std.Build.Step.Compile, root: []const u8) void {
    const cpp = b.pathJoin(&.{ root, "shadowhook", "src", "main", "cpp" });
    lib.addIncludePath(.{ .cwd_relative = cpp });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ cpp, "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ cpp, "arch", "arm64" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ cpp, "common" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ cpp, "third_party", "xdl" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ cpp, "third_party", "bsd" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ cpp, "third_party", "lss" }) });

    const files = [_][]const u8{
        b.pathJoin(&.{ cpp, "shadowhook.c" }),
        b.pathJoin(&.{ cpp, "sh_elf.c" }),
        b.pathJoin(&.{ cpp, "sh_enter.c" }),
        b.pathJoin(&.{ cpp, "sh_hub.c" }),
        b.pathJoin(&.{ cpp, "sh_island.c" }),
        b.pathJoin(&.{ cpp, "sh_jni.c" }),
        b.pathJoin(&.{ cpp, "sh_linker.c" }),
        b.pathJoin(&.{ cpp, "sh_recorder.c" }),
        b.pathJoin(&.{ cpp, "sh_safe.c" }),
        b.pathJoin(&.{ cpp, "sh_switch.c" }),
        b.pathJoin(&.{ cpp, "sh_task.c" }),
        b.pathJoin(&.{ cpp, "sh_xdl.c" }),
        b.pathJoin(&.{ cpp, "arch", "arm64", "sh_a64.c" }),
        b.pathJoin(&.{ cpp, "arch", "arm64", "sh_inst.c" }),
        b.pathJoin(&.{ cpp, "arch", "arm64", "sh_glue.S" }),
        b.pathJoin(&.{ cpp, "common", "bytesig.c" }),
        b.pathJoin(&.{ cpp, "common", "sh_errno.c" }),
        b.pathJoin(&.{ cpp, "common", "sh_log.c" }),
        b.pathJoin(&.{ cpp, "common", "sh_ref.c" }),
        b.pathJoin(&.{ cpp, "common", "sh_trampo.c" }),
        b.pathJoin(&.{ cpp, "common", "sh_util.c" }),
        b.pathJoin(&.{ cpp, "third_party", "xdl", "xdl.c" }),
        b.pathJoin(&.{ cpp, "third_party", "xdl", "xdl_iterate.c" }),
        b.pathJoin(&.{ cpp, "third_party", "xdl", "xdl_linker.c" }),
    };
    lib.addCSourceFiles(.{
        .files = &files,
        .flags = &.{
            "-std=c11",
            "-ffunction-sections",
            "-fdata-sections",
            "-Wno-everything",
        },
    });
}

fn addTinyHook(b: *std.Build, lib: *std.Build.Step.Compile, root: []const u8) void {
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ root, "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ root, "src" }) });

    const files = [_][]const u8{
        b.pathJoin(&.{ root, "src", "memory.c" }),
        b.pathJoin(&.{ root, "src", "tinyhook.c" }),
        b.pathJoin(&.{ root, "src", "interpose.c" }),
        b.pathJoin(&.{ root, "src", "symbol.c" }),
        b.pathJoin(&.{ root, "src", "objcrt.c" }),
        b.pathJoin(&.{ root, "src", "exhook.c" }),
    };
    lib.addCSourceFiles(.{
        .files = &files,
        .flags = &.{
            "-std=c11",
            "-fvisibility=hidden",
            "-Wno-everything",
        },
    });
}

fn isAndroid(target: std.Build.ResolvedTarget) bool {
    return std.mem.eql(u8, @tagName(target.result.abi), "android");
}
