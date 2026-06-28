#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

extern void ftk_platform_constructor_entry(void);

static pthread_mutex_t ftk_start_lock = PTHREAD_MUTEX_INITIALIZER;
static int ftk_started = 0;

static void ftk_mkdir_p(const char *path) {
    char tmp[1024];
    size_t len = strnlen(path, sizeof(tmp) - 1);
    if (len == 0 || len >= sizeof(tmp)) {
        return;
    }

    memcpy(tmp, path, len);
    tmp[len] = '\0';

    for (char *p = tmp + 1; *p != '\0'; ++p) {
        if (*p != '/') {
            continue;
        }
        *p = '\0';
        (void)mkdir(tmp, 0700);
        *p = '/';
    }
    (void)mkdir(tmp, 0700);
}

static void ftk_early_log(const char *message) {
    const char *home = getenv("HOME");
    char dir[1024];
    char path[1200];

    if (home != NULL && home[0] != '\0') {
        snprintf(dir, sizeof(dir), "%s/Documents/FuckerToolkit", home);
    } else {
        snprintf(dir, sizeof(dir), "/tmp/FuckerToolkit");
    }

    ftk_mkdir_p(dir);
    snprintf(path, sizeof(path), "%s/toolkit.log", dir);

    int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (fd < 0) {
        fd = open("/tmp/ftk-toolkit.log", O_WRONLY | O_CREAT | O_APPEND, 0600);
    }
    if (fd < 0) {
        return;
    }

    (void)write(fd, "[early] ", 8);
    (void)write(fd, message, strlen(message));
    (void)write(fd, "\n", 1);
    (void)close(fd);
}

static int ftk_is_target_image(const char *path) {
    const char *override = getenv("FTK_BOOT_IMAGE");
    if (override != NULL && override[0] != '\0') {
        return strstr(path, override) != NULL;
    }
    return strstr(path, "UnityFramework") != NULL ||
           strstr(path, "libil2cpp") != NULL ||
           strstr(path, "il2cpp") != NULL;
}

static void *ftk_start_thread(void *arg) {
    (void)arg;

    const char *delay_env = getenv("FTK_BOOT_DELAY_MS");
    unsigned long delay_ms = 1000;
    if (delay_env != NULL && delay_env[0] != '\0') {
        char *end = NULL;
        unsigned long parsed = strtoul(delay_env, &end, 10);
        if (end != delay_env && parsed <= 60000) {
            delay_ms = parsed;
        }
    }

    printf("[ftk] bootstrap scheduled, delay=%lums\n", delay_ms);
    ftk_early_log("bootstrap scheduled");
    usleep((useconds_t)(delay_ms * 1000));
    printf("[ftk] bootstrap begin\n");
    ftk_early_log("bootstrap begin");
    ftk_platform_constructor_entry();
    printf("[ftk] bootstrap returned\n");
    ftk_early_log("bootstrap returned");
    return NULL;
}

static void ftk_schedule_bootstrap(void) {
    pthread_mutex_lock(&ftk_start_lock);
    if (ftk_started != 0) {
        pthread_mutex_unlock(&ftk_start_lock);
        return;
    }
    ftk_started = 1;
    pthread_mutex_unlock(&ftk_start_lock);

    pthread_t thread;
    int rc = pthread_create(&thread, NULL, ftk_start_thread, NULL);
    if (rc != 0) {
        printf("[ftk] pthread_create failed: %d\n", rc);
        ftk_early_log("pthread_create failed");
        return;
    }
    pthread_detach(thread);
}

static void ftk_on_image_added(const struct mach_header *mh, intptr_t slide) {
    (void)slide;

    Dl_info info;
    if (dladdr(mh, &info) == 0 || info.dli_fname == NULL) {
        return;
    }

    if (!ftk_is_target_image(info.dli_fname)) {
        return;
    }

    printf("[ftk] target image loaded: %s\n", info.dli_fname);
    ftk_early_log("target image loaded");
    ftk_schedule_bootstrap();
}

__attribute__((constructor))
static void ftk_auto_start(void) {
    printf("[ftk] loaded, registering dyld image callback\n");
    ftk_early_log("loaded, registering dyld image callback");
    _dyld_register_func_for_add_image(ftk_on_image_added);
}
