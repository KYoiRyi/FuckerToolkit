const builtin = @import("builtin");
const std = @import("std");

pub const Status = enum(c_int) {
    ok = 0,
    invalid_target = 1,
    invalid_detour = 2,
    invalid_original = 3,
    already_attached = 4,
    not_attached = 5,
    backend_error = 6,
};

pub const NativeHook = extern struct {
    target: ?*anyopaque,
    detour: ?*anyopaque,
    original: ?*?*anyopaque,
};

pub export fn ftk_hook_attach(hook: NativeHook) callconv(.c) Status {
    if (hook.target == null) return .invalid_target;
    if (hook.detour == null) return .invalid_detour;
    if (hook.original == null) return .invalid_original;

    if (builtin.os.tag == .windows) return windowsAttach(hook);
    if (isAndroid()) return androidAttach(hook);
    if (builtin.os.tag == .ios or builtin.os.tag == .macos) return appleAttach(hook);
    return .backend_error;
}

pub export fn ftk_hook_detach(target: ?*anyopaque) callconv(.c) Status {
    if (target == null) return .invalid_target;

    if (builtin.os.tag == .windows) return windowsDetach(target.?);
    if (isAndroid()) return androidDetach(target.?);
    if (builtin.os.tag == .ios or builtin.os.tag == .macos) return appleDetach(target.?);
    return .backend_error;
}

fn isAndroid() bool {
    return comptime std.mem.eql(u8, @tagName(builtin.target.abi), "android");
}

const MH_OK: c_int = 0;
const MH_ERROR_ALREADY_CREATED: c_int = 5;
const MH_ERROR_NOT_CREATED: c_int = 6;
const MH_ERROR_ENABLED: c_int = 7;
const MH_ERROR_DISABLED: c_int = 8;
extern fn MH_Initialize() callconv(.c) c_int;
extern fn MH_CreateHook(target: *anyopaque, detour: *anyopaque, original: *?*anyopaque) callconv(.c) c_int;
extern fn MH_EnableHook(target: *anyopaque) callconv(.c) c_int;
extern fn MH_DisableHook(target: *anyopaque) callconv(.c) c_int;
extern fn MH_RemoveHook(target: *anyopaque) callconv(.c) c_int;

fn windowsAttach(hook: NativeHook) Status {
    const init = MH_Initialize();
    if (init != MH_OK) return .backend_error;

    const created = MH_CreateHook(hook.target.?, hook.detour.?, hook.original.?);
    if (created != MH_OK and created != MH_ERROR_ALREADY_CREATED) return .backend_error;

    const enabled = MH_EnableHook(hook.target.?);
    return switch (enabled) {
        MH_OK => .ok,
        MH_ERROR_ENABLED => .already_attached,
        else => .backend_error,
    };
}

fn windowsDetach(target: *anyopaque) Status {
    const disabled = MH_DisableHook(target);
    if (disabled != MH_OK and disabled != MH_ERROR_DISABLED) return .backend_error;

    const removed = MH_RemoveHook(target);
    return switch (removed) {
        MH_OK => .ok,
        MH_ERROR_NOT_CREATED => .not_attached,
        else => .backend_error,
    };
}

const SHADOWHOOK_MODE_SHARED: c_int = 0;
const SHADOWHOOK_HOOK_WITH_MULTI_MODE: c_int = 1;
extern fn shadowhook_init(mode: c_int, debuggable: bool) callconv(.c) c_int;
extern fn shadowhook_hook_func_addr_2(
    func_addr: *anyopaque,
    new_addr: *anyopaque,
    orig_addr: *?*anyopaque,
    flags: c_int,
) callconv(.c) ?*anyopaque;
extern fn shadowhook_unhook(handle: *anyopaque) callconv(.c) c_int;

var android_handle_count: usize = 0;
var android_targets: [128]*anyopaque = undefined;
var android_handles: [128]*anyopaque = undefined;

fn androidAttach(hook: NativeHook) Status {
    if (shadowhook_init(SHADOWHOOK_MODE_SHARED, false) != 0) return .backend_error;

    for (android_targets[0..android_handle_count]) |target| {
        if (target == hook.target.?) return .already_attached;
    }
    if (android_handle_count == android_targets.len) return .backend_error;

    const handle = shadowhook_hook_func_addr_2(
        hook.target.?,
        hook.detour.?,
        hook.original.?,
        SHADOWHOOK_HOOK_WITH_MULTI_MODE,
    ) orelse return .backend_error;

    android_targets[android_handle_count] = hook.target.?;
    android_handles[android_handle_count] = handle;
    android_handle_count += 1;
    return .ok;
}

fn androidDetach(target: *anyopaque) Status {
    for (android_targets[0..android_handle_count], 0..) |item, index| {
        if (item == target) {
            if (shadowhook_unhook(android_handles[index]) != 0) return .backend_error;
            android_handle_count -= 1;
            android_targets[index] = android_targets[android_handle_count];
            android_handles[index] = android_handles[android_handle_count];
            return .ok;
        }
    }
    return .not_attached;
}

const TinyHookBackup = extern struct {
    address: ?*anyopaque,
    jump_size: c_int,
    head_bak: [20]u8,
};
extern fn tiny_hook_ex(backup: *TinyHookBackup, function: *anyopaque, destination: *anyopaque, origin: *?*anyopaque) callconv(.c) c_int;
extern fn tiny_unhook_ex(backup: *const TinyHookBackup) callconv(.c) c_int;

var apple_backup_count: usize = 0;
var apple_targets: [128]*anyopaque = undefined;
var apple_backups: [128]TinyHookBackup = undefined;

fn appleAttach(hook: NativeHook) Status {
    for (apple_targets[0..apple_backup_count]) |target| {
        if (target == hook.target.?) return .already_attached;
    }
    if (apple_backup_count == apple_targets.len) return .backend_error;

    var backup = TinyHookBackup{
        .address = null,
        .jump_size = 0,
        .head_bak = [_]u8{0} ** 20,
    };
    if (tiny_hook_ex(&backup, hook.target.?, hook.detour.?, hook.original.?) != 0) {
        return .backend_error;
    }

    apple_targets[apple_backup_count] = hook.target.?;
    apple_backups[apple_backup_count] = backup;
    apple_backup_count += 1;
    return .ok;
}

fn appleDetach(target: *anyopaque) Status {
    for (apple_targets[0..apple_backup_count], 0..) |item, index| {
        if (item == target) {
            if (tiny_unhook_ex(&apple_backups[index]) != 0) return .backend_error;
            apple_backup_count -= 1;
            apple_targets[index] = apple_targets[apple_backup_count];
            apple_backups[index] = apple_backups[apple_backup_count];
            return .ok;
        }
    }
    return .not_attached;
}
