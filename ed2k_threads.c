#include <stdio.h>
#include <math.h>
#include <string.h>
#include <mach/mach_time.h>
#include <openssl/md4.h>
#include "lib/threads/threads.h"

#define TEST "/Users/rusty/Downloads/haruhi.mkv"
#define TEST_E "b630c3c3602bb60994b37de4c34a637f"

#define CHUNK_SIZE 9728000
#define BUF_SIZE   8000
#define THREAD_LOOP for (i = 0; i < total_threads; ++i)

const int total_threads = 4;
mtx_t t_mtx;

typedef struct {
  FILE* fh;
  char* ret;
  size_t size, fh_size;
  long start, end;
  int id;
} thread_arg;

long get_time() {
  static mach_timebase_info_data_t freq = {0, 0};
  if (freq.denom == 0)
    mach_timebase_info(&freq);
  return (mach_absolute_time() * freq.numer / freq.denom) / 1000;
}

void test_thrd(void* arg) {
  thread_arg t_arg  = *((thread_arg*)arg);
  MD4_CTX chunk;
  MD4_Init(&chunk);

  for (long i = t_arg.start; i < t_arg.end; i += CHUNK_SIZE) {
    for (int j = 0; j < CHUNK_SIZE; j += BUF_SIZE) {
      mtx_lock(&t_mtx);
      fseek(t_arg.fh, i + j, SEEK_SET);
      //printf("%d :: %lu\n", t_arg.id, ftell(t_arg.fh));
      mtx_unlock(&t_mtx);
    }
  }
}

int main (int argc, const char *argv[]) {
  long start_time = get_time();
  int  i          = 0;

  FILE* fh = fopen(TEST, "rb");
  if (fh == NULL) {
    printf ("%s can't be opened.\n", TEST);
    return 1;
  }

  fseek(fh, 0L, SEEK_END);
  size_t fh_size   = ftell(fh);
  rewind(fh);
  int too_small    = (fh_size < CHUNK_SIZE);
  int total_chunks = ceil(fh_size / (float)CHUNK_SIZE);
  int per_thread   = floor(total_chunks / (float)total_threads);
  int per_thread_r = total_chunks - (per_thread * total_threads);
  printf("%d %d %d %lu\n", total_chunks, per_thread, per_thread_r, fh_size);

  mtx_init(&t_mtx, NULL);
  thread_arg t_args[total_threads];
  long last_end = -1;
  THREAD_LOOP {
    t_args[i].id    = i;
    t_args[i].fh    = fh;
    t_args[i].size  = per_thread;

    if (i == 0)
      t_args[i].fh_size = fh_size;
    if (i >= (total_threads - per_thread_r))
      t_args[i].size += 1;

    t_args[i].start = last_end + 1;
    t_args[i].end   = (i + 1 == total_threads ? \
                      fh_size : \
                      t_args[i].start + (CHUNK_SIZE * t_args[i].size));
    last_end = t_args[i].end;
  }

  void (*test_func)(void*) = test_thrd;
  thrd_t* t = malloc(total_threads * sizeof(thrd_t*));
  THREAD_LOOP
    thrd_create(&t[i], test_func, (void*)&t_args[i]);
  THREAD_LOOP
    thrd_join(t[i], NULL);

  fclose(fh);
  printf("exec time: %f\n", ((get_time() - start_time) / 1000000.f));
  return 0;
}
