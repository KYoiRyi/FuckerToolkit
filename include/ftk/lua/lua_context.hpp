#pragma once

#include <filesystem>
#include <string>

namespace ftk::lua {

class LuaContext {
public:
  LuaContext();
  ~LuaContext();

  LuaContext(const LuaContext&) = delete;
  LuaContext& operator=(const LuaContext&) = delete;

  bool initialize();
  bool execute_file(const std::filesystem::path& path);
  void shutdown();

  void* native_state() const noexcept;
  const std::string& last_error() const noexcept;

private:
  void* state_ = nullptr;
  std::string last_error_;
};

} // namespace ftk::lua

