const std = @import("std");
const vfs = @import("vfs.zig");
const pal = @import("pal.zig");

pub const Options = extern struct {
    keep_runtime_alive: bool = false,
};

pub fn runOnce(allocator: std.mem.Allocator, options: Options) !void {
    _ = options;

    const root = try pal.privateRoot(allocator);
    defer allocator.free(root);

    var fs = try vfs.VirtualFileSystem.init(allocator, root);
    defer fs.deinit();

    const init_path = try fs.resolveLocalUri("local://init.lua");
    defer allocator.free(init_path);

    std.fs.accessAbsolute(init_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };

    // Lua embedding is intentionally a separate backend concern in this Zig
    // rewrite; this bootstrap verifies the private script path and leaves
    // execution to a caller-provided runtime binding.
}

export fn ftk_bootstrap_run_once() callconv(.c) c_int {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    runOnce(gpa.allocator(), .{}) catch return -1;
    return 0;
}

