#include "ftk/lua/api_bridge.hpp"

#include "ftk/lua/lua_context.hpp"

#if defined(FTK_WITH_LUA)
extern "C" {
#include <lua.h>
#include <lauxlib.h>
}
#endif

namespace ftk::lua {

void ApiBridge::register_toolkit(LuaContext& context) {
#if defined(FTK_WITH_LUA)
  auto* L = static_cast<lua_State*>(context.native_state());
  if (L == nullptr) {
    return;
  }

  lua_newtable(L);

  lua_newtable(L);
  lua_setfield(L, -2, "Memory");

  lua_newtable(L);
  lua_setfield(L, -2, "Hook");

  lua_newtable(L);
  lua_setfield(L, -2, "Dumper");

  lua_setglobal(L, "Toolkit");
#else
  (void)context;
#endif
}

} // namespace ftk::lua

