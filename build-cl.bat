cl /nologo /c /O2 amalgamation/sqlite3.c -Fo:sqlite3/bin/sqlite3.obj
@echo sqlite3/sqlite3.obj compiled!
lib /nologo sqlite3/bin/sqlite3.obj /out:"sqlite3/bin/sqlite3.lib"
@echo sqlite3/sqlite3.lib compiled!
link /nologo /DLL sqlite3\bin\sqlite3.obj /OUT:sqlite3\bin\sqlite3.dll
@echo sqlite3/sqlite3.dll compiled!
