#include <stddef.h>
#include <tinyhook.h>

enum {
    FTK_HOOK_OK = 0,
    FTK_HOOK_INVALID_TARGET = 1,
    FTK_HOOK_INVALID_DETOUR = 2,
    FTK_HOOK_INVALID_ORIGINAL = 3,
    FTK_HOOK_ALREADY_ATTACHED = 4,
    FTK_HOOK_NOT_ATTACHED = 5,
    FTK_HOOK_BACKEND_ERROR = 6,
};

typedef struct {
    void *target;
    th_bak_t backup;
} ftk_apple_hook_entry_t;

static ftk_apple_hook_entry_t g_hooks[128];
static size_t g_hook_count = 0;
static int g_last_attach_rc = 0;
static int g_last_detach_rc = 0;
static int g_last_probe_rc = 0;
static int g_last_stage = 0;

int ftk_apple_hook_last_attach_rc(void) {
    return g_last_attach_rc;
}

int ftk_apple_hook_last_detach_rc(void) {
    return g_last_detach_rc;
}

int ftk_apple_hook_last_probe_rc(void) {
    return g_last_probe_rc;
}

int ftk_apple_hook_last_stage(void) {
    return g_last_stage;
}

int ftk_apple_hook_probe_no_trampoline(void *target, void *detour) {
    if (target == NULL) return FTK_HOOK_INVALID_TARGET;
    if (detour == NULL) return FTK_HOOK_INVALID_DETOUR;

    g_last_stage = 100;
    int rc = tiny_hook(target, detour, NULL);
    g_last_stage = 101;
    g_last_probe_rc = rc;
    return rc == 0 ? FTK_HOOK_OK : FTK_HOOK_BACKEND_ERROR;
}

int ftk_apple_hook_attach(void *target, void *detour, void **original) {
    if (target == NULL) return FTK_HOOK_INVALID_TARGET;
    if (detour == NULL) return FTK_HOOK_INVALID_DETOUR;
    if (original == NULL) return FTK_HOOK_INVALID_ORIGINAL;

    for (size_t i = 0; i < g_hook_count; ++i) {
        if (g_hooks[i].target == target) {
            return FTK_HOOK_ALREADY_ATTACHED;
        }
    }
    if (g_hook_count >= sizeof(g_hooks) / sizeof(g_hooks[0])) {
        return FTK_HOOK_BACKEND_ERROR;
    }

    th_bak_t backup = {0};
    backup.address = target;
    backup.jump_size = 0;
    g_last_stage = 200;
    int rc = tiny_hook(target, detour, original);
    g_last_stage = 201;
    g_last_attach_rc = rc;
    if (rc != 0) {
        return FTK_HOOK_BACKEND_ERROR;
    }

    g_hooks[g_hook_count].target = target;
    g_hooks[g_hook_count].backup = backup;
    g_hook_count += 1;
    return FTK_HOOK_OK;
}

int ftk_apple_hook_detach(void *target) {
    if (target == NULL) return FTK_HOOK_INVALID_TARGET;

    for (size_t i = 0; i < g_hook_count; ++i) {
        if (g_hooks[i].target != target) {
            continue;
        }

        int rc = tiny_unhook_ex(&g_hooks[i].backup);
        g_last_detach_rc = rc;
        if (rc != 0) {
            return FTK_HOOK_BACKEND_ERROR;
        }

        g_hook_count -= 1;
        g_hooks[i] = g_hooks[g_hook_count];
        return FTK_HOOK_OK;
    }

    return FTK_HOOK_NOT_ATTACHED;
}
