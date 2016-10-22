# anime-ren
ED2K hasher &amp; AniDB client

Pretty simple Anime renamer. Use ed2k.c to hash files then pipe them into anidb.py.

ed2k.c and anidb.py are mutli-threaded, to try and reduce lag between renaming files.

```
./a.out ~/somewhere/someplace/*.mkv | python3 anidb.py
```

Build ed2k.c with -lssl and -lcrypto (from libssl-dev) and -lpthread. e.g. on my mac:

```
clang -I/usr/local/opt/openssl/include -L/usr/local/opt/openssl/lib -lssl -lcrypto -lpthread ed2k.c
```
