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

const int total_threads = 4;
mtx_t t_mtx;

typedef struct {
  FILE* fh;
  size_t size, fh_size;
  long start, end;
  int id;
  mtx_t* mtx;
} thread_arg;

long get_time() {
  static mach_timebase_info_data_t freq = {0, 0};
  if (freq.denom == 0)
    mach_timebase_info(&freq);
  return (mach_absolute_time() * freq.numer / freq.denom) / 1000;
}

void test_thrd(void* arg) {
  thread_arg t_arg  = *((thread_arg*)arg);
  long start_off_at = (CHUNK_SIZE * t_arg.size) * \
                      (total_threads - (t_arg.id + 1));
  long read_to      = (t_arg.id ? (CHUNK_SIZE * t_arg.size) * \
                                  (total_threads - t_arg.id) : \
                                   t_arg.fh_size);
  printf("%ld %ld %d %zu\n", start_off_at, read_to, t_arg.id, t_arg.size);

  MD4_CTX chunk;
  MD4_Init(&chunk);

  // for (long i = start_off_at; i < read_to; i += CHUNK_SIZE) {
  //   for (int j = 0; j < CHUNK_SIZE; j += BUF_SIZE) {
  //     mtx_lock(&t_mtx);
  //     fseek(t_arg.fh, i + j, SEEK_SET);
  //     printf("%d :: %lu -- %ld:%d -- %ld:%ld\n", t_arg.id, ftell(t_arg.fh), i, j, read_to, CHUNK_SIZE);
  //     mtx_unlock(&t_mtx);
  //   }
  // }
}

int main (int argc, const char *argv[]) {
  long start_time = get_time();

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

  unsigned char md [MD4_DIGEST_LENGTH];
  MD4_CTX root;
  MD4_Init(&root);

  mtx_init(&t_mtx, NULL);
  thread_arg t_args[total_threads];
  for (int i = 0; i < total_threads; ++i) {
    t_args[i].id   = i;
    t_args[i].fh   = fh;
    t_args[i].size = per_thread;
    if (i == 0)
      t_args[i].fh_size = fh_size;
    if (per_thread_r > 0) {
      t_args[i].size += 1;
      per_thread_r   -= 1;
    }
  }

  void (*test_func)(void*) = test_thrd;
  thrd_t* t = malloc(total_threads * sizeof(thrd_t*));
  for (int i = 0; i < total_threads; ++i)
    thrd_create(&t[i], test_func, (void*)&t_args[i]);
  for (int i = 0; i < total_threads; ++i)
    thrd_join(t[i], NULL);

  fclose(fh);
  printf("exec time: %f\n", ((get_time() - start_time) / 1000000.f));
  return 0;
}
