const std = @import("std");

const local_prefix = "local://";

pub const VirtualFileSystem = struct {
    allocator: std.mem.Allocator,
    root: []u8,

    pub fn init(allocator: std.mem.Allocator, root_path: []const u8) !VirtualFileSystem {
        const root = try std.fs.path.resolve(allocator, &.{root_path});
        std.fs.makeDirAbsolute(root) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
        return .{ .allocator = allocator, .root = root };
    }

    pub fn deinit(self: *VirtualFileSystem) void {
        self.allocator.free(self.root);
    }

    pub fn resolveLocalUri(self: *const VirtualFileSystem, uri: []const u8) ![]u8 {
        if (!std.mem.startsWith(u8, uri, local_prefix)) return error.InvalidScheme;

        const relative = uri[local_prefix.len..];
        if (relative.len == 0 or std.fs.path.isAbsolute(relative)) return error.InvalidPath;
        if (containsTraversal(relative)) return error.PathTraversal;

        return std.fs.path.resolve(self.allocator, &.{ self.root, relative });
    }

    pub fn readBinary(self: *const VirtualFileSystem, uri: []const u8) ![]u8 {
        const path = try self.resolveLocalUri(uri);
        defer self.allocator.free(path);

        const file = try std.fs.openFileAbsolute(path, .{ .mode = .read_only });
        defer file.close();
        return file.readToEndAlloc(self.allocator, std.math.maxInt(usize));
    }

    pub fn writeBinary(self: *const VirtualFileSystem, uri: []const u8, data: []const u8) !void {
        const path = try self.resolveLocalUri(uri);
        defer self.allocator.free(path);

        if (std.fs.path.dirname(path)) |dir| {
            try std.fs.makeDirAbsolute(dir);
        }

        const file = try std.fs.createFileAbsolute(path, .{ .truncate = true });
        defer file.close();
        try file.writeAll(data);
    }
};

fn containsTraversal(path: []const u8) bool {
    var iterator = std.mem.tokenizeAny(u8, path, "/\\");
    while (iterator.next()) |part| {
        if (std.mem.eql(u8, part, "..")) return true;
    }
    return false;
}

test "local uri traversal is rejected" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);

    var fs = try VirtualFileSystem.init(std.testing.allocator, root);
    defer fs.deinit();

    try std.testing.expectError(error.PathTraversal, fs.resolveLocalUri("local://../escape.lua"));
}

