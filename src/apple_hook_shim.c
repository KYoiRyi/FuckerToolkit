#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
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
static char g_symbol_smoke_bytes[64] = "";
static int g_symbol_diagnose_count = 0;
static char g_symbol_diagnose_names[768] = "";

typedef void *(*ftk_il2cpp_domain_get_fn_t)(void);
typedef void **(*ftk_il2cpp_domain_get_assemblies_fn_t)(const void *, size_t *);
typedef void *(*ftk_il2cpp_assembly_get_image_fn_t)(const void *);
typedef size_t (*ftk_il2cpp_image_get_class_count_fn_t)(const void *);
typedef void *(*ftk_il2cpp_image_get_class_fn_t)(const void *, size_t);
typedef const char *(*ftk_il2cpp_class_get_name_fn_t)(const void *);
typedef const char *(*ftk_il2cpp_class_get_namespace_fn_t)(const void *);
typedef void *(*ftk_il2cpp_class_get_methods_fn_t)(void *, void **);
typedef const char *(*ftk_il2cpp_method_get_name_fn_t)(const void *);
typedef void (*ftk_unity_send_message_fn_t)(const char *, const char *, const char *);

static void *ftk_detour_il2cpp_domain_get(void) {
    g_symbol_smoke_called += 1;
    ftk_il2cpp_domain_get_fn_t original = (ftk_il2cpp_domain_get_fn_t)g_symbol_smoke_original;
    if (original == NULL) return NULL;
    return original();
}

static void **ftk_detour_il2cpp_domain_get_assemblies(const void *domain, size_t *size) {
    g_symbol_smoke_called += 1;
    ftk_il2cpp_domain_get_assemblies_fn_t original = (ftk_il2cpp_domain_get_assemblies_fn_t)g_symbol_smoke_original;
    if (original == NULL) return NULL;
    return original(domain, size);
}

static void *ftk_detour_il2cpp_assembly_get_image(const void *assembly) {
    g_symbol_smoke_called += 1;
    ftk_il2cpp_assembly_get_image_fn_t original = (ftk_il2cpp_assembly_get_image_fn_t)g_symbol_smoke_original;
    if (original == NULL) return NULL;
    return original(assembly);
}

static size_t ftk_detour_il2cpp_image_get_class_count(const void *image) {
    g_symbol_smoke_called += 1;
    ftk_il2cpp_image_get_class_count_fn_t original = (ftk_il2cpp_image_get_class_count_fn_t)g_symbol_smoke_original;
    if (original == NULL) return 0;
    return original(image);
}

static void *ftk_detour_il2cpp_image_get_class(const void *image, size_t index) {
    g_symbol_smoke_called += 1;
    ftk_il2cpp_image_get_class_fn_t original = (ftk_il2cpp_image_get_class_fn_t)g_symbol_smoke_original;
    if (original == NULL) return NULL;
    return original(image, index);
}

static const char *ftk_detour_il2cpp_class_get_name(const void *klass) {
    g_symbol_smoke_called += 1;
    ftk_il2cpp_class_get_name_fn_t original = (ftk_il2cpp_class_get_name_fn_t)g_symbol_smoke_original;
    if (original == NULL) return NULL;
    return original(klass);
}

static const char *ftk_detour_il2cpp_class_get_namespace(const void *klass) {
    g_symbol_smoke_called += 1;
    ftk_il2cpp_class_get_namespace_fn_t original = (ftk_il2cpp_class_get_namespace_fn_t)g_symbol_smoke_original;
    if (original == NULL) return NULL;
    return original(klass);
}

static void *ftk_detour_il2cpp_class_get_methods(void *klass, void **iter) {
    g_symbol_smoke_called += 1;
    ftk_il2cpp_class_get_methods_fn_t original = (ftk_il2cpp_class_get_methods_fn_t)g_symbol_smoke_original;
    if (original == NULL) return NULL;
    return original(klass, iter);
}

static const char *ftk_detour_il2cpp_method_get_name(const void *method) {
    g_symbol_smoke_called += 1;
    ftk_il2cpp_method_get_name_fn_t original = (ftk_il2cpp_method_get_name_fn_t)g_symbol_smoke_original;
    if (original == NULL) return NULL;
    return original(method);
}

static void ftk_detour_unity_send_message(const char *object, const char *method, const char *message) {
    g_symbol_smoke_called += 1;
    ftk_unity_send_message_fn_t original = (ftk_unity_send_message_fn_t)g_symbol_smoke_original;
    if (original == NULL) return;
    original(object, method, message);
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

const char *ftk_apple_hook_symbol_smoke_bytes(void) {
    return g_symbol_smoke_bytes;
}

int ftk_apple_image_symbol_diagnose_count(void) {
    return g_symbol_diagnose_count;
}

const char *ftk_apple_image_symbol_diagnose_names(void) {
    return g_symbol_diagnose_names;
}

static void ftk_capture_smoke_bytes(const void *addr) {
    const unsigned char *bytes = (const unsigned char *)addr;
    char *out = g_symbol_smoke_bytes;
    size_t left = sizeof(g_symbol_smoke_bytes);
    g_symbol_smoke_bytes[0] = '\0';

    for (size_t i = 0; i < 16 && left > 1; ++i) {
        int written = snprintf(out, left, i == 0 ? "%02x" : " %02x", bytes[i]);
        if (written <= 0 || (size_t)written >= left) break;
        out += written;
        left -= (size_t)written;
    }
}

static void *ftk_resolve_il2cpp_symbol(const char *symbol) {
    void *addr = DobbySymbolResolver("UnityFramework", symbol);
    if (addr != NULL) return addr;
    addr = DobbySymbolResolver(NULL, symbol);
    if (addr != NULL) return addr;
    return dlsym(RTLD_DEFAULT, symbol);
}

static const struct mach_header_64 *ftk_find_image_header(const char *image_substr, intptr_t *slide_out) {
    if (image_substr == NULL) return NULL;

    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; ++i) {
        const char *name = _dyld_get_image_name(i);
        if (name == NULL || strstr(name, image_substr) == NULL) continue;

        const struct mach_header *header = _dyld_get_image_header(i);
        if (header == NULL || header->magic != MH_MAGIC_64) return NULL;
        if (slide_out != NULL) *slide_out = _dyld_get_image_vmaddr_slide(i);
        return (const struct mach_header_64 *)header;
    }
    return NULL;
}

int ftk_apple_image_symbol_diagnose(const char *image_substr, const char *needle) {
    g_symbol_diagnose_count = 0;
    g_symbol_diagnose_names[0] = '\0';
    if (image_substr == NULL || needle == NULL) return 0;

    intptr_t slide = 0;
    const struct mach_header_64 *header = ftk_find_image_header(image_substr, &slide);
    if (header == NULL) return 0;

    const struct symtab_command *symtab = NULL;
    const struct segment_command_64 *linkedit = NULL;
    const uint8_t *cursor = (const uint8_t *)(header + 1);
    for (uint32_t i = 0; i < header->ncmds; ++i) {
        const struct load_command *cmd = (const struct load_command *)cursor;
        if (cmd->cmd == LC_SYMTAB) {
            symtab = (const struct symtab_command *)cmd;
        } else if (cmd->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *segment = (const struct segment_command_64 *)cmd;
            if (strcmp(segment->segname, SEG_LINKEDIT) == 0) {
                linkedit = segment;
            }
        }
        cursor += cmd->cmdsize;
    }
    if (symtab == NULL || linkedit == NULL) return 0;

    uintptr_t linkedit_base = (uintptr_t)slide + (uintptr_t)linkedit->vmaddr - (uintptr_t)linkedit->fileoff;
    const struct nlist_64 *symbols = (const struct nlist_64 *)(linkedit_base + symtab->symoff);
    const char *strings = (const char *)(linkedit_base + symtab->stroff);

    char *out = g_symbol_diagnose_names;
    size_t left = sizeof(g_symbol_diagnose_names);
    for (uint32_t i = 0; i < symtab->nsyms; ++i) {
        uint32_t strx = symbols[i].n_un.n_strx;
        if (strx == 0) continue;
        const char *name = strings + strx;
        if (strstr(name, needle) == NULL) continue;

        g_symbol_diagnose_count += 1;
        if (left <= 1) continue;
        int written = snprintf(out, left, g_symbol_diagnose_count == 1 ? "%s" : ",%s", name);
        if (written <= 0 || (size_t)written >= left) {
            left = 0;
            continue;
        }
        out += written;
        left -= (size_t)written;
    }

    return g_symbol_diagnose_count;
}

typedef struct {
    const char *name;
    void *detour;
} ftk_il2cpp_candidate_t;

static int ftk_apple_hook_il2cpp_reflection_smoke(void) {
    const ftk_il2cpp_candidate_t candidates[] = {
        { "il2cpp_class_get_name", (void *)ftk_detour_il2cpp_class_get_name },
        { "il2cpp_method_get_name", (void *)ftk_detour_il2cpp_method_get_name },
        { "il2cpp_class_get_namespace", (void *)ftk_detour_il2cpp_class_get_namespace },
        { "il2cpp_class_get_methods", (void *)ftk_detour_il2cpp_class_get_methods },
        { "il2cpp_image_get_class_count", (void *)ftk_detour_il2cpp_image_get_class_count },
        { "il2cpp_image_get_class", (void *)ftk_detour_il2cpp_image_get_class },
        { "il2cpp_assembly_get_image", (void *)ftk_detour_il2cpp_assembly_get_image },
        { "il2cpp_domain_get_assemblies", (void *)ftk_detour_il2cpp_domain_get_assemblies },
        { "il2cpp_domain_get", (void *)ftk_detour_il2cpp_domain_get },
    };

    for (size_t i = 0; i < sizeof(candidates) / sizeof(candidates[0]); ++i) {
        void *addr = ftk_resolve_il2cpp_symbol(candidates[i].name);
        if (addr == NULL) {
            continue;
        }

        g_symbol_smoke_name = candidates[i].name;
        g_symbol_smoke_target = addr;
        g_symbol_smoke_before = 1;
        ftk_capture_smoke_bytes(addr);

        g_last_stage = 700 + (int)i;
        int rc = DobbyHook(addr, candidates[i].detour, &g_symbol_smoke_original);
        g_last_stage = 800 + (int)i;
        g_symbol_smoke_rc = rc;
        if (rc != 0) return FTK_HOOK_BACKEND_ERROR;

        g_symbol_smoke_after = 1;
        return FTK_HOOK_OK;
    }

    return FTK_HOOK_INVALID_TARGET;
}

static int ftk_apple_hook_unity_api_smoke(void) {
    const char *symbol = "UnitySendMessage";
    void *addr = DobbySymbolResolver("UnityFramework", symbol);
    if (addr == NULL) {
        addr = DobbySymbolResolver(NULL, symbol);
    }
    if (addr == NULL) {
        return FTK_HOOK_INVALID_TARGET;
    }

    g_symbol_smoke_name = symbol;
    g_symbol_smoke_target = addr;
    g_symbol_smoke_before = 1;
    ftk_capture_smoke_bytes(addr);

    g_last_stage = 900;
    int rc = DobbyHook(addr, (void *)ftk_detour_unity_send_message, &g_symbol_smoke_original);
    g_last_stage = 901;
    g_symbol_smoke_rc = rc;
    if (rc != 0) return FTK_HOOK_BACKEND_ERROR;

    g_symbol_smoke_after = 1;
    return FTK_HOOK_OK;
}

int ftk_apple_hook_symbol_smoke_test(const char *symbol) {
    if (symbol == NULL) return FTK_HOOK_INVALID_TARGET;

    g_last_stage = 0;
    g_symbol_smoke_rc = 0;
    g_symbol_smoke_before = 0;
    g_symbol_smoke_after = 0;
    g_symbol_smoke_called = 0;
    g_symbol_smoke_original = NULL;
    g_symbol_smoke_target = NULL;
    g_symbol_smoke_name = symbol;
    g_symbol_smoke_bytes[0] = '\0';

    if (strcmp(symbol, "il2cpp_reflection") == 0) {
        return ftk_apple_hook_il2cpp_reflection_smoke();
    }
    if (strcmp(symbol, "unity_api") == 0) {
        return ftk_apple_hook_unity_api_smoke();
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
