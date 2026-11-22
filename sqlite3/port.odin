/*
Ported functions from C to Odin
*/
package sqlite3

import "core:fmt"
import "core:mem"
import "core:strings"
import "core:unicode"

/*
Returns a message containing the location where the syntax error happened.

Odin port from the shell_error_context() in shell.c
*/
shell_error_context :: proc(db: ^SQLite3, sql: string) -> string {
	offset: i32 = error_offset(db)
	length: uint
	msg: string
	sql := sql

	if db == nil || sql == "" || offset < 0 || offset >= cast(i32)len(sql) {
		return ""
	}

	for offset > 50 {
		offset -= 1
		sql = sql[1:]
		for (sql[0] & 0xc0) == 0x80 {
			sql = sql[1:]
			offset -= 1
		}
	}

	length = len(sql)
	if length > 78 {
		length = 78
		for length > 0 && (sql[length] & 0xc0) == 0x80 {
			length -= 1
		}
	}

	code := make([]byte, len(sql), allocator = context.temp_allocator)
	mem.copy(raw_data(code), raw_data(sql), len(sql))
	for c, i in code {
		if unicode.is_space(rune(sql[i])) {
			code[i] = ' '
		}
	}

	if offset < 25 {
		padding := strings.repeat(" ", cast(int)offset)
		msg = fmt.tprintf("  %s\n  %s^--- error here\n", string(code), padding)
	} else {
		padding := strings.repeat(" ", cast(int)offset - 14)
		msg = fmt.tprintf("  %s\n  %serror here ---^\n", string(code), padding)
	}

	return msg
}
