#include <stdio.h>
#include <math.h>
#include <string.h>
#include <mach/mach_time.h>
#include <openssl/md4.h>
//#include "lib/threads/threads.h"

// FILE <9728000
#define TEST1 "/Users/rusty/Downloads/test1.dat"
#define TEST1_E "ac44b93fc9aff773ab0005c911f8396f"
// FILE =9728000
#define TEST2 "/Users/rusty/Downloads/test2.dat"
#define TEST2_E "114b21c63a74b6ca922291a11177dd5c"
// FILE >9728000
#define TEST3 "/Users/rusty/Downloads/test3.dat"
#define TEST3_E "a498747b415fbd40b835bfb65391fb45"
// FILE 10kb
#define TEST4 "/Users/rusty/Downloads/test4.dat"
#define TEST4_E "d0695c74d3a32c883075daa72256ab74"
// FILE 17gb
#define TEST5 "/Users/rusty/Downloads/haruhi.mkv"
#define TEST5_E "b630c3c3602bb60994b37de4c34a637f"

#define TEST TEST5

#define CHUNK_SIZE 9728000
#define BUF_SIZE   8000

long get_time() {
  static mach_timebase_info_data_t freq = {0, 0};
  if (freq.denom == 0)
    mach_timebase_info(&freq);
  return (mach_absolute_time() * freq.numer / freq.denom) / 1000;
}

int main (int argc, const char *argv[]) {
  long start_time = get_time();

  FILE* fh = fopen(TEST, "rb");
  if (fh == NULL) {
    printf ("%s can't be opened.\n", TEST);
    return 1;
  }

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

  for (int i = 0; i < MD4_DIGEST_LENGTH; ++i)
    printf("%02x", md[i]);
  printf("\n");

  fclose(fh);
  printf("exec time: %f\n", ((get_time() - start_time) / 1000000.f));
  return 0;
}
