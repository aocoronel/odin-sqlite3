package test

import sqlite "../sqlite3"
import "core:fmt"
import "core:log"
import "core:os"
import "core:testing"

@(test)
exec :: proc(t: ^testing.T) {
	db: ^sqlite.SQLite3
	defer sqlite.close(db)

	DB :: "test.db"

	defer os.remove(DB)
	assert(sqlite.open(DB, &db) == .Ok)

	DATABASE :: `CREATE TABLE IF NOT EXISTS user(
    id   INTEGER PRIMARY KEY,
    name TEXT)`

	if rc := sqlite.exec(db, DATABASE); rc != .Ok { assert(false, "failed to create database") }

	ADD_USER :: `INSERT INTO user (name) VALUES (?);`

	// Test all prepare variants
	{
		stmt: ^sqlite.Stmt
		rc: sqlite.Result_Code
		if stmt, rc = sqlite.prepare(db, string(ADD_USER), "bob"); rc != .Ok {
			log.error(sqlite.errmsg(db))
			assert(false, "failed to prepare statement")} else { sqlite.finalize(stmt) }
		if stmt, rc = sqlite.prepare(db, cstring(ADD_USER), "bob");
		   rc != .Ok {log.error(sqlite.errmsg(db))
			assert(false, "failed to prepare statement")} else { sqlite.finalize(stmt) }
		if stmt, rc = sqlite.prepare(db, cstring16(ADD_USER), "bob");
		   rc != .Ok {log.error(sqlite.errmsg(db))
			assert(false, "failed to prepare statement")} else { sqlite.finalize(stmt) }
		if stmt, rc = sqlite.prepare(db, string16(ADD_USER), "bob"); rc != .Ok {
			log.error(sqlite.errmsg(db))
			assert(false, "failed to prepare statement")} else { sqlite.finalize(stmt) }
	}

	// Test exec_ignore_query
	if rc := sqlite.exec(db, string(ADD_USER), "bob");
	   rc != .Ok { assert(false, "failed to add 'bob'") }
	if rc := sqlite.exec(db, cstring16(ADD_USER), "bob");
	   rc != .Ok { assert(false, "failed to add 'bob'") }

	// Test exec_struct
	if _, rc := sqlite.exec_struct(db, string(ADD_USER), struct {}, "bob");
	   rc != .Ok { assert(false, "failed to add 'bob'") }
	if _, rc := sqlite.exec_struct(db, cstring16(ADD_USER), struct {}, "bob");
	   rc != .Ok { assert(false, "failed to add 'bob'") }

	// Test exec_dynamic
	if _, rc := sqlite.exec_dynamic(db, string(ADD_USER), "bob");
	   rc != .Ok { assert(false, "failed to add 'bob'") }
	if _, rc := sqlite.exec_dynamic(db, cstring16(ADD_USER), "bob");
	   rc != .Ok { assert(false, "failed to add 'bob'") }

	SELECT_QUERY :: `SELECT * FROM user;`

	// Test exec_column
	dyn_cols: [dynamic]cstring
	if cols, vals, rc := sqlite.exec_column(db, SELECT_QUERY, &dyn_cols);
	   rc != .Ok { assert(false, "failed to add 'bob'") }
	if cols, vals, rc := sqlite.exec_column(db, cstring16(SELECT_QUERY), &dyn_cols);
	   rc != .Ok { assert(false, "failed to add 'bob'") }

	// Test read_row_into_column_array
	{
		stmt: ^sqlite.Stmt
		rc: sqlite.Result_Code
		{
			stmt, rc = sqlite.prepare(db, SELECT_QUERY)
			assert(rc == .Ok)
		}
		init: bool
		cols := make([dynamic]cstring, context.temp_allocator)
		for {
			rc = sqlite.step(stmt)
			if rc != .Row do break
			cols, vals, rc := sqlite.exec_column(db, stmt, &init, &cols)
		}
		rc = sqlite.finalize(stmt)
		assert(rc == .Ok)
	}

	LARGE_QUERY :: `INSERT INTO user (name) VALUES ('alice');` + SELECT_QUERY

	{
		tail: string
		assert(sqlite.exec(db, string(LARGE_QUERY), tail = &tail) == .Ok)
		assert(tail == SELECT_QUERY)
	}
	{
		tail: cstring
		assert(sqlite.exec(db, cstring(LARGE_QUERY), tail = &tail) == .Ok)
		assert(tail == SELECT_QUERY)
	}
	{
		tail: cstring16
		assert(sqlite.exec(db, cstring16(LARGE_QUERY), tail = &tail) == .Ok)
		assert(tail == SELECT_QUERY)
	}
	{
		tail: string16
		assert(sqlite.exec(db, string16(LARGE_QUERY), tail = &tail) == .Ok)
		assert(tail == SELECT_QUERY)
	}

	// Test exec_all
	once: bool
	assert(sqlite.exec_all(db, LARGE_QUERY) == .Ok)
	assert(sqlite.exec_all(db, LARGE_QUERY, callback, &once) == .Ok)
	assert(sqlite.exec_all(db, LARGE_QUERY, callback_abort, nil) == .Abort)
}

callback :: proc(arg: rawptr, ncol: i32, vals, cols: []cstring) -> bool {
	if !(cast(^bool)arg)^ {
		assert(cols != nil)
		(cast(^bool)arg)^ = true
	}
	assert(vals != nil)
	return true
}

callback_abort :: proc(arg: rawptr, ncol: i32, vals, cols: []cstring) -> bool {
	return false
}
