#include <malloc/malloc.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#ifdef REPLACEMENT
#include <interposer.h>
#define SIZE replacement_malloc_size
#else
#define SIZE malloc_size
#endif

int main(int argc, char **argv) {
    if (argc != 2) return 64;
    const char *name = argv[1];
    void *mapping = NULL;
    void *pointer = NULL;
    size_t page = (size_t)getpagesize();
    if (strncmp(name, "unreadable-", 11) == 0 || strncmp(name, "mapped-", 7) == 0) {
        mapping = mmap(NULL, 3 * page, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0);
        if (mapping == MAP_FAILED) return 65;
        pointer = (char *)mapping + page + (strstr(name, "offset256") ? 256 : 0);
        if (strncmp(name, "unreadable-", 11) == 0 && mprotect(mapping, 3 * page, PROT_NONE)) return 66;
    } else if (strcmp(name, "null") == 0) {
        pointer = NULL;
    } else if (strcmp(name, "tagged") == 0) {
        pointer = (void *)((uintptr_t)1 << 63);
    } else if (strcmp(name, "small-address") == 0) {
        pointer = (void *)(uintptr_t)1;
    } else if (strncmp(name, "owned", 5) == 0) {
        size_t requested = (size_t)strtoul(name + 5, NULL, 10);
#ifdef REPLACEMENT
        pointer = replacement_malloc(requested);
        if (!pointer || !malloc_interposer_is_ours(pointer)) return 68;
        if (SIZE(pointer) < requested) return 69;
        memset(pointer, 0x5a, requested);
        void *resized = replacement_realloc(pointer, requested + 31);
        if (!resized || SIZE(resized) < requested + 31) return 70;
        for (size_t i = 0; i < requested; i++) {
            if (((unsigned char *)resized)[i] != 0x5a) return 71;
        }
        replacement_free(resized);
#else
        pointer = malloc(requested);
        if (!pointer || SIZE(pointer) < requested) return 68;
        free(pointer);
#endif
        printf("case=%s valid=true\n", name);
        return 0;
    } else if (strcmp(name, "foreign-malloc") == 0 || strcmp(name, "foreign-aligned") == 0) {
        malloc_zone_t *native_zone = malloc_default_zone();
        if (!native_zone) return 72;
        if (strcmp(name, "foreign-aligned") == 0) {
            if (posix_memalign(&pointer, page, 4096)) return 73;
        } else {
            pointer = native_zone->malloc(native_zone, 64);
        }
        if (!pointer || !malloc_zone_from_ptr(pointer)) return 74;
#ifdef REPLACEMENT
        if (malloc_interposer_is_ours(pointer)) return 75;
#endif
        size_t size = SIZE(pointer);
        if (size < (strcmp(name, "foreign-aligned") == 0 ? 4096 : 64)) return 76;
        native_zone->free(native_zone, pointer);
        printf("case=%s size=%zu valid=true\n", name, size);
        return 0;
    } else {
        return 64;
    }
    malloc_zone_t *zone = malloc_zone_from_ptr(pointer);
    size_t size = SIZE(pointer);
    printf("case=%s zone=%p size=%zu\n", name, (void *)zone, size);
    if (mapping) munmap(mapping, 3 * page);
    return zone == NULL && size == 0 ? 0 : 67;
}
