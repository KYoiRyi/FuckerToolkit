#pragma once

namespace ftk::lua {

class LuaContext;

class ApiBridge {
public:
  static void register_toolkit(LuaContext& context);
};

} // namespace ftk::lua

