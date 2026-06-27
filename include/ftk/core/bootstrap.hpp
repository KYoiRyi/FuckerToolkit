#pragma once

namespace ftk {

struct BootstrapOptions {
  bool keep_lua_alive = false;
};

class Bootstrap {
public:
  static void start_async(BootstrapOptions options = {});
  static void run_once(BootstrapOptions options = {});
};

} // namespace ftk

