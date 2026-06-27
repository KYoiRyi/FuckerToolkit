#pragma once

#include <filesystem>
#include <optional>
#include <string>
#include <vector>

namespace ftk::vfs {

class VirtualFileSystem {
public:
  explicit VirtualFileSystem(std::filesystem::path root);

  const std::filesystem::path& root() const noexcept;
  std::optional<std::filesystem::path> resolve_local_uri(const std::string& uri) const;
  std::optional<std::vector<std::uint8_t>> read_binary(const std::string& uri) const;
  bool write_binary(const std::string& uri, const std::vector<std::uint8_t>& data) const;

private:
  std::filesystem::path root_;
};

} // namespace ftk::vfs

