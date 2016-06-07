#include <stdio.h>
#include <math.h>
#include <string.h>
#include <mach/mach_time.h>
#include <openssl/md4.h>
#include <pthread.h>

#define TEST_FILE  "/Users/rusty/Downloads/haruhi.mkv"
#define CHUNK_SIZE 9728000
#define BUF_SIZE   8000

const int total_threads = 4;
const int total_tests   = 15;

typedef struct {
  char** files;
  size_t total_files;
  int id;
} thread_arg;

long get_time() {
  static mach_timebase_info_data_t freq = {0, 0};
  if (freq.denom == 0)
    mach_timebase_info(&freq);
  return (mach_absolute_time() * freq.numer / freq.denom) / 1000;
}

void* ed2k(void* arg) {
  thread_arg t = *((thread_arg*)arg);
  for (int i = 0; i < t.total_files; ++i) {
    FILE* fh = fopen(t.files[i], "rb");
    if (fh) {
      fseek(fh, 0L, SEEK_END);
      size_t fh_size = ftell(fh);
      rewind(fh);
      int too_small  = (fh_size < CHUNK_SIZE);

      unsigned char buf[BUF_SIZE];
      unsigned char md [MD4_DIGEST_LENGTH];
      MD4_CTX root;
      MD4_CTX chunk;
      MD4_Init(&root);
      MD4_Init(&chunk);

      size_t cur_len   = 0,
             len       = 0,
             cur_chunk = 0,
             cur_buf   = 0;
      while (fread(buf, sizeof(*buf), BUF_SIZE, fh) > 0) {
        len        = ftell(fh);
        cur_buf    = len - cur_len;
        MD4_Update(&chunk, buf, cur_buf);
        cur_len    = len;
        cur_chunk += BUF_SIZE;

        if (cur_chunk == CHUNK_SIZE && cur_buf == BUF_SIZE) {
          cur_chunk = 0;
          MD4_Final(md, &chunk);
          MD4_Init(&chunk);
          MD4_Update(&root, md, MD4_DIGEST_LENGTH);
        }
      }
      MD4_Final(md, &chunk);

      if (!too_small) {
        MD4_Update(&root, md, MD4_DIGEST_LENGTH);
        MD4_Final(md, &root);
      }

      char* result = malloc(32 * sizeof(char*));
      for(int i = 0; i < MD4_DIGEST_LENGTH; ++i)
        sprintf(&result[i * 2], "%02x", (unsigned int)md[i]);
      printf("%s :: %s\n", t.files[i], result);

      fclose(fh);
    }
  }
  pthread_exit(NULL);
}

int main (int argc, const char *argv[]) {
  long start_time = get_time();

  const char* test_files[total_tests];
  for (int i = 0; i < total_tests; ++i) {
    test_files[i] = malloc(80 * sizeof(char*));
    sprintf(test_files[i], "/Users/rusty/Downloads/test%d.dat", i + 1);
  }

  int per_thread   = floor(total_tests / total_threads);
  int per_thread_r = total_tests % total_threads;

  thread_arg thread_args[total_threads];
  for (int i = 0; i < total_threads; ++i) {
    thread_args[i].id    = i;
    thread_args[i].files = malloc((per_thread + (i < per_thread_r)) * sizeof(char*));
    unsigned int j, k;
  	for (j = (i < per_thread_r ? \
              i * (per_thread+1) : \
              total_tests - (total_threads - i) * per_thread), \
         k = j; \
         k < j + per_thread + (i < per_thread_r); \
         ++k) {
  		thread_args[i].files[k - j] = malloc(strlen(test_files[j]) * sizeof(char*));
      strcpy(thread_args[i].files[k - j], test_files[k]);
  	}
    thread_args[i].total_files = k - j;
  }

  pthread_t threads[total_threads];
  for (int i = 0; i < total_threads; ++i)
    pthread_create(&threads[i], NULL, ed2k, (void*)&thread_args[i]);
  for (int i = 0; i < total_threads; ++i)
    pthread_join(threads[i], NULL);

  printf("exec time: %f\n", ((get_time() - start_time) / 1000000.f));
  return 0;
}
