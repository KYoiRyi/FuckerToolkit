#pragma once

#include <cstdint>
#include <string>

namespace ftk::hook {

struct RegisterContext {
#if defined(_M_X64) || defined(__x86_64__)
  std::uint64_t rax = 0;
  std::uint64_t rbx = 0;
  std::uint64_t rcx = 0;
  std::uint64_t rdx = 0;
  std::uint64_t rsi = 0;
  std::uint64_t rdi = 0;
  std::uint64_t rbp = 0;
  std::uint64_t rsp = 0;
  std::uint64_t r8 = 0;
  std::uint64_t r9 = 0;
  std::uint64_t r10 = 0;
  std::uint64_t r11 = 0;
  std::uint64_t r12 = 0;
  std::uint64_t r13 = 0;
  std::uint64_t r14 = 0;
  std::uint64_t r15 = 0;
#elif defined(__aarch64__) || defined(_M_ARM64)
  std::uint64_t x[31] = {};
  std::uint64_t sp = 0;
  std::uint64_t pc = 0;
  std::uint64_t pstate = 0;
#else
  std::uintptr_t platform_words[32] = {};
#endif
};

enum class HookStatus {
  ok,
  invalid_target,
  invalid_detour,
  invalid_original,
  already_attached,
  not_attached,
  backend_error,
};

struct HookResult {
  HookStatus status = HookStatus::backend_error;
  std::string message;

  explicit operator bool() const noexcept { return status == HookStatus::ok; }
};

struct NativeHook {
  void* target = nullptr;
  void* detour = nullptr;
  void** original = nullptr;
};

class IHookEngine {
public:
  virtual ~IHookEngine() = default;
  virtual HookResult attach(const NativeHook& hook) = 0;
  virtual HookResult detach(void* target) = 0;
};

IHookEngine& default_engine();

template <typename Function>
HookResult attach(Function* target, Function* detour, Function** original) {
  return default_engine().attach({
      reinterpret_cast<void*>(target),
      reinterpret_cast<void*>(detour),
      reinterpret_cast<void**>(original),
  });
}

} // namespace ftk::hook
