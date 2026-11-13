#include <interposer.h>
#include <pthread.h>
#include <stdio.h>
#include <unistd.h>
static pthread_key_t later;
static int mode;
static void traffic(void) { void *p = malloc(4096); __asm__ volatile("" : : "r"(p) : "memory"); free(p); }
static void late(void *p) { (void)p; traffic(); }
static void *reset_worker(void *p) { (void)p; usleep(100000); malloc_interposer_disable(); malloc_interposer_reset(); write(1,"reset after main exit ok\n",25); _exit(0); }
static void *worker(void *p) { (void)p; traffic(); if (mode == 2) { pthread_key_create(&later, late); pthread_setspecific(later, (void *)1); } return NULL; }
int main(int argc, char **argv) {
 mode = argc > 1 ? atoi(argv[1]) : 0;
 if (mode != 5) { malloc_interposer_enable(); traffic(); malloc_interposer_disable(); }
 if (mode == 3 || mode == 4) { if (mode == 4) malloc_interposer_enable(); pthread_t t; pthread_create(&t,NULL,reset_worker,NULL); pthread_exit(NULL); }
 if (mode && mode != 5) { malloc_interposer_enable(); pthread_t t; pthread_create(&t, NULL, worker, NULL); pthread_join(t, NULL); malloc_interposer_disable(); }
 malloc_interposer_reset();
 int64_t a,b,c,d,e,f; malloc_interposer_get_stats(&a,&b,&c,&d,&e,&f);
 printf("mode=%d reset=ok total=%lld\n",mode,a);
 malloc_interposer_enable(); traffic(); malloc_interposer_disable();
 malloc_interposer_get_stats(&a,&b,&c,&d,&e,&f); printf("post-reset malloc=%lld free=%lld bytes=%lld\n",a,e,b); return (a > 0 && e > 0) ? 0 : 2;
}
