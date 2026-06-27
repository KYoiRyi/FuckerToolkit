#include "ftk/hook/hook_engine.hpp"

#if defined(_WIN32)
#include <MinHook.h>

#include <mutex>

namespace ftk::hook {
namespace {

HookResult from_status(MH_STATUS status, const char* action) {
  if (status == MH_OK) {
    return {HookStatus::ok, action};
  }
  if (status == MH_ERROR_ALREADY_CREATED || status == MH_ERROR_ENABLED) {
    return {HookStatus::already_attached, MH_StatusToString(status)};
  }
  if (status == MH_ERROR_NOT_CREATED || status == MH_ERROR_DISABLED) {
    return {HookStatus::not_attached, MH_StatusToString(status)};
  }
  return {HookStatus::backend_error, MH_StatusToString(status)};
}

class MinHookEngine final : public IHookEngine {
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

    auto create = MH_CreateHook(hook.target, hook.detour, hook.original);
    if (create != MH_OK && create != MH_ERROR_ALREADY_CREATED) {
      return from_status(create, "create hook");
    }

    auto enable = MH_EnableHook(hook.target);
    return from_status(enable, "hook enabled");
  }

  HookResult detach(void* target) override {
    if (target == nullptr) {
      return {HookStatus::invalid_target, "target address is null"};
    }

    std::lock_guard<std::mutex> lock(mutex_);
    auto init = initialize_locked();
    if (!init) {
      return init;
    }

    auto disable = MH_DisableHook(target);
    if (disable != MH_OK && disable != MH_ERROR_DISABLED) {
      return from_status(disable, "disable hook");
    }

    auto remove = MH_RemoveHook(target);
    return from_status(remove, "hook removed");
  }

private:
  HookResult initialize_locked() {
    if (initialized_) {
      return {HookStatus::ok, "MinHook initialized"};
    }

    auto status = MH_Initialize();
    if (status == MH_OK || status == MH_ERROR_ALREADY_INITIALIZED) {
      initialized_ = true;
      return {HookStatus::ok, "MinHook initialized"};
    }
    return from_status(status, "initialize MinHook");
  }

  bool initialized_ = false;
  std::mutex mutex_;
};

} // namespace

IHookEngine& default_engine() {
  static MinHookEngine engine;
  return engine;
}

} // namespace ftk::hook
#endif

