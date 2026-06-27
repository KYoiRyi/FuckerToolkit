#include "ftk/pal/path_resolver.hpp"

#include <cstdlib>

#if defined(_WIN32)
#include <windows.h>
#endif

namespace ftk::pal {
namespace {

std::filesystem::path env_path(const char* name) {
  const char* value = std::getenv(name);
  if (value == nullptr || *value == '\0') {
    return {};
  }
  return std::filesystem::path(value);
}

} // namespace

std::filesystem::path PathResolver::private_root() {
#if defined(_WIN32)
  auto base = env_path("LOCALAPPDATA");
  if (base.empty()) {
    wchar_t buffer[MAX_PATH] = {};
    auto length = GetTempPathW(MAX_PATH, buffer);
    base = length > 0 ? std::filesystem::path(buffer) : std::filesystem::temp_directory_path();
  }
  return base / "FuckerToolkit";
#elif defined(__ANDROID__)
  auto base = env_path("FTK_PRIVATE_ROOT");
  if (base.empty()) {
    base = env_path("TMPDIR");
  }
  if (base.empty()) {
    base = "/data/local/tmp/ftk";
  }
  return base;
#elif defined(__APPLE__)
  auto base = env_path("HOME");
  if (base.empty()) {
    base = std::filesystem::temp_directory_path();
  }
  return base / "Library" / "Application Support" / "FuckerToolkit";
#else
  auto base = env_path("XDG_DATA_HOME");
  if (base.empty()) {
    auto home = env_path("HOME");
    base = home.empty() ? std::filesystem::temp_directory_path() : home / ".local" / "share";
  }
  return base / "ftk";
#endif
}

} // namespace ftk::pal

