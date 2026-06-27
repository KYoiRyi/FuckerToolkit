#include "ftk/core/bootstrap.hpp"

#if defined(_WIN32)
#include <windows.h>

BOOL APIENTRY DllMain(HMODULE, DWORD reason, LPVOID) {
  if (reason == DLL_PROCESS_ATTACH) {
    ftk::Bootstrap::start_async();
  }
  return TRUE;
}
#endif

