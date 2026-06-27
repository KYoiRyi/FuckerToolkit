#include "ftk/core/bootstrap.hpp"

#include "ftk/lua/api_bridge.hpp"
#include "ftk/lua/lua_context.hpp"
#include "ftk/pal/path_resolver.hpp"
#include "ftk/vfs/vfs.hpp"

#include <filesystem>
#include <thread>

namespace ftk {
namespace {

void bootstrap_main(BootstrapOptions options) {
  auto root = pal::PathResolver::private_root();
  vfs::VirtualFileSystem vfs(root);
  auto init_path = vfs.resolve_local_uri("local://init.lua");
  if (!init_path || !std::filesystem::exists(*init_path)) {
    return;
  }

  lua::LuaContext lua;
  if (!lua.initialize()) {
    return;
  }

  lua::ApiBridge::register_toolkit(lua);
  lua.execute_file(*init_path);

  if (!options.keep_lua_alive) {
    lua.shutdown();
  }
}

} // namespace

void Bootstrap::start_async(BootstrapOptions options) {
  std::thread([options] { bootstrap_main(options); }).detach();
}

void Bootstrap::run_once(BootstrapOptions options) {
  bootstrap_main(options);
}

} // namespace ftk

