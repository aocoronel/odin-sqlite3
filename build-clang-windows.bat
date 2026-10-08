setlocal

set CFLAGS=-O2 -fPIC

if not exist bindings\bin mkdir bindings\bin

clang %CFLAGS% -c amalgamation\sqlite3.c -o bindings\bin\sqlite3.o
@echo bindings\bin\sqlite3.o compiled!

llvm-ar rcs bindings\bin\sqlite3.a bindings\bin\sqlite3.o
@echo bindings\bin\sqlite3.a compiled!

ld -shared -o bindings\bin\sqlite3.so bindings\bin\sqlite3.o
@echo bindings\bin\sqlite3.so compiled!

endlocal
