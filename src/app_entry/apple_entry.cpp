#include "ftk/core/bootstrap.hpp"

#if defined(__APPLE__)
__attribute__((constructor)) static void ftk_apple_constructor() {
  ftk::Bootstrap::start_async();
}
#endif

