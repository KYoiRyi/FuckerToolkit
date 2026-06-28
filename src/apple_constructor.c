#include <dlfcn.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

extern void ftk_platform_constructor_entry(void);
static void ftk_auto_start(void);

int ftk_apple_module_dir(char *buffer, unsigned long buffer_len) {
    Dl_info info;
    if (buffer == NULL || buffer_len == 0) {
        return -1;
    }
    if (dladdr((const void *)&ftk_auto_start, &info) == 0 || info.dli_fname == NULL) {
        return -1;
    }

    const char *slash = strrchr(info.dli_fname, '/');
    if (slash == NULL) {
        return -1;
    }

    size_t len = (size_t)(slash - info.dli_fname);
    if (len == 0 || len + 1 > buffer_len) {
        return -1;
    }

    memcpy(buffer, info.dli_fname, len);
    buffer[len] = '\0';
    return (int)len;
}

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
    dir[0] = '\0';

    if (ftk_apple_module_dir(dir, sizeof(dir)) <= 0 && home != NULL && home[0] != '\0') {
        snprintf(dir, sizeof(dir), "%s/Library/Application Support/FuckerToolkit", home);
    } else if (dir[0] == '\0') {
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

static void *ftk_start_thread(void *arg) {
    (void)arg;
    ftk_early_log("constructor thread started");
    const char *delay_env = getenv("FTK_BOOT_DELAY_MS");
    unsigned long delay_ms = 5000;
    if (delay_env != NULL && delay_env[0] != '\0') {
        char *end = NULL;
        unsigned long parsed = strtoul(delay_env, &end, 10);
        if (end != delay_env && parsed <= 60000) {
            delay_ms = parsed;
        }
    }
    usleep((useconds_t)(delay_ms * 1000));
    ftk_early_log("bootstrap begin");
    ftk_platform_constructor_entry();
    ftk_early_log("bootstrap returned");
    return NULL;
}

__attribute__((constructor))
static void ftk_auto_start(void) {
    pthread_t thread;
    int rc = pthread_create(&thread, NULL, ftk_start_thread, NULL);
    if (rc != 0) {
        ftk_early_log("pthread_create failed");
        return;
    }
    pthread_detach(thread);
}
