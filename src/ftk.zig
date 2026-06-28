const builtin = @import("builtin");

pub const bootstrap = @import("bootstrap.zig");
pub const entry = @import("entry.zig");
pub const hook = @import("hook.zig");
pub const hook_selftest = @import("hook_selftest.zig");
pub const logger = @import("logger.zig");
pub const lua_runtime = @import("lua_runtime.zig");
pub const memory = @import("memory.zig");
pub const pal = @import("pal.zig");
pub const vfs = @import("vfs.zig");

comptime {
    if (!builtin.is_test) {
        _ = entry.ftk_platform_constructor_entry;
    }
}

test {
    _ = pal;
    _ = vfs;
}
