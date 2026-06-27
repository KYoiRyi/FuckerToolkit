#include "ftk/core/bootstrap.hpp"
#include "ftk/hook/hook_engine.hpp"
#include "ftk/pal/path_resolver.hpp"
#include "ftk/vfs/vfs.hpp"

#include <iostream>

namespace {

#if defined(_MSC_VER)
#define FTK_NOINLINE __declspec(noinline)
#else
#define FTK_NOINLINE __attribute__((noinline))
#endif

using AddOneFn = int(int);

FTK_NOINLINE int add_one(int value) {
  return value + 1;
}

AddOneFn* original_add_one = nullptr;

FTK_NOINLINE int detour_add_one(int value) {
  return original_add_one(value) + 10;
}

} // namespace

int main() {
  auto root = ftk::pal::PathResolver::private_root();
  ftk::vfs::VirtualFileSystem vfs(root);

  auto resolved = vfs.resolve_local_uri("local://init.lua");
  if (!resolved) {
    std::cerr << "failed to resolve init.lua\n";
    return 1;
  }

  auto before = add_one(1);
  auto attach = ftk::hook::attach<AddOneFn>(&add_one, &detour_add_one, &original_add_one);
  auto after_attach = add_one(1);
  auto detach = ftk::hook::default_engine().detach(reinterpret_cast<void*>(&add_one));
  auto after_detach = add_one(1);

  std::cout << "root=" << vfs.root().string() << "\n";
  std::cout << "before=" << before << "\n";
  std::cout << "attach_status=" << static_cast<int>(attach.status) << ":" << attach.message << "\n";
  std::cout << "after_attach=" << after_attach << "\n";
  std::cout << "detach_status=" << static_cast<int>(detach.status) << ":" << detach.message << "\n";
  std::cout << "after_detach=" << after_detach << "\n";

  ftk::Bootstrap::run_once();
  return before == 2 && attach && after_attach == 12 && detach && after_detach == 2 ? 0 : 1;
}
