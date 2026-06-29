const std = @import("std");
const image = @import("image.zig");
const logger = @import("logger.zig");
const hook_selftest = @import("hook_selftest.zig");
const hook = @import("hook.zig");
const builtin = @import("builtin");

const LUA_OK: c_int = 0;
const LUA_MULTRET: c_int = -1;

const LuaState = opaque {};
const LuaCFunction = *const fn (?*LuaState) callconv(.c) c_int;

extern fn luaL_newstate() callconv(.c) ?*LuaState;
extern fn luaL_openlibs(L: *LuaState) callconv(.c) void;
extern fn lua_close(L: *LuaState) callconv(.c) void;
extern fn luaL_loadfilex(L: *LuaState, filename: [*:0]const u8, mode: ?[*:0]const u8) callconv(.c) c_int;
extern fn lua_pcallk(L: *LuaState, nargs: c_int, nresults: c_int, msgh: c_int, ctx: isize, k: ?*anyopaque) callconv(.c) c_int;
extern fn lua_tolstring(L: *LuaState, index: c_int, len: ?*usize) callconv(.c) ?[*]const u8;
extern fn luaL_checklstring(L: *LuaState, index: c_int, len: ?*usize) callconv(.c) [*]const u8;
extern fn luaL_checkinteger(L: *LuaState, index: c_int) callconv(.c) isize;
extern fn lua_gettop(L: *LuaState) callconv(.c) c_int;
extern fn lua_settop(L: *LuaState, index: c_int) callconv(.c) void;
extern fn lua_pushcclosure(L: *LuaState, function: LuaCFunction, n: c_int) callconv(.c) void;
extern fn lua_pushlstring(L: *LuaState, s: [*]const u8, len: usize) callconv(.c) void;
extern fn lua_pushinteger(L: *LuaState, n: isize) callconv(.c) void;
extern fn lua_pushnil(L: *LuaState) callconv(.c) void;
extern fn lua_pushboolean(L: *LuaState, b: c_int) callconv(.c) void;
extern fn lua_pushvalue(L: *LuaState, index: c_int) callconv(.c) void;
extern fn lua_createtable(L: *LuaState, narr: c_int, nrec: c_int) callconv(.c) void;
extern fn lua_setfield(L: *LuaState, index: c_int, key: [*:0]const u8) callconv(.c) void;
extern fn lua_setglobal(L: *LuaState, name: [*:0]const u8) callconv(.c) void;

pub const Context = struct {
    allocator: std.mem.Allocator,
    root: []const u8,
    state: *LuaState,

    pub fn init(allocator: std.mem.Allocator, root: []const u8) !Context {
        const state = luaL_newstate() orelse return error.LuaAllocationFailed;
        luaL_openlibs(state);

        var context = Context{
            .allocator = allocator,
            .root = root,
            .state = state,
        };
        context.registerToolkit();
        return context;
    }

    pub fn deinit(self: *Context) void {
        lua_close(self.state);
    }

    pub fn executeFile(self: *Context, path: []const u8) !void {
        const c_path = try self.allocator.dupeZ(u8, path);
        defer self.allocator.free(c_path);

        if (luaL_loadfilex(self.state, c_path.ptr, null) != LUA_OK) {
            try self.logLuaError("load");
            return error.LuaLoadFailed;
        }
        if (lua_pcallk(self.state, 0, LUA_MULTRET, 0, 0, null) != LUA_OK) {
            try self.logLuaError("runtime");
            return error.LuaRuntimeFailed;
        }
    }

    fn registerToolkit(self: *Context) void {
        lua_createtable(self.state, 0, 4);
        lua_createtable(self.state, 0, 3);

        lua_pushcclosure(self.state, luaLogInfo, 0);
        lua_setfield(self.state, -2, "info");
        lua_pushcclosure(self.state, luaLogWarn, 0);
        lua_setfield(self.state, -2, "warn");
        lua_pushcclosure(self.state, luaLogError, 0);
        lua_setfield(self.state, -2, "error");

        lua_setfield(self.state, -2, "Log");

        lua_createtable(self.state, 0, 1);
        lua_pushcclosure(self.state, luaMemoryReadBytes, 0);
        lua_setfield(self.state, -2, "ReadBytes");
        lua_setfield(self.state, -2, "Memory");

        lua_createtable(self.state, 0, 3);
        lua_pushcclosure(self.state, luaImageBase, 0);
        lua_setfield(self.state, -2, "Base");
        lua_pushcclosure(self.state, luaImageAddress, 0);
        lua_setfield(self.state, -2, "Address");
        lua_pushcclosure(self.state, luaImageDiagnoseRva, 0);
        lua_setfield(self.state, -2, "DiagnoseRva");
        lua_setfield(self.state, -2, "Image");

        lua_createtable(self.state, 0, 2);
        lua_pushcclosure(self.state, luaHookSelfTest, 0);
        lua_setfield(self.state, -2, "SelfTest");
        lua_pushcclosure(self.state, luaHookAutoSmokeTest, 0);
        lua_setfield(self.state, -2, "AutoSmokeTest");
        lua_setfield(self.state, -2, "Hook");

        lua_setglobal(self.state, "Toolkit");

        lua_pushcclosure(self.state, luaPrint, 0);
        lua_setglobal(self.state, "print");
    }

    fn logLuaError(self: *Context, phase: []const u8) !void {
        var len: usize = 0;
        const raw = lua_tolstring(self.state, -1, &len) orelse return;
        const message = raw[0..len];
        const composed = try std.fmt.allocPrint(self.allocator, "lua {s} error: {s}", .{ phase, message });
        defer self.allocator.free(composed);
        var log = logger.Logger{ .allocator = self.allocator, .root = self.root };
        try log.write(.err, composed);
        lua_settop(self.state, -2);
    }
};

fn writeLuaMessage(L: ?*LuaState, level: logger.Level, arg_start: c_int) c_int {
    const state = L orelse return 0;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const top = lua_gettop(state);
    var parts = std.ArrayList([]const u8).init(allocator);
    defer parts.deinit();

    var index = arg_start;
    while (index <= top) : (index += 1) {
        var len: usize = 0;
        const raw = luaL_checklstring(state, index, &len);
        parts.append(raw[0..len]) catch return 0;
    }

    const message = std.mem.join(allocator, "\t", parts.items) catch return 0;
    defer allocator.free(message);
    logger.writeDefault(allocator, level, message) catch return 0;
    return 0;
}

fn luaLogInfo(L: ?*LuaState) callconv(.c) c_int {
    return writeLuaMessage(L, .info, 1);
}

fn luaLogWarn(L: ?*LuaState) callconv(.c) c_int {
    return writeLuaMessage(L, .warn, 1);
}

fn luaLogError(L: ?*LuaState) callconv(.c) c_int {
    return writeLuaMessage(L, .err, 1);
}

fn luaPrint(L: ?*LuaState) callconv(.c) c_int {
    return writeLuaMessage(L, .info, 1);
}

fn readLuaString(state: *LuaState, index: c_int) []const u8 {
    var len: usize = 0;
    const raw = luaL_checklstring(state, index, &len);
    return raw[0..len];
}

fn checkedAddress(value: isize) ?usize {
    if (value <= 0) return null;
    return @intCast(value);
}

fn luaMemoryReadBytes(L: ?*LuaState) callconv(.c) c_int {
    const state = L orelse return 0;
    const address = checkedAddress(luaL_checkinteger(state, 1)) orelse {
        lua_pushnil(state);
        return 1;
    };
    const requested = luaL_checkinteger(state, 2);
    if (requested <= 0 or requested > 64) {
        lua_pushnil(state);
        return 1;
    }

    const len: usize = @intCast(requested);
    const bytes: [*]const u8 = @ptrFromInt(address);

    var buffer: [64 * 3]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    for (bytes[0..len], 0..) |byte, index| {
        if (index != 0) stream.writer().writeByte(' ') catch return 0;
        stream.writer().print("{x:0>2}", .{byte}) catch return 0;
    }
    const out = stream.getWritten();
    lua_pushlstring(state, out.ptr, out.len);
    return 1;
}

fn luaImageBase(L: ?*LuaState) callconv(.c) c_int {
    const state = L orelse return 0;
    const name = readLuaString(state, 1);
    const info = image.findByNameContains(name) orelse {
        lua_pushnil(state);
        return 1;
    };
    lua_pushinteger(state, @intCast(info.base));
    return 1;
}

fn luaImageAddress(L: ?*LuaState) callconv(.c) c_int {
    const state = L orelse return 0;
    const name = readLuaString(state, 1);
    const rva_value = luaL_checkinteger(state, 2);
    if (rva_value < 0) {
        lua_pushnil(state);
        return 1;
    }
    const address = image.resolveRva(name, @intCast(rva_value)) orelse {
        lua_pushnil(state);
        return 1;
    };
    lua_pushinteger(state, @intCast(address));
    return 1;
}

fn luaImageDiagnoseRva(L: ?*LuaState) callconv(.c) c_int {
    const state = L orelse return 0;
    const name = readLuaString(state, 1);
    const rva_value = luaL_checkinteger(state, 2);
    const requested = if (lua_gettop(state) >= 3) luaL_checkinteger(state, 3) else 16;
    if (rva_value < 0 or requested <= 0 or requested > 64) {
        lua_pushboolean(state, 0);
        return 1;
    }

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const info = image.findByNameContains(name) orelse {
        logger.writeDefault(allocator, .err, "image diagnose: image not found") catch {};
        lua_pushboolean(state, 0);
        return 1;
    };
    const address = info.base + @as(usize, @intCast(rva_value));
    const len: usize = @intCast(requested);
    const bytes: [*]const u8 = @ptrFromInt(address);

    var byte_buf: [64 * 3]u8 = undefined;
    var stream = std.io.fixedBufferStream(&byte_buf);
    for (bytes[0..len], 0..) |byte, index| {
        if (index != 0) stream.writer().writeByte(' ') catch return 0;
        stream.writer().print("{x:0>2}", .{byte}) catch return 0;
    }
    const byte_text = stream.getWritten();

    const message = std.fmt.allocPrint(
        allocator,
        "image diagnose: image={s} index={d} base=0x{x} rva=0x{x} address=0x{x} bytes={s}",
        .{ info.name, info.index, info.base, @as(usize, @intCast(rva_value)), address, byte_text },
    ) catch {
        lua_pushboolean(state, 0);
        return 1;
    };
    defer allocator.free(message);
    logger.writeDefault(allocator, .info, message) catch {};

    lua_pushboolean(state, 1);
    lua_pushinteger(state, @intCast(address));
    lua_pushlstring(state, byte_text.ptr, byte_text.len);
    return 3;
}

fn luaHookSelfTest(L: ?*LuaState) callconv(.c) c_int {
    _ = L;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const pal = @import("pal.zig");
    const root = pal.privateRoot(allocator) catch return 0;
    defer allocator.free(root);

    hook_selftest.run(allocator, root) catch |err| {
        const message = std.fmt.allocPrint(allocator, "hook selftest: failed with {s}", .{@errorName(err)}) catch return 0;
        defer allocator.free(message);
        var log = logger.Logger{ .allocator = allocator, .root = root };
        log.write(.err, message) catch {};
        return 0;
    };
    return 0;
}

extern fn ftk_apple_hook_symbol_smoke_test(symbol: [*:0]const u8) callconv(.c) c_int;
extern fn ftk_apple_hook_symbol_smoke_rc() callconv(.c) c_int;
extern fn ftk_apple_hook_symbol_smoke_before() callconv(.c) c_int;
extern fn ftk_apple_hook_symbol_smoke_after() callconv(.c) c_int;
extern fn ftk_apple_hook_symbol_smoke_called() callconv(.c) c_int;
extern fn ftk_apple_hook_symbol_smoke_target() callconv(.c) ?*anyopaque;
extern fn ftk_apple_hook_symbol_smoke_original() callconv(.c) ?*anyopaque;
extern fn ftk_apple_hook_symbol_smoke_name() callconv(.c) ?[*:0]const u8;
extern fn ftk_apple_hook_symbol_smoke_bytes() callconv(.c) ?[*:0]const u8;
extern fn ftk_apple_hook_last_stage() callconv(.c) c_int;

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

fn statusFromInt(value: c_int) hook.Status {
    return switch (value) {
        0 => .ok,
        1 => .invalid_target,
        2 => .invalid_detour,
        3 => .invalid_original,
        4 => .already_attached,
        5 => .not_attached,
        else => .backend_error,
    };
}

fn logImageIfPresent(allocator: std.mem.Allocator, name: []const u8) void {
    const info = image.findByNameContains(name) orelse {
        const missing = std.fmt.allocPrint(allocator, "auto smoke: image not found: {s}", .{name}) catch return;
        defer allocator.free(missing);
        logger.writeDefault(allocator, .warn, missing) catch {};
        return;
    };
    const message = std.fmt.allocPrint(
        allocator,
        "auto smoke: image found name={s} index={d} base=0x{x}",
        .{ info.name, info.index, info.base },
    ) catch return;
    defer allocator.free(message);
    logger.writeDefault(allocator, .info, message) catch {};
}

fn luaHookAutoSmokeTest(L: ?*LuaState) callconv(.c) c_int {
    const state = L orelse return 0;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    logger.writeDefault(allocator, .info, "auto smoke: begin") catch {};
    logImageIfPresent(allocator, "UnityFramework");
    logImageIfPresent(allocator, "libil2cpp");

    if (builtin.os.tag != .ios and builtin.os.tag != .macos) {
        logger.writeDefault(allocator, .warn, "auto smoke: currently implemented for Apple targets") catch {};
        lua_pushboolean(state, 0);
        return 1;
    }

    logger.writeDefault(allocator, .info, "auto smoke: trying DobbyHook target=il2cpp reflection API") catch {};
    const status = statusFromInt(ftk_apple_hook_symbol_smoke_test("il2cpp_reflection"));
    const target = ftk_apple_hook_symbol_smoke_target();
    const original = ftk_apple_hook_symbol_smoke_original();
    const name_ptr = ftk_apple_hook_symbol_smoke_name();
    const name = if (name_ptr) |ptr| std.mem.span(ptr) else "unknown";
    const bytes_ptr = ftk_apple_hook_symbol_smoke_bytes();
    const bytes = if (bytes_ptr) |ptr| std.mem.span(ptr) else "";
    const message = std.fmt.allocPrint(
        allocator,
        "auto smoke: target=il2cpp symbol={s} status={s} rc={d} stage={d} address=0x{x} original=0x{x} before={d} after={d} called={d} bytes={s}",
        .{
            name,
            statusName(status),
            ftk_apple_hook_symbol_smoke_rc(),
            ftk_apple_hook_last_stage(),
            if (target) |ptr| @intFromPtr(ptr) else 0,
            if (original) |ptr| @intFromPtr(ptr) else 0,
            ftk_apple_hook_symbol_smoke_before(),
            ftk_apple_hook_symbol_smoke_after(),
            ftk_apple_hook_symbol_smoke_called(),
            bytes,
        },
    ) catch {
        lua_pushboolean(state, 0);
        return 1;
    };
    defer allocator.free(message);
    logger.writeDefault(allocator, if (status == .ok) .info else .err, message) catch {};
    logger.writeDefault(allocator, .info, "auto smoke: end") catch {};

    lua_pushboolean(state, if (status == .ok) 1 else 0);
    return 1;
}
