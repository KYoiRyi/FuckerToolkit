const std = @import("std");
const builtin = @import("builtin");
const vfs = @import("vfs.zig");
const pal = @import("pal.zig");
const logger = @import("logger.zig");
const lua = @import("lua_runtime.zig");

pub const Options = extern struct {
    keep_runtime_alive: bool = false,
};

pub fn runOnce(allocator: std.mem.Allocator, options: Options) !void {
    const root = try pal.privateRoot(allocator);
    defer allocator.free(root);

    var fs = try vfs.VirtualFileSystem.init(allocator, root);
    defer fs.deinit();

    var log = logger.Logger{ .allocator = allocator, .root = fs.root };
    try log.write(.info, "bootstrap started");

    const init_path = try fs.resolveLocalUri("local://init.lua");
    defer allocator.free(init_path);

    std.fs.accessAbsolute(init_path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            try log.write(.info, "local://init.lua not found; bootstrap stopped");
            return;
        },
        else => return err,
    };

    const context_ptr = try allocator.create(lua.Context);
    context_ptr.* = try lua.Context.init(allocator, fs.root);
    const keep_runtime_alive = options.keep_runtime_alive or builtin.os.tag == .ios or builtin.os.tag == .macos;
    defer if (!keep_runtime_alive) {
        context_ptr.deinit();
        allocator.destroy(context_ptr);
    };

    try log.write(.info, "executing local://init.lua");
    try context_ptr.executeFile(init_path);
    try log.write(.info, "local://init.lua finished");
    if (keep_runtime_alive) {
        try log.write(.info, "Lua runtime kept alive after bootstrap");
    }
}

pub export fn ftk_bootstrap_run_once() callconv(.c) c_int {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    runOnce(gpa.allocator(), .{}) catch return -1;
    return 0;
}
