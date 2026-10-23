#include <unistd.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <limits.h>
#include <errno.h>
#include <stdint.h>
#include <stdatomic.h>

/* Native delay only: an exact target AND its synthetic data root must match.
 * The runner inserts this library only into native-delay fixture children.
 * No production source, global I/O policy, or other process is changed. */
static _Atomic uint64_t delayed_reads = 0;

uint64_t pomo_slow_read_count(void) {
    return atomic_load_explicit(&delayed_reads, memory_order_relaxed);
}

static ssize_t delayed_read(int fd, void *buffer, size_t count) {
    char path[PATH_MAX];
    char root[PATH_MAX];
    const char *target = getenv("POMO_SLOW_READ_PATH");
    const char *configured_root = getenv("POMO_FIXTURE_DATA_ROOT");
    if (target && configured_root && realpath(configured_root, root) &&
        fcntl(fd, F_GETPATH, path) == 0) {
        size_t root_length = strlen(root);
        if (root_length > 1 && strncmp(path, root, root_length) == 0 &&
            path[root_length] == '/' && strcmp(path, target) == 0) {
            atomic_fetch_add_explicit(&delayed_reads, 1, memory_order_relaxed);
            struct timespec remaining = {1, 200000000};
            while (nanosleep(&remaining, &remaining) != 0 && errno == EINTR) {}
        }
    }
    return read(fd, buffer, count);
}

#define DYLD_INTERPOSE(replacement, original) \
__attribute__((used)) static struct { const void *replacement_fn; const void *original_fn; } \
interpose_##original __attribute__((section("__DATA,__interpose"))) = { \
    (const void *)(unsigned long)&replacement, (const void *)(unsigned long)&original };
DYLD_INTERPOSE(delayed_read, read)
