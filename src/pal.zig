const std = @import("std");
const builtin = @import("builtin");

pub fn privateRoot(allocator: std.mem.Allocator) ![]u8 {
    return switch (builtin.os.tag) {
        .windows => windowsRoot(allocator),
        .android => androidRoot(allocator),
        .ios, .macos => appleRoot(allocator),
        else => posixRoot(allocator),
    };
}

fn envOrNull(allocator: std.mem.Allocator, name: []const u8) ?[]u8 {
    return std.process.getEnvVarOwned(allocator, name) catch null;
}

fn windowsRoot(allocator: std.mem.Allocator) ![]u8 {
    if (envOrNull(allocator, "LOCALAPPDATA")) |base| {
        defer allocator.free(base);
        return std.fs.path.join(allocator, &.{ base, "FuckerToolkit" });
    }
    if (envOrNull(allocator, "TEMP")) |base| {
        defer allocator.free(base);
        return std.fs.path.join(allocator, &.{ base, "FuckerToolkit" });
    }
    return allocator.dupe(u8, "C:\\FuckerToolkit");
}

fn androidRoot(allocator: std.mem.Allocator) ![]u8 {
    if (envOrNull(allocator, "FTK_PRIVATE_ROOT")) |base| return base;
    if (envOrNull(allocator, "TMPDIR")) |base| return base;
    return allocator.dupe(u8, "/data/local/tmp/ftk");
}

fn appleRoot(allocator: std.mem.Allocator) ![]u8 {
    if (envOrNull(allocator, "HOME")) |home| {
        defer allocator.free(home);
        return std.fs.path.join(allocator, &.{ home, "Library", "Application Support", "FuckerToolkit" });
    }
    return allocator.dupe(u8, "/tmp/FuckerToolkit");
}

fn posixRoot(allocator: std.mem.Allocator) ![]u8 {
    if (envOrNull(allocator, "XDG_DATA_HOME")) |base| {
        defer allocator.free(base);
        return std.fs.path.join(allocator, &.{ base, "ftk" });
    }
    if (envOrNull(allocator, "HOME")) |home| {
        defer allocator.free(home);
        return std.fs.path.join(allocator, &.{ home, ".local", "share", "ftk" });
    }
    return allocator.dupe(u8, "/tmp/ftk");
}

test "private root resolves" {
    const root = try privateRoot(std.testing.allocator);
    defer std.testing.allocator.free(root);
    try std.testing.expect(root.len > 0);
}

