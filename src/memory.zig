const builtin = @import("builtin");

pub const PageProtection = enum(c_int) {
    read_only = 0,
    read_write = 1,
    read_execute = 2,
    read_write_execute = 3,
};

pub export fn ftk_memory_protect(address: ?*anyopaque, length: usize, protection: PageProtection) callconv(.c) c_int {
    if (address == null or length == 0) return -1;

    return switch (builtin.os.tag) {
        .windows => windowsProtect(address.?, length, protection),
        else => posixProtect(address.?, length, protection),
    };
}

const DWORD = u32;
extern "kernel32" fn VirtualProtect(address: *anyopaque, size: usize, new_protect: DWORD, old_protect: *DWORD) callconv(.winapi) c_int;

fn windowsProtect(address: *anyopaque, length: usize, protection: PageProtection) c_int {
    const native: DWORD = switch (protection) {
        .read_only => 0x02,
        .read_write => 0x04,
        .read_execute => 0x20,
        .read_write_execute => 0x40,
    };

    var old: DWORD = 0;
    return if (VirtualProtect(address, length, native, &old) == 0) -1 else 0;
}

extern fn mprotect(address: *anyopaque, length: usize, protection: c_int) callconv(.c) c_int;

fn posixProtect(address: *anyopaque, length: usize, protection: PageProtection) c_int {
    const native: c_int = switch (protection) {
        .read_only => 0x1,
        .read_write => 0x1 | 0x2,
        .read_execute => 0x1 | 0x4,
        .read_write_execute => 0x1 | 0x2 | 0x4,
    };
    return mprotect(address, length, native);
}

