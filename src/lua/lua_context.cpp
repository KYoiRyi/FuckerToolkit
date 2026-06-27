#include "ftk/lua/lua_context.hpp"

#if defined(FTK_WITH_LUA)
extern "C" {
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
}
#endif

namespace ftk::lua {

LuaContext::LuaContext() = default;

LuaContext::~LuaContext() {
  shutdown();
}

bool LuaContext::initialize() {
#if defined(FTK_WITH_LUA)
  if (state_ != nullptr) {
    return true;
  }

  auto* L = luaL_newstate();
  if (L == nullptr) {
    last_error_ = "failed to allocate Lua state";
    return false;
  }

  luaL_openlibs(L);
  state_ = L;
  return true;
#else
  last_error_ = "built without Lua support; configure with -DFTK_WITH_LUA=ON";
  return false;
#endif
}

bool LuaContext::execute_file(const std::filesystem::path& path) {
#if defined(FTK_WITH_LUA)
  auto* L = static_cast<lua_State*>(state_);
  if (L == nullptr && !initialize()) {
    return false;
  }

  if (luaL_dofile(L, path.u8string().c_str()) != LUA_OK) {
    last_error_ = lua_tostring(L, -1);
    lua_pop(L, 1);
    return false;
  }

  return true;
#else
  (void)path;
  last_error_ = "built without Lua support; configure with -DFTK_WITH_LUA=ON";
  return false;
#endif
}

void LuaContext::shutdown() {
#if defined(FTK_WITH_LUA)
  if (state_ != nullptr) {
    lua_close(static_cast<lua_State*>(state_));
    state_ = nullptr;
  }
#endif
}

void* LuaContext::native_state() const noexcept {
  return state_;
}

const std::string& LuaContext::last_error() const noexcept {
  return last_error_;
}

} // namespace ftk::lua

