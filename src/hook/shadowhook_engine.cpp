#include "ftk/hook/hook_engine.hpp"

#if defined(__ANDROID__)
#include <shadowhook.h>

#include <mutex>
#include <unordered_map>

namespace ftk::hook {
namespace {

class ShadowHookEngine final : public IHookEngine {
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
    auto init = initialize_locked();
    if (!init) {
      return init;
    }

    if (stubs_.find(hook.target) != stubs_.end()) {
      return {HookStatus::already_attached, "target already hooked"};
    }

    void* stub = shadowhook_hook_func_addr_2(
        hook.target,
        hook.detour,
        hook.original,
        SHADOWHOOK_HOOK_WITH_MULTI_MODE);
    if (stub == nullptr) {
      return {HookStatus::backend_error, shadowhook_to_errmsg(shadowhook_get_errno())};
    }

    stubs_.emplace(hook.target, stub);
    return {HookStatus::ok, "hook enabled"};
  }

  HookResult detach(void* target) override {
    if (target == nullptr) {
      return {HookStatus::invalid_target, "target address is null"};
    }

    std::lock_guard<std::mutex> lock(mutex_);
    auto it = stubs_.find(target);
    if (it == stubs_.end()) {
      return {HookStatus::not_attached, "target was not hooked"};
    }

    int rc = shadowhook_unhook(it->second);
    if (rc != 0) {
      return {HookStatus::backend_error, shadowhook_to_errmsg(shadowhook_get_errno())};
    }

    stubs_.erase(it);
    return {HookStatus::ok, "hook removed"};
  }

private:
  HookResult initialize_locked() {
    if (initialized_) {
      return {HookStatus::ok, "ShadowHook initialized"};
    }

    int rc = shadowhook_init(SHADOWHOOK_MODE_SHARED, false);
    if (rc != 0) {
      return {HookStatus::backend_error, shadowhook_to_errmsg(shadowhook_get_errno())};
    }

    initialized_ = true;
    return {HookStatus::ok, "ShadowHook initialized"};
  }

  bool initialized_ = false;
  std::mutex mutex_;
  std::unordered_map<void*, void*> stubs_;
};

} // namespace

IHookEngine& default_engine() {
  static ShadowHookEngine engine;
  return engine;
}

} // namespace ftk::hook
#endif
