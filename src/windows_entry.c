#define WIN32_LEAN_AND_MEAN
#include <windows.h>

extern int ftk_bootstrap_run_once(void);

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID reserved) {
    (void)instance;
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) {
        (void)ftk_bootstrap_run_once();
    }
    return TRUE;
}
