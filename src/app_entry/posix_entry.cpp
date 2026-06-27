#include "ftk/core/bootstrap.hpp"

#if !defined(_WIN32) && !defined(__APPLE__) && !defined(__ANDROID__)
__attribute__((constructor)) static void ftk_posix_constructor() {
  ftk::Bootstrap::start_async();
}
#endif

