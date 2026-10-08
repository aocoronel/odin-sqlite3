cl /nologo /c /O2 amalgamation/sqlite3.c -Fo:bindings/bin/sqlite3.obj
@echo bindings/sqlite3.obj compiled!
lib /nologo bindings/bin/sqlite3.obj /out:"bindings/bin/sqlite3.lib"
@echo bindings/sqlite3.lib compiled!
link /nologo /DLL bindings\bin\sqlite3.obj /OUT:bindings\bin\sqlite3.dll
@echo bindings/sqlite3.dll compiled!
