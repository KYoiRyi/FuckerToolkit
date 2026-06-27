#include "ftk/vfs/vfs.hpp"

#include <fstream>

namespace ftk::vfs {
namespace {

constexpr const char* kLocalPrefix = "local://";

bool is_under_root(const std::filesystem::path& root, const std::filesystem::path& candidate) {
  auto normalized_root = std::filesystem::weakly_canonical(root);
  auto normalized_candidate = std::filesystem::weakly_canonical(candidate);
  auto root_it = normalized_root.begin();
  auto candidate_it = normalized_candidate.begin();

  for (; root_it != normalized_root.end(); ++root_it, ++candidate_it) {
    if (candidate_it == normalized_candidate.end() || *root_it != *candidate_it) {
      return false;
    }
  }
  return true;
}

} // namespace

VirtualFileSystem::VirtualFileSystem(std::filesystem::path root)
    : root_(std::filesystem::absolute(std::move(root))) {
  std::filesystem::create_directories(root_);
}

const std::filesystem::path& VirtualFileSystem::root() const noexcept {
  return root_;
}

std::optional<std::filesystem::path> VirtualFileSystem::resolve_local_uri(const std::string& uri) const {
  if (uri.rfind(kLocalPrefix, 0) != 0) {
    return std::nullopt;
  }

  auto relative = std::filesystem::path(uri.substr(std::char_traits<char>::length(kLocalPrefix)));
  if (relative.empty() || relative.is_absolute()) {
    return std::nullopt;
  }

  auto candidate = root_ / relative;
  if (!is_under_root(root_, candidate)) {
    return std::nullopt;
  }
  return candidate;
}

std::optional<std::vector<std::uint8_t>> VirtualFileSystem::read_binary(const std::string& uri) const {
  auto path = resolve_local_uri(uri);
  if (!path) {
    return std::nullopt;
  }

  std::ifstream input(*path, std::ios::binary);
  if (!input) {
    return std::nullopt;
  }

  return std::vector<std::uint8_t>(
      std::istreambuf_iterator<char>(input),
      std::istreambuf_iterator<char>());
}

bool VirtualFileSystem::write_binary(const std::string& uri, const std::vector<std::uint8_t>& data) const {
  auto path = resolve_local_uri(uri);
  if (!path) {
    return false;
  }

  std::filesystem::create_directories(path->parent_path());
  std::ofstream output(*path, std::ios::binary | std::ios::trunc);
  if (!output) {
    return false;
  }

  output.write(reinterpret_cast<const char*>(data.data()), static_cast<std::streamsize>(data.size()));
  return output.good();
}

} // namespace ftk::vfs

