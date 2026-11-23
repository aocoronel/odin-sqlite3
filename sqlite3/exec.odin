/*
Better sqlite3_exec()
*/
package sqlite3

import "base:intrinsics"
import "base:runtime"
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
	"INSERT INTO tags (tag) VALUES (?) RETURNING *", "mytag",
	struct { id: i64, tag: string }
)
defer delete(rows)
if rc != .Ok { log.error(errmsg(db)) }
*/
exec_struct :: proc {
	read_row_into_struct,
	exec8_struct_query,
	exec16_struct_query,
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
	exec8_dynamic_query,
	exec16_dynamic_query,
}

/*
For this procedure, it's recommended that the allocator is an arena.

Only executes one statement.

Example:

cols, vals, tail, rc := exec_dynamic(
	db, "INSERT INTO tags (tag) VALUES (?) RETURNING *",
	"mytag"
)
defer {
	for col in cols {
		/* 'vals' shares the same array as 'cols' */
		delete(col)
	}
	delete(cols)
}
if rc != .Ok { log.error(errmsg(db)) }
*/
exec_column :: proc {
	read_row_into_column_array,
	exec8_column_query,
	exec16_column_query,
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
	exec8_ignore_query,
	exec16_ignore_query,
}

exec_all :: proc {
	exec_all_callback,
	exec_all_no_callback,
}

exec16_dynamic_query :: proc(
	db: ^SQLite3,
	sql: $Q,
	args: ..any,
	allocator := context.temp_allocator,
	loc := #caller_location,
) -> (
	rows: [dynamic][dynamic]SQLite_Types,
	tail: cstring16,
	rc: Result_Code,
) where Q == string16 ||
	Q == cstring16 {
	return _exec_dynamic_query(cstring16, db, sql, ..args, allocator = allocator, loc = loc)
}

exec8_dynamic_query :: proc(
	db: ^SQLite3,
	sql: $Q,
	args: ..any,
	allocator := context.temp_allocator,
	loc := #caller_location,
) -> (
	rows: [dynamic][dynamic]SQLite_Types,
	tail: cstring,
	rc: Result_Code,
) where Q == string ||
	Q == cstring {
	return _exec_dynamic_query(cstring, db, sql, ..args, allocator = allocator, loc = loc)
}

exec16_column_query :: proc(
	db: ^SQLite3,
	sql: $Q,
	args: ..any,
	cols: [dynamic]cstring = nil,
	allocator := context.temp_allocator,
	loc := #caller_location,
) -> (
	sCols, sVals: []cstring,
	tail: cstring16,
	rc: Result_Code,
) where Q == string16 ||
	Q == cstring16 {
	return _exec_column_query(
		cstring16,
		db,
		sql,
		..args,
		cols = cols,
		allocator = allocator,
		loc = loc,
	)
}

exec8_column_query :: proc(
	db: ^SQLite3,
	sql: $Q,
	args: ..any,
	cols: [dynamic]cstring = nil,
	allocator := context.temp_allocator,
	loc := #caller_location,
) -> (
	sCols, sVals: []cstring,
	tail: cstring,
	rc: Result_Code,
) where Q == string ||
	Q == cstring {
	return _exec_column_query(
		cstring,
		db,
		sql,
		..args,
		cols = cols,
		allocator = allocator,
		loc = loc,
	)
}

exec16_struct_query :: proc(
	db: ^SQLite3,
	sql: $Q,
	$T: typeid,
	args: ..any,
	allocator := context.temp_allocator,
	loc := #caller_location,
) -> (
	rows: [dynamic]T,
	tail: cstring16,
	rc: Result_Code,
) where Q == string16 ||
	Q == cstring16 {
	return _exec_struct_query(cstring16, db, sql, T, ..args, allocator = allocator, loc = loc)
}

exec8_struct_query :: proc(
	db: ^SQLite3,
	sql: $Q,
	$T: typeid,
	args: ..any,
	allocator := context.temp_allocator,
	loc := #caller_location,
) -> (
	rows: [dynamic]T,
	tail: cstring,
	rc: Result_Code,
) where Q == string ||
	Q == cstring {
	return _exec_struct_query(cstring, db, sql, T, ..args, allocator = allocator, loc = loc)
}

exec16_ignore_query :: proc(
	db: ^SQLite3,
	sql: $T,
	args: ..any,
	loc := #caller_location,
) -> (
	tail: cstring16,
	rc: Result_Code,
) where T == string16 ||
	T == cstring16 {
	return _exec_ignore_query(cstring16, db, sql, ..args, loc = loc)
}

exec8_ignore_query :: proc(
	db: ^SQLite3,
	sql: $T,
	args: ..any,
	loc := #caller_location,
) -> (
	tail: cstring,
	rc: Result_Code,
) where T == string ||
	T == cstring {
	return _exec_ignore_query(cstring, db, sql, ..args, loc = loc)
}

// WIP: early exit if query is empty
_invalid_query :: #force_inline proc "contextless" (
	sql: $T,
) -> bool where T == string16 ||
	T == cstring16 ||
	T == string ||
	T == cstring {
	when T == string || T == string16 {
		if len(sql) > 0 do return false
	} else when T == cstring {
		if sql != nil && (cast([^]u8)sql)[0] != 0 {
			return false
		}
	} else when T == cstring16 {
		if sql != nil && (cast([^]u16)sql)[0] != 0 {
			return false
		}
	}
	return true
}

/*
Does nothing with rows.

Only executes one statement.

Example:

  stmt, rc := prepare(db, "INSERT INTO tags (tag) VALUES (?)", "mytag")
  rc = exec(stmt)
  if rc != .Ok { log.error(errmsg(db)) }
  finalize(stmt)
*/
exec_ignore :: proc(stmt: ^Stmt) -> (rc: Result_Code) {
	for {
		rc = step(stmt)
		if rc != .Row {
			return .Ok if rc == .Done else rc
		}
	}
}

_exec_dynamic_query :: #force_inline proc(
	$TAIL_TYPE: typeid,
	db: ^SQLite3,
	sql: $Q,
	args: ..any,
	allocator := context.temp_allocator,
	loc := #caller_location,
) -> (
	rows: [dynamic][dynamic]SQLite_Types,
	tail: TAIL_TYPE,
	rc: Result_Code,
) where (TAIL_TYPE == cstring && Q == string || Q == cstring) ||
	(TAIL_TYPE == cstring16 && Q == string16 || Q == cstring16) {
	if _invalid_query(sql) do return

	rows.allocator = allocator
	stmt: ^Stmt

	stmt, rc = prepare(db, sql, ..args, tail = &tail, loc = loc)
	if rc == .Ok {
		for {
			if step(stmt) != .Row do break
			append(&rows, read_row_into_dynamic_array(stmt, nil, allocator, loc))
		}
	}

	rc = finalize(stmt)
	return
}

_exec_column_query :: #force_inline proc(
	$TAIL_TYPE: typeid,
	db: ^SQLite3,
	sql: $Q,
	args: ..any,
	cols: [dynamic]cstring = nil,
	allocator := context.temp_allocator,
	loc := #caller_location,
) -> (
	sCols, sVals: []cstring,
	tail: TAIL_TYPE,
	rc: Result_Code,
) where (TAIL_TYPE == cstring && Q == string || Q == cstring) ||
	(TAIL_TYPE == cstring16 && Q == string16 || Q == cstring16) {
	if _invalid_query(sql) do return

	stmt: ^Stmt
	cols := cols

	stmt, rc = prepare(db, sql, ..args, tail = &tail, loc = loc)
	if rc == .Ok {
		init := true
		ncols: i32
		for {
			rc = step(stmt)
			if rc != .Row do break
			if init {
				ncols = column_count(stmt)

				if cols == nil {
					cols = make([dynamic]cstring, ncols * 2, allocator)
				} else {
					reserve(&cols, int(ncols * 2))
				}

				for i: i32 = 0; i < ncols; i += 1 {
					cols[i] = column_name(stmt, i)
					assert(cols[i] != nil)
				}
				init = false
			}
			vals := cast([^]cstring)(&cols[ncols])
			for i: i32 = 0; i < ncols; i += 1 {
				vals[i] = column_text(stmt, i)
				if (vals[i] == nil && column_type(stmt, i) != .Null) {
					rc = set_errmsg(db, .No_Mem, "out of memory")
					return
				}
			}
			sCols = cols[:ncols]
			sVals = vals[:ncols]
		}
	}

	rc = finalize(stmt)

	return
}

_exec_struct_query :: #force_inline proc(
	$TAIL_TYPE: typeid,
	db: ^SQLite3,
	sql: $Q,
	$T: typeid,
	args: ..any,
	allocator := context.temp_allocator,
	loc := #caller_location,
) -> (
	rows: [dynamic]T,
	tail: TAIL_TYPE,
	rc: Result_Code,
) where (TAIL_TYPE == cstring && Q == string || Q == cstring) ||
	(TAIL_TYPE == cstring16 && Q == string16 || Q == cstring16) {
	if _invalid_query(sql) do return

	rows.allocator = allocator
	stmt: ^Stmt

	stmt, rc = prepare(db, sql, ..args, tail = &tail, loc = loc)
	if rc == .Ok {
		for {
			if step(stmt) != .Row do break
			append(&rows, read_row_into_struct(db, stmt, T, allocator, loc = loc) or_return)
		}
	}

	rc = finalize(stmt)
	return
}

_exec_ignore_query :: proc(
	$TAIL_TYPE: typeid,
	db: ^SQLite3,
	sql: $Q,
	args: ..any,
	loc := #caller_location,
) -> (
	tail: TAIL_TYPE,
	rc: Result_Code,
) where (TAIL_TYPE == cstring && Q == string || Q == cstring) ||
	(TAIL_TYPE == cstring16 && Q == string16 || Q == cstring16) {
	if _invalid_query(sql) do return
	stmt: ^Stmt

	stmt, rc = prepare(db, sql, ..args, tail = &tail, loc = loc)
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
	STRING :: cstring when T == string || T == cstring else cstring16
	ARRAY_CAST :: u8 when T == string || T == cstring else u16

	leftover: STRING
	next: T = sql
	stmt: ^Stmt

	for rc == .Ok {
		when T == string || T == string16 {
			if len(next) == 0 do break
		} else {
			if next != nil && (cast([^]ARRAY_CAST)next)[0] == 0 {
				break
			}
		}
		stmt, rc = prepare(db, next, tail = &leftover)
		if rc != .Ok { rc = finalize(stmt); return }

		for {
			if step(stmt) != .Row do break
		}

		rc = finalize(stmt)
		next = string(leftover) when STRING == string || STRING == cstring else string16(leftover)
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
	STRING :: cstring when T == string || T == cstring else cstring16
	ARRAY_CAST :: u8 when T == string || T == cstring else u16

	leftover: STRING
	next: T = sql
	stmt: ^Stmt

	cols := make([dynamic]cstring, context.temp_allocator)
	for rc == .Ok {
		when T == string || T == string16 {
			if len(next) == 0 do break
		} else {
			if next != nil && (cast([^]ARRAY_CAST)next)[0] == 0 {
				break
			}
		}
		stmt, rc = prepare(db, next, tail = &leftover)
		if rc != .Ok { rc = finalize(stmt); return }

		init := true
		ncols: i32
		for {
			if step(stmt) != .Row do break
			if init {
				ncols = column_count(stmt)
				resize(&cols, ncols * 2)
				for i: i32 = 0; i < ncols; i += 1 {
					cols[i] = column_name(stmt, i)
					assert(cols[i] != nil)
				}
				init = false
			}
			vals := cast([^]cstring)(&cols[ncols])
			for i: i32 = 0; i < ncols; i += 1 {
				vals[i] = column_text(stmt, i)
				if (vals[i] == nil && column_type(stmt, i) != .Null) {
					return set_errmsg(db, .No_Mem, "out of memory")
				}
			}
			if !callback(arg, ncols, vals[:ncols], cols[:ncols]) {
				finalize(stmt)
				return set_errmsg(db, .Abort, "callback aborted")
			}
		}

		rc = finalize(stmt)
		next = string(leftover) when STRING == string || STRING == cstring else string16(leftover)
	}

	return
}

/*
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
	sCols, sVals: []cstring,
	rc: Result_Code,
) {
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
	vals := cast([^]cstring)(&cols[ncols])
	for i: i32 = 0; i < ncols; i += 1 {
		vals[i] = column_text(stmt, i)
		if (vals[i] == nil && column_type(stmt, i) != .Null) {
			rc = set_errmsg(db, .No_Mem, "out of memory")
			return
		}
	}
	sCols = cols[:ncols]
	sVals = vals[:ncols]

	return
}

/*
Populates a dynamic array with the types provided in order.

Freeing the memory is necessary. The user can optionally reset the dynamic array and pass
it back, to minimize allocations.

Example:

stmt, rc := prepare(db, "INSERT INTO tags (tag) VALUES (?) RETURNING *", "mytag")
for {
    rc = step(stmt)
    if rc != .Row { finalize(stmt); break }
    row := exec_dynamic(stmt)
    id := row[0].(i64)
    tag := row[1].(cstring)
}

stmt, rc := prepare(db, "SELECT * FROM tags;")
row: [dynamic]SQLite_Types
for {
    rc = step(stmt)
    if rc != .Row { finalize(stmt); break }
    exec_dynamic(stmt, row)
    id := row[0].(i64)
    tag := row[1].(cstring)
}
*/
read_row_into_dynamic_array :: proc(
	stmt: ^Stmt,
	row: [dynamic]SQLite_Types = nil,
	allocator := context.temp_allocator,
	loc := #caller_location,
) -> [dynamic]SQLite_Types {
	context.allocator = allocator
	row := row
	columns := column_count(stmt)

	if row == nil {
		row = make([dynamic]SQLite_Types, columns, allocator)
	} else {
		resize(&row, columns)
	}

	for i in 0 ..< columns {
		type := column_type(stmt, i)
		switch type {
		case .Integer:
			row[i] = column_int64(stmt, i)
		case .Float:
			row[i] = column_double(stmt, i)
		case .Text:
			row[i] = strings.clone_to_cstring(string(column_text(stmt, i)), loc = loc)
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

This procedure doesn't perform allocations, except for string types.

Example:

stmt, rc := prepare(db, "INSERT INTO tags (tag) VALUES (?) RETURNING *", "mytag")
for {
    rc := step(stmt)
    if rc != .Row { finalize(stmt); break }
    row :=  exec_struct(db, stmt, struct { id: i64, tag: string })
    id := row.id
    tag := row.tag
}
*/
read_row_into_struct :: proc(
	db: ^SQLite3,
	stmt: ^Stmt,
	$T: typeid,
	allocator := context.temp_allocator,
	loc := #caller_location,
) -> (
	t: T,
	rc: Result_Code,
) where intrinsics.type_is_struct(T) {
	rc = .Error

	struct_info := runtime.type_info_base(type_info_of(T)).variant.(runtime.Type_Info_Struct)
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
		field_base := runtime.type_info_base(field)
		field_offs := struct_info.offsets[field_idx]
		if un, ok := field_base.variant.(runtime.Type_Info_Union); ok {
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
		case runtime.Type_Info_Boolean:
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
		case runtime.Type_Info_Enum:
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
		case runtime.Type_Info_Float:
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
		case runtime.Type_Info_Integer:
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
		case runtime.Type_Info_String:
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

		case runtime.Type_Info_Array:
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
	return t, .Ok
}
