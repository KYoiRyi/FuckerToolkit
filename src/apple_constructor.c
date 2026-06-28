#include <fcntl.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

extern void ftk_platform_constructor_entry(void);

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
        snprintf(dir, sizeof(dir), "%s/Library/Application Support/FuckerToolkit", home);
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

static void *ftk_start_thread(void *arg) {
    (void)arg;
    ftk_early_log("constructor thread started");
    usleep(1500 * 1000);
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
