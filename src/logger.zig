const std = @import("std");
const pal = @import("pal.zig");
const vfs = @import("vfs.zig");

pub const Level = enum {
    debug,
    info,
    warn,
    err,

    fn label(self: Level) []const u8 {
        return switch (self) {
            .debug => "DEBUG",
            .info => "INFO",
            .warn => "WARN",
            .err => "ERROR",
        };
    }
};

pub const Logger = struct {
    allocator: std.mem.Allocator,
    root: []const u8,

    pub fn write(self: *const Logger, level: Level, message: []const u8) !void {
        try writeToRoot(self.allocator, self.root, level, message);
    }
};

pub fn writeToRoot(allocator: std.mem.Allocator, root: []const u8, level: Level, message: []const u8) !void {
    var fs = try vfs.VirtualFileSystem.init(allocator, root);
    defer fs.deinit();

    const path = try fs.resolveLocalUri("local://toolkit.log");
    defer allocator.free(path);

    const file = try std.fs.createFileAbsolute(path, .{ .truncate = false });
    defer file.close();
    try file.seekFromEnd(0);

    var buffer: [64]u8 = undefined;
    const timestamp = std.fmt.bufPrint(&buffer, "{}", .{std.time.timestamp()}) catch "0";
    try file.writer().print("[{s}] [{s}] {s}\n", .{ timestamp, level.label(), message });
}

pub fn writeDefault(allocator: std.mem.Allocator, level: Level, message: []const u8) !void {
    const root = try pal.privateRoot(allocator);
    defer allocator.free(root);
    try writeToRoot(allocator, root, level, message);
}

fn levelFromInt(value: c_int) Level {
    return switch (value) {
        0 => .debug,
        2 => .warn,
        3 => .err,
        else => .info,
    };
}

pub export fn ftk_log_write(level: c_int, message: [*:0]const u8) callconv(.c) c_int {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const msg = std.mem.span(message);
    writeDefault(gpa.allocator(), levelFromInt(level), msg) catch return -1;
    return 0;
}

