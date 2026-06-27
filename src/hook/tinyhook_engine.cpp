#include "ftk/hook/hook_engine.hpp"

#if defined(__APPLE__)
#include <tinyhook.h>

#include <mutex>
#include <unordered_map>

namespace ftk::hook {
namespace {

class TinyHookEngine final : public IHookEngine {
public:
  HookResult attach(const NativeHook& hook) override {
    if (hook.target == nullptr) {
      return {HookStatus::invalid_target, "target address is null"};
    }
    if (hook.detour == nullptr) {
      return {HookStatus::invalid_detour, "detour address is null"};
    }
    if (hook.original == nullptr) {
      return {HookStatus::invalid_original, "original storage is null"};
    }

    std::lock_guard<std::mutex> lock(mutex_);
    if (backups_.find(hook.target) != backups_.end()) {
      return {HookStatus::already_attached, "target already hooked"};
    }

    th_bak_t backup = {};
    int rc = tiny_hook_ex(&backup, hook.target, hook.detour, hook.original);
    if (rc != 0) {
      return {HookStatus::backend_error, "tiny_hook_ex failed"};
    }

    backups_.emplace(hook.target, backup);
    return {HookStatus::ok, "hook enabled"};
  }

  HookResult detach(void* target) override {
    if (target == nullptr) {
      return {HookStatus::invalid_target, "target address is null"};
    }

    std::lock_guard<std::mutex> lock(mutex_);
    auto it = backups_.find(target);
    if (it == backups_.end()) {
      return {HookStatus::not_attached, "target was not hooked"};
    }

    int rc = tiny_unhook_ex(&it->second);
    if (rc != 0) {
      return {HookStatus::backend_error, "tiny_unhook_ex failed"};
    }

    backups_.erase(it);
    return {HookStatus::ok, "hook removed"};
  }

private:
  std::mutex mutex_;
  std::unordered_map<void*, th_bak_t> backups_;
};

} // namespace

IHookEngine& default_engine() {
  static TinyHookEngine engine;
  return engine;
}

} // namespace ftk::hook
#endif

