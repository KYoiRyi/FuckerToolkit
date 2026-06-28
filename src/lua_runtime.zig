const std = @import("std");
const logger = @import("logger.zig");
const hook_selftest = @import("hook_selftest.zig");

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
extern fn lua_gettop(L: *LuaState) callconv(.c) c_int;
extern fn lua_settop(L: *LuaState, index: c_int) callconv(.c) void;
extern fn lua_pushcclosure(L: *LuaState, function: LuaCFunction, n: c_int) callconv(.c) void;
extern fn lua_pushlstring(L: *LuaState, s: [*]const u8, len: usize) callconv(.c) void;
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
        lua_createtable(self.state, 0, 2);
        lua_createtable(self.state, 0, 3);

        lua_pushcclosure(self.state, luaLogInfo, 0);
        lua_setfield(self.state, -2, "info");
        lua_pushcclosure(self.state, luaLogWarn, 0);
        lua_setfield(self.state, -2, "warn");
        lua_pushcclosure(self.state, luaLogError, 0);
        lua_setfield(self.state, -2, "error");

        lua_setfield(self.state, -2, "Log");

        lua_createtable(self.state, 0, 1);
        lua_pushcclosure(self.state, luaHookSelfTest, 0);
        lua_setfield(self.state, -2, "SelfTest");
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
