#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>
#include <dobby.h>

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
} ftk_apple_hook_entry_t;

static ftk_apple_hook_entry_t g_hooks[128];
static size_t g_hook_count = 0;
static int g_last_attach_rc = 0;
static int g_last_detach_rc = 0;
static int g_last_probe_rc = 0;
static int g_last_stage = 0;
static int g_symbol_smoke_rc = 0;
static int g_symbol_smoke_before = 0;
static int g_symbol_smoke_after = 0;
static int g_symbol_smoke_called = 0;
static void *g_symbol_smoke_target = NULL;
static void *g_symbol_smoke_original = NULL;
static const char *g_symbol_smoke_name = "";

typedef void *(*ftk_il2cpp_domain_get_fn_t)(void);

static void *ftk_detour_il2cpp_domain_get(void) {
    g_symbol_smoke_called += 1;
    ftk_il2cpp_domain_get_fn_t original = (ftk_il2cpp_domain_get_fn_t)g_symbol_smoke_original;
    if (original == NULL) return NULL;
    return original();
}

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

int ftk_apple_hook_symbol_smoke_rc(void) {
    return g_symbol_smoke_rc;
}

int ftk_apple_hook_symbol_smoke_before(void) {
    return g_symbol_smoke_before;
}

int ftk_apple_hook_symbol_smoke_after(void) {
    return g_symbol_smoke_after;
}

int ftk_apple_hook_symbol_smoke_called(void) {
    return g_symbol_smoke_called;
}

void *ftk_apple_hook_symbol_smoke_target(void) {
    return g_symbol_smoke_target;
}

void *ftk_apple_hook_symbol_smoke_original(void) {
    return g_symbol_smoke_original;
}

const char *ftk_apple_hook_symbol_smoke_name(void) {
    return g_symbol_smoke_name;
}

static void *ftk_resolve_il2cpp_symbol(const char *symbol) {
    void *addr = DobbySymbolResolver("UnityFramework", symbol);
    if (addr != NULL) return addr;
    addr = DobbySymbolResolver(NULL, symbol);
    if (addr != NULL) return addr;
    return dlsym(RTLD_DEFAULT, symbol);
}

static int ftk_apple_hook_il2cpp_reflection_smoke(void) {
    const char *symbol = "il2cpp_domain_get";
    void *addr = ftk_resolve_il2cpp_symbol(symbol);
    if (addr == NULL) {
        const char *candidates[] = {
            "il2cpp_domain_get_assemblies",
            "il2cpp_assembly_get_image",
            "il2cpp_image_get_class_count",
            "il2cpp_image_get_class",
            "il2cpp_class_get_name",
            "il2cpp_class_get_namespace",
            "il2cpp_class_get_methods",
            "il2cpp_method_get_name",
        };
        for (size_t i = 0; i < sizeof(candidates) / sizeof(candidates[0]); ++i) {
            addr = ftk_resolve_il2cpp_symbol(candidates[i]);
            if (addr != NULL) {
                g_symbol_smoke_name = candidates[i];
                g_symbol_smoke_target = addr;
                g_symbol_smoke_before = 1;
                g_symbol_smoke_after = 0;
                return FTK_HOOK_NOT_ATTACHED;
            }
        }
        return FTK_HOOK_INVALID_TARGET;
    }

    g_symbol_smoke_name = symbol;
    g_symbol_smoke_target = addr;
    ftk_il2cpp_domain_get_fn_t target = (ftk_il2cpp_domain_get_fn_t)addr;
    void *before = target();
    g_symbol_smoke_before = before != NULL ? 1 : 0;

    g_last_stage = 600;
    int rc = DobbyHook(addr, (void *)ftk_detour_il2cpp_domain_get, &g_symbol_smoke_original);
    g_last_stage = 601;
    g_symbol_smoke_rc = rc;
    if (rc != 0) return FTK_HOOK_BACKEND_ERROR;

    void *after = target();
    g_symbol_smoke_after = after != NULL ? 1 : 0;
    if (g_symbol_smoke_called <= 0) return FTK_HOOK_BACKEND_ERROR;
    return FTK_HOOK_OK;
}

int ftk_apple_hook_symbol_smoke_test(const char *symbol) {
    if (symbol == NULL) return FTK_HOOK_INVALID_TARGET;

    g_symbol_smoke_rc = 0;
    g_symbol_smoke_before = 0;
    g_symbol_smoke_after = 0;
    g_symbol_smoke_called = 0;
    g_symbol_smoke_original = NULL;
    g_symbol_smoke_target = NULL;
    g_symbol_smoke_name = symbol;

    if (strcmp(symbol, "il2cpp_reflection") == 0) {
        return ftk_apple_hook_il2cpp_reflection_smoke();
    }

    return FTK_HOOK_INVALID_TARGET;
}

int ftk_apple_hook_probe_no_trampoline(void *target, void *detour) {
    if (target == NULL) return FTK_HOOK_INVALID_TARGET;
    if (detour == NULL) return FTK_HOOK_INVALID_DETOUR;

    g_last_stage = 100;
    void *unused_original = NULL;
    int rc = DobbyHook(target, detour, &unused_original);
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

    g_last_stage = 200;
    int rc = DobbyHook(target, detour, original);
    g_last_stage = 201;
    g_last_attach_rc = rc;
    if (rc != 0) {
        return FTK_HOOK_BACKEND_ERROR;
    }

    g_hooks[g_hook_count].target = target;
    g_hook_count += 1;
    return FTK_HOOK_OK;
}

int ftk_apple_hook_detach(void *target) {
    if (target == NULL) return FTK_HOOK_INVALID_TARGET;

    for (size_t i = 0; i < g_hook_count; ++i) {
        if (g_hooks[i].target != target) {
            continue;
        }

        int rc = DobbyDestroy(target);
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
