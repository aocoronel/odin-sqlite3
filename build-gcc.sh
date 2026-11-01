#!/usr/bin/env sh

set -xe

CFLAGS=${CFLAGS:-"-O2 -fPIC"}

mkdir -p sqlite3/bin

gcc $CFLAGS -c amalgamation/sqlite3.c -o sqlite3/bin/sqlite3.o
echo "sqlite3/bin/sqlite3.o compiled!"

ar rcs sqlite3/bin/sqlite3.a sqlite3/bin/sqlite3.o
echo "sqlite3/bin/sqlite3.a compiled!"

ld -shared -o sqlite3/bin/sqlite3.so sqlite3/bin/sqlite3.o
echo "sqlite3/bin/sqlite3.so compiled!"
