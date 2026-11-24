/*
Better sqlite3_exec()
*/
package sqlite3

import "base:intrinsics"
import rt "base:runtime"
import "core:log"
import "core:mem"
import "core:strings"

/*
Base SQLite for the examples:

CREATE TABLE tags (
  id  INTEGER PRIMARY KEY,
  tag TEXT    UNIQUE
);
*/

SQLite_Types :: union {
	i64,
	f64,
	cstring,
	[]u8,
}

/*
All wrappers return .Ok as success, where .Ok == nil.
*/

/*
Only executes one statement.

Example:

	rows, rc := exec_struct(db,
		struct { id: i64, tag: string },
		"INSERT INTO tags (tag) VALUES (?) RETURNING *", "mytag"
	)
	defer delete(rows)
	if rc != .Ok { log.error(errmsg(db)) }
*/
exec_struct :: proc {
	read_row_into_struct,
	exec_struct_query,
}

/*
For this procedure, it's recommended that the allocator is an arena.

Significantly simpler than exec_struct().

Only executes one statement.

Example:

	rows, _, rc := exec_dynamic(
		db, "INSERT INTO tags (tag) VALUES (?) RETURNING *",
		"mytag"
	)
	defer {
		for row in rows {
			delete(row)
		}
		delete(rows)
	}
	if rc != .Ok { log.error(errmsg(db)) }
*/
exec_dynamic :: proc {
	read_row_into_dynamic_array,
	exec_dynamic_query,
}

/*
For this procedure, it's recommended that the allocator is an arena.

Only executes one statement.

Example:

	dyn_cols: [dynamic]cstring
	cols, vals, rc := exec_dynamic(
		db, &dyn_cols, "INSERT INTO tags (tag) VALUES (?) RETURNING *",
		"mytag",
	)
	defer {
		for col in dyn_cols {
			/* 'vals' shares the same array as 'cols' */
			delete(col)
		}
		delete(cols)
	}
	if rc != .Ok { log.error(errmsg(db)) }
*/
exec_column :: proc {
	read_row_into_column_array,
	exec_column_query,
}

/*
Does nothing with rows.

Only executes one statement.

Example:

	rc := exec(db, "INSERT INTO tags (tag) VALUES (?)", "mytag")
	if rc != .Ok { log.error(errmsg(db)) }
*/
exec :: proc {
	exec_ignore,
	exec_ignore_query,
}

exec_all :: proc {
	exec_all_callback,
	exec_all_no_callback,
}

/*
Checks if the tail received from prepare() is valid, and can
be used to prepare another statement.
*/
is_sql_valid :: #force_inline proc "contextless" (
	sql: $T,
) -> bool where T == string16 ||
	T == cstring16 ||
	T == string ||
	T == cstring {
	when T == string || T == string16 {
		if len(sql) > 0 do return true
	} else when T == cstring {
		if sql != nil && (cast([^]u8)sql)[0] != 0 {
			return true
		}
	} else when T == cstring16 {
		if sql != nil && (cast([^]u16)sql)[0] != 0 {
			return true
		}
	}
	return false
}

exec_dynamic_query :: proc(
	db: ^SQLite3,
	sql: $T,
	args: ..any,
	tail: ^T = nil,
	allocator := context.temp_allocator,
	loc := #caller_location,
) -> (
	rows: [dynamic][]SQLite_Types,
	rc: Result_Code,
) where T == string ||
	T == string16 ||
	T == cstring ||
	T == cstring16 {
	stmt: ^Stmt
	stmt, rc = prepare(db, sql, ..args, tail = tail, loc = loc)
	if rc == .Ok {
		for {
			if step(stmt) != .Row do break
			append(&rows, read_row_into_dynamic_array(stmt, allocator, loc))
		}
	}
	rc = finalize(stmt)
	return
}

exec_column_query :: proc(
	db: ^SQLite3,
	cols: ^[dynamic]cstring,
	sql: $T,
	args: ..any,
	tail: ^T = nil,
	allocator := context.temp_allocator,
	loc := #caller_location,
) -> (
	columns, rows: []cstring,
	rc: Result_Code,
) where T == string ||
	T == string16 ||
	T == cstring ||
	T == cstring16 {
	assert(cols != nil)
	context.allocator = allocator

	stmt: ^Stmt
	stmt, rc = prepare(db, sql, ..args, tail = tail, loc = loc)
	if rc == .Ok {
		init := true
		ncols: i32
		for {
			rc = step(stmt)
			if rc != .Row do break
			if init {
				init = false
				ncols = column_count(stmt)
				resize(cols, int(ncols * 2))
				for i: i32 = 0; i < ncols; i += 1 {
					cols[i] = clone(column_name(stmt, i))
					assert(cols[i] != nil)
				}
			}
			vals := (cast([^]cstring)(&cols[ncols]))[:ncols]
			for i: i32 = 0; i < ncols; i += 1 {
				vals[i] = clone(column_text(stmt, i))
				if (vals[i] == nil && column_type(stmt, i) != .Null) {
					finalize(stmt)
					set_errmsg(db, .No_Mem, "out of memory")
					rc = .No_Mem
					return
				}
			}
			columns = cols[:ncols]
			rows = vals
		}
	}

	rc = finalize(stmt)

	return
}

exec_struct_query :: proc(
	db: ^SQLite3,
	$S: typeid,
	sql: $T,
	args: ..any,
	tail: ^T = nil,
	allocator := context.temp_allocator,
	loc := #caller_location,
) -> (
	rows: [dynamic]S,
	rc: Result_Code,
) where T == string ||
	T == string16 ||
	T == cstring ||
	T == cstring16 {
	rows.allocator = allocator

	stmt: ^Stmt
	stmt, rc = prepare(db, sql, ..args, tail = tail, loc = loc)
	if rc == .Ok {
		for {
			if step(stmt) != .Row do break
			row, ok := read_row_into_struct(db, stmt, S, allocator, loc = loc)
			if !ok do return nil, .Error
			append(&rows, row)
		}
	}

	rc = finalize(stmt)
	return
}

exec_ignore :: #force_inline proc(stmt: ^Stmt) -> (rc: Result_Code) {
	for {
		rc = step(stmt)
		if rc != .Row do return
	}
}

exec_ignore_query :: proc(
	db: ^SQLite3,
	sql: $T,
	args: ..any,
	tail: ^T = nil,
	loc := #caller_location,
) -> (
	rc: Result_Code,
) where T == string ||
	T == string16 ||
	T == cstring ||
	T == cstring16 {
	stmt: ^Stmt
	stmt, rc = prepare(db, sql, ..args, tail = tail, loc = loc)
	if rc == .Ok {
		for {
			if step(stmt) != .Row do break
		}
	}
	rc = finalize(stmt)
	return
}

/*
Does nothing with rows.

Executes all statements.
*/
exec_all_no_callback :: proc(
	db: ^SQLite3,
	sql: $T,
) -> (
	rc: Result_Code,
) where T == cstring ||
	T == string ||
	T == string16 ||
	T == cstring16 {
	leftover: T = sql
	stmt: ^Stmt
	for rc == .Ok {
		if !is_sql_valid(leftover) do break

		stmt, rc = prepare(db, leftover, tail = &leftover)
		if rc != .Ok do break

		for {
			if step(stmt) != .Row do break
		}

		rc = finalize(stmt)
		stmt = nil
	}
	if stmt != nil {
		rc = finalize(stmt)
	}
	return
}

exec_all_callback :: proc(
	db: ^SQLite3,
	sql: $T,
	callback: proc(arg: rawptr, ncol: i32, vals, cols: []cstring) -> bool,
	arg: rawptr,
) -> (
	rc: Result_Code,
) where T == cstring ||
	T == string ||
	T == string16 ||
	T == cstring16 {
	leftover: T = sql
	stmt: ^Stmt

	cols := make([dynamic]cstring, context.temp_allocator)
	for rc == .Ok {
		if !is_sql_valid(leftover) do break

		stmt, rc = prepare(db, leftover, tail = &leftover)
		if rc != .Ok { rc = finalize(stmt); return }

		init := true
		ncols: i32
		for {
			if step(stmt) != .Row do break
			if init {
				init = false
				ncols = column_count(stmt)
				resize(&cols, ncols * 2)
				for i: i32 = 0; i < ncols; i += 1 {
					cols[i] = column_name(stmt, i)
					assert(cols[i] != nil)
				}
			}
			vals := (cast([^]cstring)(&cols[ncols]))[:ncols]
			for i: i32 = 0; i < ncols; i += 1 {
				vals[i] = column_text(stmt, i)
				if (vals[i] == nil && column_type(stmt, i) != .Null) {
					finalize(stmt)
					set_errmsg(db, .No_Mem, "out of memory")
					return .Abort
				}
			}
			if !callback(arg, ncols, vals, cols[:ncols]) {
				finalize(stmt)
				set_errmsg(db, .Abort, "callback aborted")
				return .Abort
			}
		}

		rc = finalize(stmt)
	}

	return
}

/*
Writes columns and rows.

Example:

	init: bool
	cols := make([dynamic]cstring, context.temp_allocator)
	for {
		rc = sqlite.step(stmt)
		if rc != .Row do break
		cols, vals, rc := sqlite.exec_column(db, stmt, &init, &cols)
	}
	rc = sqlite.finalize(stmt)
*/
read_row_into_column_array :: proc(
	db: ^SQLite3,
	stmt: ^Stmt,
	is_initialized: ^bool,
	cols: ^[dynamic]cstring,
) -> (
	columns, rows: []cstring,
	rc: Result_Code,
) {
	assert(cols != nil)
	ncols: i32

	if !is_initialized^ {
		ncols = column_count(stmt)

		resize(cols, int(ncols * 2))

		for i: i32 = 0; i < ncols; i += 1 {
			cols[i] = column_name(stmt, i)
			assert(cols[i] != nil)
		}
		is_initialized^ = true
	}
	vals := (cast([^]cstring)(&cols[ncols]))[:ncols]
	for i: i32 = 0; i < ncols; i += 1 {
		vals[i] = column_text(stmt, i)
		if (vals[i] == nil && column_type(stmt, i) != .Null) {
			set_errmsg(db, .No_Mem, "out of memory")
			rc = .No_Mem
			return
		}
	}
	columns = cols[:ncols]
	rows = vals

	return
}

/*
Dynamically append SQLite types from query.

TBD:

- Binding a cstring does requires allocations.

Example #1:

	stmt, rc := prepare(db, "INSERT INTO tags (tag) VALUES (?) RETURNING *", "mytag")
	for {
		rc = step(stmt)
		if rc != .Row { break }
		row := exec_dynamic(stmt)
		defer delete(row)
		id := row[0].(i64)
		tag := row[1].(cstring)
	}
	rc = finalize(stmt)

Example #2:

	stmt, rc := prepare(db, "SELECT * FROM tags;")
	for {
		rc = step(stmt)
		if rc != .Row { break }
		row := exec_dynamic(stmt)
		defer delete(row)
		id := row[0].(i64)
		tag := row[1].(cstring)
	}
	rc = finalize(stmt)
*/
read_row_into_dynamic_array :: proc(
	stmt: ^Stmt,
	allocator := context.temp_allocator,
	loc := #caller_location,
) -> []SQLite_Types {
	context.allocator = allocator
	columns := column_count(stmt)

	row := make([]SQLite_Types, columns)

	for i in 0 ..< columns {
		type := column_type(stmt, i)
		switch type {
		case .Integer:
			row[i] = column_int64(stmt, i)
		case .Float:
			row[i] = column_double(stmt, i)
		case .Text:
			row[i] = clone((column_text(stmt, i)), loc = loc)
		case .Blob:
			len := int(column_bytes(stmt, i))
			row[i] = mem.byte_slice(column_blob(stmt, i), len)
		case .Null:
			row[i] = nil
		}
	}
	return row
}

/*
Writes contents from row into user provided struct.

Errors are printed using log.error. All errors are due to wrong API usage.
Thus, in a correct program the error codepath will never execute.
There's no need to set the error message to the database.

TBD:

- Binding a any string type does requires allocations.

Example:

	stmt, rc := prepare(db, "INSERT INTO tags (tag) VALUES (?) RETURNING *", "mytag")
	for {
		rc := step(stmt)
		if rc != .Row { break }
		row := exec_struct(db, stmt, struct { id: i64, tag: string })
		id := row.id
		tag := row.tag
	}
	finalize(stmt)
*/
read_row_into_struct :: proc(
	db: ^SQLite3,
	stmt: ^Stmt,
	$T: typeid,
	allocator := context.temp_allocator,
	loc := #caller_location,
) -> (
	t: T,
	ok: bool,
) where intrinsics.type_is_struct(T) {
	struct_info := rt.type_info_base(type_info_of(T)).variant.(rt.Type_Info_Struct)
	if struct_info.soa_kind != .None {
		log.error("#soa structs not accepted.", location = loc)
		return
	}
	if .raw_union in struct_info.flags {
		log.errorf("Can not select into raw union: %v", typeid_of(T), location = loc)
		return
	}

	t_bytes := transmute([^]u8)&t
	for field, field_idx in struct_info.types[:struct_info.field_count] {
		col_idx := cast(i32)field_idx
		col_type := column_type(stmt, col_idx)
		field_base := rt.type_info_base(field)
		field_offs := struct_info.offsets[field_idx]
		if un, ok := field_base.variant.(rt.Type_Info_Union); ok {
			if !un.no_nil && len(un.variants) != 1 {
				log.errorf(
					"Only Maybe(T) is supported as union argument, %v not accepted",
					typeid_of(type_of(un)),
					location = loc,
				)
				return
			}
			field_base = un.variants[0]
		}
		#partial switch field_variant in field_base.variant {
		case rt.Type_Info_Boolean:
			if col_type != .Integer {
				log.errorf(
					"Type mismatch: %v <- %v",
					typeid_of(type_of(field_variant)),
					col_type,
					location = loc,
				)
				return
			}
			value := column_int64(stmt, col_idx)
			switch field.size {
			case 1:
				(transmute(^b8)&t_bytes[field_offs])^ = value != 0
			case 2:
				(transmute(^b16)&t_bytes[field_offs])^ = value != 0
			case 4:
				(transmute(^b32)&t_bytes[field_offs])^ = value != 0
			case 8:
				(transmute(^b64)&t_bytes[field_offs])^ = value != 0
			case:
				log.error(
					"Only bool sizes of 1, 2, 4 and 8 bytes are supported. Got: %d",
					field.size,
					location = loc,
				)
				return
			}
		case rt.Type_Info_Enum:
			if col_type == .Integer {
				value := column_int64(stmt, col_idx)
				switch field.size {
				case 1:
					(transmute(^i8)&t_bytes[field_offs])^ = cast(i8)value
				case 2:
					(transmute(^i16)&t_bytes[field_offs])^ = cast(i16)value
				case 4:
					(transmute(^i32)&t_bytes[field_offs])^ = cast(i32)value
				case 8:
					(transmute(^i64)&t_bytes[field_offs])^ = value
				case:
					log.error(
						"Only bool sizes of 1, 2, 4 and 8 bytes are supported. Got: %d",
						field.size,
						location = loc,
					)
					return
				}
			} else if col_type == .Text {
				name := column_text(stmt, col_idx)
				value_idx := -1
				for enum_name, idx in field_variant.names {
					if enum_name == cast(string)name {
						value_idx = idx
					}
				}
				if value_idx == -1 {
					log.error(
						"Enum value extracted from SQL stmt is not part of enum",
						location = loc,
					)
					return
				}
				value := field_variant.values[value_idx]
				switch field.size {
				case 1:
					(transmute(^i8)&t_bytes[field_offs])^ = cast(i8)value
				case 2:
					(transmute(^i16)&t_bytes[field_offs])^ = cast(i16)value
				case 4:
					(transmute(^i32)&t_bytes[field_offs])^ = cast(i32)value
				case 8:
					(transmute(^i64)&t_bytes[field_offs])^ = cast(i64)value
				case:
					log.error(
						"Only enum integer sizes of 1, 2, 4 and 8 bytes are supported. Got: %d",
						field.size,
						location = loc,
					)
					return
				}
			} else {
				log.errorf(
					"Type mismatch: %v <- %v",
					typeid_of(type_of(field_variant)),
					col_type,
					location = loc,
				)
				return
			}
		case rt.Type_Info_Float:
			if col_type != .Float {
				log.errorf(
					"Type mismatch: %v <- %v",
					typeid_of(type_of(field_variant)),
					col_type,
					location = loc,
				)
				return
			}
			value := column_double(stmt, col_idx)
			switch field.size {
			case 2:
				(transmute(^f16)&t_bytes[field_offs])^ = cast(f16)value
			case 4:
				(transmute(^f32)&t_bytes[field_offs])^ = cast(f32)value
			case 8:
				(transmute(^f64)&t_bytes[field_offs])^ = value
			case:
				log.errorf(
					"Only float sizes of 2, 4 and 8 bytes are supported. Got: %d",
					field.size,
					location = loc,
				)
				return
			}
		case rt.Type_Info_Integer:
			if col_type != .Integer {
				log.errorf(
					"Type mismatch: %v <- %v",
					typeid_of(type_of(field_variant)),
					col_type,
					location = loc,
				)
				return
			}
			value := column_int64(stmt, col_idx)
			switch field.size {
			case 1:
				(transmute(^i8)&t_bytes[field_offs])^ = cast(i8)value
			case 2:
				(transmute(^i16)&t_bytes[field_offs])^ = cast(i16)value
			case 4:
				(transmute(^i32)&t_bytes[field_offs])^ = cast(i32)value
			case 8:
				(transmute(^i64)&t_bytes[field_offs])^ = value
			case:
				log.errorf(
					"Only enum integer sizes of 1, 2, 4 and 8 bytes are supported. Got: %d",
					field.size,
					location = loc,
				)
				return
			}
		case rt.Type_Info_String:
			if col_type != .Text {
				log.errorf(
					"Type mismatch: %v <- %v",
					typeid_of(type_of(field_variant)),
					col_type,
					location = loc,
				)
				return
			}
			value := column_text(stmt, col_idx)
			switch field_variant.encoding {
			case .UTF_8:
				if field_variant.is_cstring {
					(cast(^cstring)&t_bytes[field_offs])^ = strings.clone_to_cstring(
						string(value),
						allocator,
					)
				} else {
					(cast(^string)&t_bytes[field_offs])^ = strings.clone(string(value), allocator)
				}
			case .UTF_16:
				if field_variant.is_cstring {
					(cast(^cstring16)&t_bytes[field_offs])^ = transmute(cstring16)strings.clone_to_cstring(
						string(value),
						allocator,
					)
				} else {
					(cast(^string16)&t_bytes[field_offs])^ = transmute(string16)strings.clone(
						string(value),
						allocator,
					)
				}
			}

		case rt.Type_Info_Array:
			if col_type != .Blob {
				log.errorf(
					"Type mismatch: %v <- %v",
					typeid_of(type_of(field_variant)),
					col_type,
					location = loc,
				)
				return
			}
			len := int(column_bytes(stmt, col_idx))
			value := column_blob(stmt, col_idx)
			mem.copy((transmute(^rawptr)&t_bytes[field_offs]), value, len)
		case:
			log.errorf(
				"Unsupported type for accepting SQL values in the given struct: %q",
				field_variant,
				location = loc,
			)
			return
		}
	}
	return t, true
}

@(private)
clone :: #force_inline proc(
	s: cstring,
	allocator := context.allocator,
	loc := #caller_location,
) -> (
	cstring,
	rt.Allocator_Error,
) #optional_allocator_error {
	if s == nil do return nil, .None
	return strings.clone_to_cstring(string(s))
}
