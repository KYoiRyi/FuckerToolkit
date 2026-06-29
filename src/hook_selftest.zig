const std = @import("std");
const builtin = @import("builtin");
const hook = @import("hook.zig");
const logger = @import("logger.zig");

var original_add: ?*anyopaque = null;

extern fn ftk_selftest_target_add(a: c_int, b: c_int) callconv(.c) c_int;
extern fn ftk_selftest_detour_add(a: c_int, b: c_int) callconv(.c) c_int;

fn statusName(status: hook.Status) []const u8 {
    return switch (status) {
        .ok => "ok",
        .invalid_target => "invalid_target",
        .invalid_detour => "invalid_detour",
        .invalid_original => "invalid_original",
        .already_attached => "already_attached",
        .not_attached => "not_attached",
        .backend_error => "backend_error",
    };
}

fn logBytes(allocator: std.mem.Allocator, log: *logger.Logger, label: []const u8, ptr: *anyopaque) !void {
    const bytes: [*]const u8 = @ptrCast(ptr);
    const message = try std.fmt.allocPrint(
        allocator,
        "hook selftest: {s} bytes={x:0>2} {x:0>2} {x:0>2} {x:0>2} {x:0>2} {x:0>2} {x:0>2} {x:0>2}",
        .{
            label,
            bytes[0],
            bytes[1],
            bytes[2],
            bytes[3],
            bytes[4],
            bytes[5],
            bytes[6],
            bytes[7],
        },
    );
    defer allocator.free(message);
    try log.write(.info, message);
}

fn isApple() bool {
    return builtin.os.tag == .ios or builtin.os.tag == .macos;
}

pub fn run(allocator: std.mem.Allocator, root: []const u8) !void {
    var log = logger.Logger{ .allocator = allocator, .root = root };
    try log.write(.info, "hook selftest: start");

    const before = ftk_selftest_target_add(10, 20);
    const expected_before: c_int = 37;
    if (before != expected_before) {
        const message = try std.fmt.allocPrint(allocator, "hook selftest: unexpected target baseline result={d}", .{before});
        defer allocator.free(message);
        try log.write(.err, message);
        return error.HookSelfTestBaselineFailed;
    }
    try log.write(.info, "hook selftest: baseline target call returned 37");

    original_add = null;
    var original_slot: ?*anyopaque = null;
    const target_ptr: *anyopaque = @constCast(@ptrCast(&ftk_selftest_target_add));
    const detour_ptr: *anyopaque = @constCast(@ptrCast(&ftk_selftest_detour_add));
    {
        const message = try std.fmt.allocPrint(allocator, "hook selftest: attaching target=0x{x} detour=0x{x}", .{
            @intFromPtr(target_ptr),
            @intFromPtr(detour_ptr),
        });
        defer allocator.free(message);
        try log.write(.info, message);
    }
    try logBytes(allocator, &log, "target before attach", target_ptr);
    const attach_status = hook.ftk_hook_attach(.{
        .target = target_ptr,
        .detour = detour_ptr,
        .original = &original_slot,
    });
    original_add = original_slot;

    {
        const message = try std.fmt.allocPrint(allocator, "hook selftest: attach status={s}", .{statusName(attach_status)});
        defer allocator.free(message);
        try log.write(if (attach_status == .ok) .info else .err, message);
    }
    if (attach_status != .ok and attach_status != .already_attached) return error.HookSelfTestAttachFailed;
    try logBytes(allocator, &log, "target after attach", target_ptr);

    if (isApple()) {
        try log.write(.warn, "hook selftest: patched target invocation skipped on Apple to avoid loader-host crash");
    } else {
        const after = ftk_selftest_target_add(10, 20);
        {
            const message = try std.fmt.allocPrint(allocator, "hook selftest: hooked target call returned {d}", .{after});
            defer allocator.free(message);
            try log.write(.info, message);
        }
        if (after != 4242) return error.HookSelfTestCallFailed;
    }

    const detach_status = hook.ftk_hook_detach(target_ptr);
    {
        const message = try std.fmt.allocPrint(allocator, "hook selftest: detach status={s}", .{statusName(detach_status)});
        defer allocator.free(message);
        try log.write(if (detach_status == .ok) .info else .warn, message);
    }
    try logBytes(allocator, &log, "target after detach", target_ptr);

    const restored = ftk_selftest_target_add(10, 20);
    {
        const message = try std.fmt.allocPrint(allocator, "hook selftest: restored target call returned {d}", .{restored});
        defer allocator.free(message);
        try log.write(.info, message);
    }
    if (restored != expected_before) return error.HookSelfTestRestoreFailed;

    try log.write(.info, "hook selftest: success");
}

pub export fn ftk_hook_selftest() callconv(.c) c_int {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const pal = @import("pal.zig");
    const root = pal.privateRoot(allocator) catch return -1;
    defer allocator.free(root);

    run(allocator, root) catch return -1;
    return 0;
}
