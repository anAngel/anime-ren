# anime-ren
ED2K hasher &amp; AniDB client

Pretty simple Anime renamer. Use ed2k.c to hash files then pipe them into anidb.py.

```
./a.out "~/Downloads/test.mkv" "~/whatever/whatever.mkv" | python anidb.py
```

Build ed2k.c with -lssl and -lcrypto from libssl-dev.

```
clang -I/usr/local/opt/openssl/include -L/usr/local/opt/openssl/lib -lssl -lcrypto ed2k.c
```
