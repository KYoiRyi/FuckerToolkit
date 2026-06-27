const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const minhook_root = b.option([]const u8, "minhook-root", "Path to a MinHook source checkout");
    const shadowhook_root = b.option([]const u8, "shadowhook-root", "Path to an android-inline-hook source checkout");
    const tinyhook_root = b.option([]const u8, "tinyhook-root", "Path to a tinyhook source checkout");
    const lua_root = b.option([]const u8, "lua-root", "Path to a Lua 5.4 source checkout");
    const android_sysroot = b.option([]const u8, "android-sysroot", "Path to the Android NDK sysroot");
    const apple_sysroot = b.option([]const u8, "apple-sysroot", "Path to the Apple SDK sysroot");
    const apple_toolchain_include = b.option([]const u8, "apple-toolchain-include", "Path to the Apple toolchain include directory");

    const lib = b.addStaticLibrary(.{
        .name = "ftk",
        .root_source_file = b.path("src/ftk.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib.linkLibC();
    addLuaSources(
        b,
        lib,
        target,
        lua_root orelse @panic("Builds require -Dlua-root=/path/to/lua"),
        android_sysroot,
        apple_sysroot,
        apple_toolchain_include,
    );
    addHookBackendSources(b, lib, target, minhook_root, shadowhook_root, tinyhook_root, android_sysroot, apple_sysroot, apple_toolchain_include);
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

fn addLuaSources(
    b: *std.Build,
    lib: *std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
    root: []const u8,
    android_sysroot: ?[]const u8,
    apple_sysroot: ?[]const u8,
    apple_toolchain_include: ?[]const u8,
) void {
    lib.addIncludePath(.{ .cwd_relative = root });

    const files = [_][]const u8{
        b.pathJoin(&.{ root, "lapi.c" }),
        b.pathJoin(&.{ root, "lauxlib.c" }),
        b.pathJoin(&.{ root, "lbaselib.c" }),
        b.pathJoin(&.{ root, "lcode.c" }),
        b.pathJoin(&.{ root, "lcorolib.c" }),
        b.pathJoin(&.{ root, "lctype.c" }),
        b.pathJoin(&.{ root, "ldblib.c" }),
        b.pathJoin(&.{ root, "ldebug.c" }),
        b.pathJoin(&.{ root, "ldo.c" }),
        b.pathJoin(&.{ root, "ldump.c" }),
        b.pathJoin(&.{ root, "lfunc.c" }),
        b.pathJoin(&.{ root, "lgc.c" }),
        b.pathJoin(&.{ root, "linit.c" }),
        b.pathJoin(&.{ root, "liolib.c" }),
        b.pathJoin(&.{ root, "llex.c" }),
        b.pathJoin(&.{ root, "lmathlib.c" }),
        b.pathJoin(&.{ root, "lmem.c" }),
        b.pathJoin(&.{ root, "loadlib.c" }),
        b.pathJoin(&.{ root, "lobject.c" }),
        b.pathJoin(&.{ root, "lopcodes.c" }),
        b.pathJoin(&.{ root, "loslib.c" }),
        b.pathJoin(&.{ root, "lparser.c" }),
        b.pathJoin(&.{ root, "lstate.c" }),
        b.pathJoin(&.{ root, "lstring.c" }),
        b.pathJoin(&.{ root, "lstrlib.c" }),
        b.pathJoin(&.{ root, "ltable.c" }),
        b.pathJoin(&.{ root, "ltablib.c" }),
        b.pathJoin(&.{ root, "ltm.c" }),
        b.pathJoin(&.{ root, "lundump.c" }),
        b.pathJoin(&.{ root, "lutf8lib.c" }),
        b.pathJoin(&.{ root, "lvm.c" }),
        b.pathJoin(&.{ root, "lzio.c" }),
    };

    var flags = std.ArrayList([]const u8).init(b.allocator);
    flags.append("-std=c99") catch @panic("out of memory");

    if (target.result.os.tag == .windows) {
        flags.append("-DLUA_USE_WINDOWS") catch @panic("out of memory");
    } else if (target.result.os.tag == .ios or target.result.os.tag == .macos) {
        flags.append("-DLUA_USE_MACOSX") catch @panic("out of memory");
        if (apple_sysroot) |path| {
            flags.appendSlice(&.{
                "-isysroot",
                path,
                "-isystem",
                b.pathJoin(&.{ path, "usr", "include" }),
                "-iframework",
                b.pathJoin(&.{ path, "System", "Library", "Frameworks" }),
            }) catch @panic("out of memory");
        }
        if (apple_toolchain_include) |path| {
            flags.appendSlice(&.{ "-isystem", path }) catch @panic("out of memory");
        }
    } else if (isAndroid(target)) {
        flags.appendSlice(&.{ "-DLUA_USE_LINUX", "-D__ANDROID_API__=23", "-DANDROID" }) catch @panic("out of memory");
        if (android_sysroot) |path| {
            flags.appendSlice(&.{
                b.fmt("--sysroot={s}", .{path}),
                "-isystem",
                b.pathJoin(&.{ path, "usr", "include" }),
                "-isystem",
                b.pathJoin(&.{ path, "usr", "include", "aarch64-linux-android" }),
            }) catch @panic("out of memory");
        }
    } else {
        flags.append("-DLUA_USE_LINUX") catch @panic("out of memory");
    }

    lib.addCSourceFiles(.{
        .files = &files,
        .flags = flags.items,
    });
}

fn addHookBackendSources(
    b: *std.Build,
    lib: *std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
    minhook_root: ?[]const u8,
    shadowhook_root: ?[]const u8,
    tinyhook_root: ?[]const u8,
    android_sysroot: ?[]const u8,
    apple_sysroot: ?[]const u8,
    apple_toolchain_include: ?[]const u8,
) void {
    switch (target.result.os.tag) {
        .windows => {
            const root = minhook_root orelse @panic("Windows builds require -Dminhook-root=/path/to/minhook");
            addMinHook(b, lib, root, target);
        },
        .ios, .macos => {
            const root = tinyhook_root orelse @panic("Apple builds require -Dtinyhook-root=/path/to/tinyhook");
            addTinyHook(b, lib, root, apple_sysroot, apple_toolchain_include);
        },
        .linux => {
            if (isAndroid(target)) {
                const root = shadowhook_root orelse @panic("Android builds require -Dshadowhook-root=/path/to/android-inline-hook");
                addShadowHook(b, lib, root, android_sysroot);
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

fn addShadowHook(b: *std.Build, lib: *std.Build.Step.Compile, root: []const u8, sysroot: ?[]const u8) void {
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
    const c_flags = if (sysroot) |path|
        &[_][]const u8{
            "-std=c11",
            "-ffunction-sections",
            "-fdata-sections",
            "-Wno-everything",
            b.fmt("--sysroot={s}", .{path}),
            "-isystem",
            b.pathJoin(&.{ path, "usr", "include" }),
            "-isystem",
            b.pathJoin(&.{ path, "usr", "include", "aarch64-linux-android" }),
            "-D__ANDROID_API__=23",
            "-DANDROID",
        }
    else
        &[_][]const u8{
            "-std=c11",
            "-ffunction-sections",
            "-fdata-sections",
            "-Wno-everything",
            "-D__ANDROID_API__=23",
            "-DANDROID",
        };

    lib.addCSourceFiles(.{
        .files = &files,
        .flags = c_flags,
    });
}

fn addTinyHook(
    b: *std.Build,
    lib: *std.Build.Step.Compile,
    root: []const u8,
    sysroot: ?[]const u8,
    toolchain_include: ?[]const u8,
) void {
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
    var flags = std.ArrayList([]const u8).init(b.allocator);
    flags.appendSlice(&.{
        "-std=c11",
        "-fvisibility=hidden",
        "-Wno-everything",
    }) catch @panic("out of memory");
    if (sysroot) |path| {
        flags.appendSlice(&.{
            "-isysroot",
            path,
            "-isystem",
            b.pathJoin(&.{ path, "usr", "include" }),
            "-iframework",
            b.pathJoin(&.{ path, "System", "Library", "Frameworks" }),
        }) catch @panic("out of memory");
    }
    if (toolchain_include) |path| {
        flags.appendSlice(&.{
            "-isystem",
            path,
        }) catch @panic("out of memory");
    }

    lib.addCSourceFiles(.{
        .files = &files,
        .flags = flags.items,
    });
}

fn isAndroid(target: std.Build.ResolvedTarget) bool {
    return std.mem.eql(u8, @tagName(target.result.abi), "android");
}
