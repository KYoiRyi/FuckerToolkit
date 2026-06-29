const std = @import("std");
const builtin = @import("builtin");

const MachHeader = opaque {};

extern fn _dyld_image_count() callconv(.c) u32;
extern fn _dyld_get_image_name(image_index: u32) callconv(.c) ?[*:0]const u8;
extern fn _dyld_get_image_header(image_index: u32) callconv(.c) ?*const MachHeader;

pub const ImageInfo = struct {
    index: u32,
    name: []const u8,
    base: usize,
};

pub fn findByNameContains(needle: []const u8) ?ImageInfo {
    if (builtin.os.tag != .ios and builtin.os.tag != .macos) return null;

    const count = _dyld_image_count();
    var index: u32 = 0;
    while (index < count) : (index += 1) {
        const raw_name = _dyld_get_image_name(index) orelse continue;
        const name = std.mem.span(raw_name);
        if (std.mem.indexOf(u8, name, needle) == null) continue;

        const header = _dyld_get_image_header(index) orelse continue;
        return .{
            .index = index,
            .name = name,
            .base = @intFromPtr(header),
        };
    }
    return null;
}

pub fn resolveRva(needle: []const u8, rva: usize) ?usize {
    const info = findByNameContains(needle) orelse return null;
    return info.base + rva;
}

