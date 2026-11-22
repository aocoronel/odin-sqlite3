/*
Wrappers to the C API.
*/
package sqlite3

import "base:runtime"
import "core:log"
import "core:reflect"

/*
Supports the SQL to be provided as string, cstring, string16 or cstring16.
*/
prepare :: proc {
	prepare8,
	prepare16,
}

/*
Prepare a statement using UTF-8 strings.
*/
prepare8 :: #force_inline proc(
	db: ^SQLite3,
	sql: $T,
	args: ..any,
	flags: Prepare_Flags = {},
	tail: ^cstring = nil,
	loc := #caller_location,
) -> (
	stmt: ^Stmt,
	rc: Result_Code,
) where T == cstring ||
	T == string {
	when T == string {
		prepare_v3(db, cstring(raw_data(sql)), cast(i32)len(sql), flags, &stmt, tail) or_return
	} else {
		prepare_v3(db, sql, -1, flags, &stmt, tail) or_return
	}
	rc = bind(stmt, ..args, loc = loc)
	return
}

/*
Prepare a statement using UTF-16 strings.
*/
prepare16 :: #force_inline proc(
	db: ^SQLite3,
	sql: $T,
	args: ..any,
	flags: Prepare_Flags = {},
	tail: ^cstring16 = nil,
	loc := #caller_location,
) -> (
	stmt: ^Stmt,
	rc: Result_Code,
) where T == string16 ||
	T == cstring16 {
	when T == string16 {
		panic("I think Odin's string16 is broken. All prepare procedures work, but this one")
		prepare16_v3(db, cstring16(raw_data(sql)), cast(i32)len(sql), flags, &stmt, tail) or_return
	} else {
		prepare16_v3(db, sql, -1, flags, &stmt, tail) or_return
	}
	rc = bind(stmt, ..args, loc = loc)
	return
}

/*
RTTI-based bindings.
*/
bind :: proc(stmt: ^Stmt, args: ..any, loc := #caller_location) -> (rc: Result_Code) {
	UNSUPPORTED_BINDING :: "Unsupported bind type: %v. Supports only integers, floats, booleans, strings, nil, Maybe(T) and [N]u8."
	for arg, arg_idx in args {
		arg_idx := cast(i32)arg_idx + 1
		arg_info := runtime.type_info_base(type_info_of(arg.id))
		if arg == nil {
			rc = bind_null(stmt, arg_idx)
			if rc != nil {
				log.errorf(UNSUPPORTED_BINDING, arg, errstr(rc), location = loc)
				return .Error
			}
			continue
		}
		if arg_variant, ok := arg_info.variant.(runtime.Type_Info_Union); ok {
			if !arg_variant.no_nil && len(arg_variant.variants) != 1 {
				log.errorf(
					"Only Maybe(T) is supported as union argument, %v not accepted.",
					typeid_of(type_of(arg_variant)),
					location = loc,
				)
				return .Error
			}
			arg_info = arg_variant.variants[0]
		}
		rc = Result_Code.Ok
		#partial switch arg_variant in arg_info.variant {
		case runtime.Type_Info_Integer:
			value, ok := reflect.as_i64(arg)
			assert(ok)
			rc = bind_int64(stmt, arg_idx, value)
		case runtime.Type_Info_Float:
			value, ok := reflect.as_f64(arg)
			assert(ok)
			rc = bind_double(stmt, arg_idx, value)
		case runtime.Type_Info_String:
			switch a in arg {
			case string:
				rc = bind_text(stmt, arg_idx, cstring(raw_data(a)), cast(i32)len(a), nil)
			case string16:
				rc = bind_text16(stmt, arg_idx, cstring16(raw_data(a)), cast(i32)len(a), nil)
			case cstring:
				rc = bind_text(stmt, arg_idx, a, -1, nil)
			case cstring16:
				rc = bind_text16(stmt, arg_idx, a, -1, nil)
			}
		case runtime.Type_Info_Boolean:
			value, ok := reflect.as_bool(arg)
			assert(ok)
			rc = bind_int(stmt, arg_idx, cast(i32)value)
		case runtime.Type_Info_Array:
			if arg_variant.elem.id != u8 {
				log.errorf("Unsupported bind type: %v.", arg_variant, location = loc)
				return .Error
			}
			value := reflect.as_bytes(arg)
			rc = bind_blob(stmt, arg_idx, raw_data(value), cast(i32)len(value), nil)
		case:
			log.errorf(UNSUPPORTED_BINDING, arg_variant, location = loc)
			return .Error
		}
		if rc != nil {
			log.errorf("Unable to bind argument %v: %s.", arg, errstr(rc), location = loc)
			return .Error
		}
	}
	return
}
