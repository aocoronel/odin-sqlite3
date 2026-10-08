package sqlite3

import "base:intrinsics"
import "base:runtime"
import "core:log"
import "core:mem"
import "core:reflect"
import "core:strings"

/*
Notes for this file:

Base SQLite for the examples:

CREATE TABLE tags (
  id INTEGER PRIMARY KEY NOT NULL,
  tag TEXT NOT NULL UNIQUE
);

Tips and tricks:

assert(Status.Ok == nil)
*/

SQLite_Types :: union {
	i64,
	f64,
	cstring,
	bool,
	[]u8,
}

execute :: proc {
	execute_struct,
	execute_query_struct,
	execute_dynamic,
	execute_query_dynamic,
	execute_ignore,
	execute_query_ignore,
}

/*
This procedure does perform allocations.

Example:

query, status := prepare(db, "insert into tags (tag) values (?) returning *", "mytag")
for {
    row, status := execute(db, query)
    defer delete(row)
    if status != nil { break }
    id := row[0].(i64)
    tag := row[1].(cstring)
}

query, status := prepare(db, "select * from tags;")
row: [dynamic]SQLite_Types
status: Status
for {
    clear(row)
    row, status = execute(db, query, rows = row)
    if status != nil { break }
    id := row[0].(i64)
    tag := row[1].(cstring)
}
*/
execute_dynamic :: proc(
	db: ^SQLite3,
	query: ^Stmt,
	rows: [dynamic]SQLite_Types = nil,
	allocator := context.allocator,
	temp_allocator := context.temp_allocator,
) -> (
	row: [dynamic]SQLite_Types,
	status: Status,
) {
	op := step(query)
	#partial switch op {
	case .Row:
		return read_row_into_dynamic_array(query, rows, allocator, temp_allocator), .Ok
	case .Done:
		finalize(query) or_return
		status = .Done
		return
	case:
		status = op
		return
	}
	panic("unreachable")
}

/*
This procedure does perform allocations. The max amount of appended rows
is set by 'n', leave -1 for unlimited.

For this procedure, it's recommended that the allocator is an arena.

Example:

rows, status := execute(db, context.allocator, "insert into tags (tag) values (?) returning *", "mytag")
defer {
	for row in rows {
		delete(row)
	}
	delete(rows)
}
if status != .Done { log.error(errmsg(status)) }
*/
execute_query_dynamic :: proc(
	db: ^SQLite3,
	allocator: runtime.Allocator,
	sql: string,
	args: ..any,
	n := -1,
	temp_allocator := context.temp_allocator,
	loc := #caller_location,
) -> (
	rows: [dynamic][dynamic]SQLite_Types,
	status: Status,
) {
	if n == -1 {
		rows.allocator = allocator
	} else if n > 0 {
		rows = make([dynamic][dynamic]SQLite_Types, n, allocator = allocator)
	}
	query := prepare(db, sql, ..args, loc = loc) or_return
	for {
		op := step(query)
		#partial switch op {
		case .Row:
			if n == -1 || len(rows) < n {
				append(
					&rows,
					read_row_into_dynamic_array(query, nil, allocator, temp_allocator, loc),
				)
			}
			continue
		case .Done:
			finalize(query) or_return
			status = .Done
			return
		case:
			status = op
			return
		}
		panic("unreachable")
	}
}

/*
This procedure doesn't perform allocations.

Example:

query, status := prepare(db, "insert into tags (tag) values (?) returning *", "mytag")
for {
    row, status := execute(db, query, struct { id: i64, tag: string })
    if status != nil { break }
    id := row.id
    tag := row.tag
}
*/
execute_struct :: proc(
	db: ^SQLite3,
	query: ^Stmt,
	$T: typeid,
	loc := #caller_location,
) -> (
	row: T,
	status: Status,
) {
	op := step(query)
	#partial switch op {
	case .Row:
		return read_row_into_struct(db, query, T, loc = loc)
	case .Done:
		finalize(query) or_return
		status = .Done
		return
	case:
		status = op
		return
	}
	panic("unreachable")
}

/*
This procedure does perform allocations. The max amount of appended rows
is set by 'n', leave -1 for unlimited.

Example:

rows, status := execute(db, context.allocator, struct { id: i64, tag: string }, "insert into tags (tag) values (?) returning *", "mytag")
defer delete(rows)
if status != .Done { log.error(errmsg(status)) }
*/
execute_query_struct :: proc(
	db: ^SQLite3,
	allocator: runtime.Allocator,
	$T: typeid,
	sql: string,
	args: ..any,
	n := -1,
	loc := #caller_location,
) -> (
	rows: [dynamic]T,
	status: Status,
) {
	if n == -1 {
		rows.allocator = allocator
	} else if n > 0 {
		rows = make([dynamic]T, n, allocator = allocator)
	}
	query := prepare(db, sql, ..args, loc = loc) or_return
	for {
		op := step(query)
		#partial switch op {
		case .Row:
			if n == -1 || len(rows) < n {
				append(&rows, read_row_into_struct(db, query, T, loc = loc) or_return)
			}
			continue
		case .Done:
			finalize(query) or_return
			status = .Done
			return
		case:
			status = op
			return
		}
		panic("unreachable")
	}
}

/*
Doesn't handle the rows.

Example:

query, status := prepare(db, "insert into tags (tag) values (?)", "mytag")
status := execute(db, query)
if status != .Done { log.error(errmsg(status)) }
*/
execute_ignore :: proc(query: ^Stmt) -> Status {
	for {
		op := step(query)
		if op == .Row do continue
		return op
	}
}

/*
Doesn't handle the rows.

Example:

status := execute(db, "insert into tags (tag) values (?)", "mytag")
if status != .Done { log.error(errmsg(status)) }
*/
execute_query_ignore :: proc(
	db: ^SQLite3,
	sql: string,
	args: ..any,
	loc := #caller_location,
) -> Status {
	query := prepare(db, sql, ..args, loc = loc) or_return
	for {
		op := step(query)
		if op == .Row do continue
		return op
	}
}

prepare :: proc(
	db: ^SQLite3,
	sql: string,
	args: ..any,
	loc := #caller_location,
) -> (
	query: ^Stmt,
	status: Status,
) {
	unused: [^]u8
	prepare_v2(db, raw_data(sql), cast(i32)len(sql), &query, &unused) or_return
	status = bind(query, ..args, loc = loc)
	return
}

bind :: proc(query: ^Stmt, args: ..any, loc := #caller_location) -> (status: Status) {
	for arg, arg_idx in args {
		arg_idx := cast(i32)arg_idx + 1
		arg_info := runtime.type_info_base(type_info_of(arg.id))
		if arg == nil {
			status = bind_null(query, arg_idx)
			if status != nil {
				log.errorf("Unable to bind argument %v: %s", arg, errstr(status), location = loc)
				return .Error
			}
			continue
		}
		status = Status.Ok
		#partial switch arg_variant in arg_info.variant {
		case runtime.Type_Info_Integer:
			value, ok := reflect.as_i64(arg)
			assert(ok)
			status = bind_int64(query, arg_idx, value)
		case runtime.Type_Info_Float:
			value, ok := reflect.as_f64(arg)
			assert(ok)
			status = bind_double(query, arg_idx, value)
		case runtime.Type_Info_String:
			value, ok := reflect.as_string(arg)
			assert(ok)
			status = bind_text(query, arg_idx, raw_data(value), cast(i32)len(value), nil)
		case runtime.Type_Info_Boolean:
			value, ok := reflect.as_bool(arg)
			assert(ok)
			status = bind_int(query, arg_idx, cast(i32)value)
		case runtime.Type_Info_Array:
			if arg_variant.elem.id != u8 {
				log.errorf("Unsupported bind type: %v", arg_variant, location = loc)
				return .Error
			}
			value := reflect.as_bytes(arg)
			status = bind_blob(query, arg_idx, raw_data(value), cast(i32)len(value), nil)
		case:
			log.errorf("Unsupported bind type: %v", arg_variant, location = loc)
			return .Error
		}
	}
	return
}

/*
Populates a dynamic array with the types provided in order.

Freeing the memory is necessary. The user can optionally reset the dynamic array and pass
it back, to minimize allocations.
*/
read_row_into_dynamic_array :: proc(
	query: ^Stmt,
	row: [dynamic]SQLite_Types = nil,
	allocator := context.allocator,
	temp_allocator := context.temp_allocator,
	loc := #caller_location,
) -> [dynamic]SQLite_Types {
	row := row
	columns := column_count(query)

	if row == nil {
		row = make([dynamic]SQLite_Types, columns, allocator)
	} else {
		if cap(row) < cast(int)columns {
			reserve(&row, columns)
		}
	}

	for i in 0 ..< columns {
		type := column_type(query, i)
		switch type {
		case .Integer:
			row[i] = column_int64(query, i)
		case .Float:
			row[i] = column_double(query, i)
		case .Text:
			row[i] = strings.clone_to_cstring(string(column_text(query, i)), temp_allocator, loc)
		case .Blob:
			len := int(column_bytes(query, i))
			row[i] = mem.byte_slice(column_blob(query, i), len)
		case .Null:
			row[i] = nil
		}
	}
	return row
}

/*
Writes contents from row into user provided struct.
*/
read_row_into_struct :: proc(
	db: ^SQLite3,
	query: ^Stmt,
	$T: typeid,
	loc := #caller_location,
) -> (
	t: T,
	status: Status,
) where intrinsics.type_is_struct(T) {
	status = .Error

	struct_info := runtime.type_info_base(type_info_of(T)).variant.(runtime.Type_Info_Struct)
	if struct_info.soa_kind != .None {
		log.error("#soa structs not accepted.")
		return
	}
	if .raw_union in struct_info.flags {
		log.errorf("Can not select into raw union: %v", typeid_of(T), location = loc)
		return
	}

	t_bytes := transmute([^]u8)&t
	for field, field_idx in struct_info.types[:struct_info.field_count] {
		col_idx := cast(i32)field_idx
		col_type := column_type(query, col_idx)
		field_base := runtime.type_info_base(field)
		field_offs := struct_info.offsets[field_idx]
		if un, ok := field_base.variant.(runtime.Type_Info_Union); ok {
			if !un.no_nil || len(un.variants) != 1 {
				log.errorf, location = loc(
					"Only Maybe(T) is supported as union argument, %v not accepted",
					typeid_of(type_of(un)),
				)
				return
			}
			field_base = un.variants[0]
		}
		#partial switch field_variant in field_base.variant {
		case runtime.Type_Info_Any:
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
			value := column_int64(query, col_idx)
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
				)
				return
			}
		case runtime.Type_Info_Enum:
			if col_type == .Integer {
				value := column_int64(query, col_idx)
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
					)
					return
				}
			} else if col_type == .Text {
				name := column_text(query, col_idx)
				value_idx := -1
				for enum_name, idx in field_variant.names {
					if enum_name == cast(string)name {
						value_idx = idx
					}
				}
				if value_idx == -1 {
					log.error("Enum value extracted from SQL query is not part of enum")
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
			value := column_double(query, col_idx)
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
			value := column_int64(query, col_idx)
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
			value := column_text(query, col_idx)
			if field_variant.is_cstring {
				(transmute(^cstring)&t_bytes[field_offs])^ = value
			} else {
				(transmute(^string)&t_bytes[field_offs])^ = cast(string)value
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
			len := int(column_bytes(query, col_idx))
			value := column_blob(query, col_idx)
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
