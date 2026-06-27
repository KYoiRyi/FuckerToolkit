#pragma once

#include <filesystem>

namespace ftk::pal {

class PathResolver {
public:
  static std::filesystem::path private_root();
};

} // namespace ftk::pal

