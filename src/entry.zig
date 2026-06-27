const builtin = @import("builtin");
const std = @import("std");
const bootstrap = @import("bootstrap.zig");

const DLL_PROCESS_ATTACH: u32 = 1;
const JNI_VERSION_1_6: c_int = 0x00010006;

pub export fn DllMain(instance: ?*anyopaque, reason: u32, reserved: ?*anyopaque) callconv(.winapi) c_int {
    _ = instance;
    _ = reserved;
    if (builtin.os.tag == .windows and reason == DLL_PROCESS_ATTACH) {
        _ = bootstrap.ftk_bootstrap_run_once();
    }
    return 1;
}

pub export fn JNI_OnLoad(vm: ?*anyopaque, reserved: ?*anyopaque) callconv(.c) c_int {
    _ = vm;
    _ = reserved;
    if (isAndroid()) {
        _ = bootstrap.ftk_bootstrap_run_once();
    }
    return JNI_VERSION_1_6;
}

pub export fn ftk_platform_constructor_entry() callconv(.c) void {
    if (builtin.os.tag == .ios or builtin.os.tag == .macos or builtin.os.tag == .linux) {
        _ = bootstrap.ftk_bootstrap_run_once();
    }
}

fn isAndroid() bool {
    return comptime std.mem.eql(u8, @tagName(builtin.target.abi), "android");
}
