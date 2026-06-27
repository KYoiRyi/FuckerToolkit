#include "ftk/pal/memory_manager.hpp"

#include <cstdint>

#if defined(_WIN32)
#include <windows.h>
#else
#include <sys/mman.h>
#include <unistd.h>
#endif

namespace ftk::pal {
namespace {

#if defined(_WIN32)
DWORD to_native(PageProtection protection) {
  switch (protection) {
  case PageProtection::read_only:
    return PAGE_READONLY;
  case PageProtection::read_write:
    return PAGE_READWRITE;
  case PageProtection::read_execute:
    return PAGE_EXECUTE_READ;
  case PageProtection::read_write_execute:
    return PAGE_EXECUTE_READWRITE;
  }
  return PAGE_NOACCESS;
}
#else
int to_native(PageProtection protection) {
  switch (protection) {
  case PageProtection::read_only:
    return PROT_READ;
  case PageProtection::read_write:
    return PROT_READ | PROT_WRITE;
  case PageProtection::read_execute:
    return PROT_READ | PROT_EXEC;
  case PageProtection::read_write_execute:
    return PROT_READ | PROT_WRITE | PROT_EXEC;
  }
  return PROT_NONE;
}
#endif

} // namespace

bool MemoryManager::protect(void* address, std::size_t length, PageProtection protection) {
  if (address == nullptr || length == 0) {
    return false;
  }

#if defined(_WIN32)
  DWORD old_protection = 0;
  return VirtualProtect(address, length, to_native(protection), &old_protection) != 0;
#else
  auto page = page_size();
  auto raw = reinterpret_cast<std::uintptr_t>(address);
  auto aligned = raw & ~(static_cast<std::uintptr_t>(page) - 1U);
  auto delta = raw - aligned;
  return mprotect(reinterpret_cast<void*>(aligned), length + delta, to_native(protection)) == 0;
#endif
}

std::size_t MemoryManager::page_size() {
#if defined(_WIN32)
  SYSTEM_INFO info = {};
  GetSystemInfo(&info);
  return static_cast<std::size_t>(info.dwPageSize);
#else
  auto value = sysconf(_SC_PAGESIZE);
  return value > 0 ? static_cast<std::size_t>(value) : 4096U;
#endif
}

} // namespace ftk::pal

