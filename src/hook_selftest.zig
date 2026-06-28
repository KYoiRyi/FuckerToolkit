const std = @import("std");
const hook = @import("hook.zig");
const logger = @import("logger.zig");

const AddFn = *const fn (c_int, c_int) callconv(.c) c_int;

var original_add: ?*anyopaque = null;

fn targetAdd(a: c_int, b: c_int) callconv(.c) c_int {
    return a + b + 7;
}

fn detourAdd(a: c_int, b: c_int) callconv(.c) c_int {
    _ = a;
    _ = b;
    return 4242;
}

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

pub fn run(allocator: std.mem.Allocator, root: []const u8) !void {
    var log = logger.Logger{ .allocator = allocator, .root = root };
    try log.write(.info, "hook selftest: start");

    const before = targetAdd(10, 20);
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
    const attach_status = hook.ftk_hook_attach(.{
        .target = @ptrCast(&targetAdd),
        .detour = @ptrCast(&detourAdd),
        .original = &original_slot,
    });
    original_add = original_slot;

    {
        const message = try std.fmt.allocPrint(allocator, "hook selftest: attach status={s}", .{statusName(attach_status)});
        defer allocator.free(message);
        try log.write(if (attach_status == .ok) .info else .err, message);
    }
    if (attach_status != .ok and attach_status != .already_attached) return error.HookSelfTestAttachFailed;

    const after = targetAdd(10, 20);
    {
        const message = try std.fmt.allocPrint(allocator, "hook selftest: hooked target call returned {d}", .{after});
        defer allocator.free(message);
        try log.write(.info, message);
    }
    if (after != 4242) return error.HookSelfTestCallFailed;

    const detach_status = hook.ftk_hook_detach(@ptrCast(&targetAdd));
    {
        const message = try std.fmt.allocPrint(allocator, "hook selftest: detach status={s}", .{statusName(detach_status)});
        defer allocator.free(message);
        try log.write(if (detach_status == .ok) .info else .warn, message);
    }

    const restored = targetAdd(10, 20);
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
