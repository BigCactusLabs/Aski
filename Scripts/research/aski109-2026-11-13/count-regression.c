#include <interposer.h>
#include <inttypes.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

typedef struct {
    int allocations;
    int passes;
    int callbacks;
} context_t;

static pthread_key_t later_key;

static void traffic(int count) {
    for (int i = 0; i < count; ++i) {
        void *p = malloc(4096);
        if (!p) _exit(80);
        __asm__ volatile("" : : "r"(p) : "memory");
        free(p);
    }
}

static void later_destructor(void *argument) {
    context_t *context = argument;
    traffic(context->allocations);
    context->callbacks++;
    if (context->callbacks < context->passes &&
        pthread_setspecific(later_key, context) != 0) _exit(81);
}

static void *worker(void *argument) {
    context_t *context = argument;
    if (pthread_setspecific(later_key, context) != 0) _exit(82);
    malloc_interposer_enable();
    traffic(1);
    malloc_interposer_disable();
    malloc_interposer_reset();
    usleep(10000);
    malloc_interposer_enable();
    traffic(7);
    return NULL;
}

static void print_stats(context_t context) {
    int64_t count, bytes, small, large, frees, freed_bytes;
    malloc_interposer_get_stats(&count, &bytes, &small, &large, &frees, &freed_bytes);
    printf("{\"malloc\":%" PRId64 ",\"free\":%" PRId64
           ",\"bytes\":%" PRId64 ",\"freed_bytes\":%" PRId64
           ",\"callbacks\":%d}\n", count, frees, bytes, freed_bytes, context.callbacks);
}

int main(int argc, char **argv) {
    if (argc != 3) return 64;
    int passes = atoi(argv[1]);
    int allocations = atoi(argv[2]);
    if (passes < 0 || passes > 4 || allocations < 1 || allocations > 100) return 64;
    malloc_interposer_enable();
    traffic(1);
    malloc_interposer_disable();
    malloc_interposer_reset();
    context_t context = {allocations, passes, 0};
    if (passes == 0) {
        malloc_interposer_enable();
        traffic(allocations);
        malloc_interposer_disable();
    } else {
        if (pthread_key_create(&later_key, later_destructor) != 0) return 65;
        pthread_t thread;
        if (pthread_create(&thread, NULL, worker, &context) != 0) return 66;
        if (pthread_join(thread, NULL) != 0) return 67;
        malloc_interposer_disable();
        if (pthread_key_delete(later_key) != 0) return 68;
    }
    print_stats(context);
    malloc_interposer_reset();
    int64_t count, bytes, small, large, frees, freed_bytes;
    malloc_interposer_get_stats(&count, &bytes, &small, &large, &frees, &freed_bytes);
    if (count || bytes || small || large || frees || freed_bytes) return 69;
    return context.callbacks == passes ? 0 : 70;
}
