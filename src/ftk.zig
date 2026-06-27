pub const bootstrap = @import("bootstrap.zig");
pub const entry = @import("entry.zig");
pub const hook = @import("hook.zig");
pub const logger = @import("logger.zig");
pub const lua_runtime = @import("lua_runtime.zig");
pub const memory = @import("memory.zig");
pub const pal = @import("pal.zig");
pub const vfs = @import("vfs.zig");

comptime {
    _ = bootstrap.ftk_bootstrap_run_once;
    _ = entry.DllMain;
    _ = entry.JNI_OnLoad;
    _ = entry.ftk_platform_constructor_entry;
    _ = hook.ftk_hook_attach;
    _ = hook.ftk_hook_detach;
    _ = logger.ftk_log_write;
}

test {
    _ = pal;
    _ = vfs;
}
