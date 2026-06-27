#pragma once

#include <cstddef>

namespace ftk::pal {

enum class PageProtection {
  read_only,
  read_write,
  read_execute,
  read_write_execute,
};

class MemoryManager {
public:
  static bool protect(void* address, std::size_t length, PageProtection protection);
  static std::size_t page_size();
};

} // namespace ftk::pal

