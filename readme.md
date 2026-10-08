# odin-sqlite3

> [!WARNING]
> These bindings were hand-written and thus can contain many mistakes. In case
> you found a mistake consider [opening up an issue](https://github.com/flysand7/odin-sqlite3/issues)
> or making a [pull request](https://github.com/flysand7/odin-sqlite3/pulls).

This repository contains sqlite3 bindings and a wrapper library for Odin.

## Project structure:

- `/amalgamation/`: sqlite3's official amalgamation of the source code. Replace
    the contents of the folder with fresh version of amalgamation to update the version.
- `/bindings/`: Raw bindings of sqlite3.
- `/bindings/bin/`: Compiled binaries of the sqlite3 library.
- `/wrapper/`: A more convenient interface to the sqlite3 library.
- `/test/`: An example of using the sqlite3 wrapper.

## Building and usage.

1. Clone this repository.
2. Build the binaries:
    - Windows: Run `./build-cl.bat`, in case you want to build with MSVC compiler; or `./build-clang-windows.bat` to build the clang.
    - Linux: Run `./build-clang-linux`
3. Copy the files to your project:
    - Just the bindings: copy `/bindings` directories.
    - With the wrapper: copy `/bindings` and `/wrapper` directories.

## Example

> This uses the API provided in bindings/extras.odin.

### Open the database:

```odin
DB_FILE :: "test/db.sqlite"
db: ^sqlite3.SQLite3
err := sqlite3.open(DB_FILE, &db)
if err != nil {
	log.errorf("Unable to open database '%s'(%v): %s", DB_FILE, status, sqlite.errmsg(db))
	return
}
defer sqlite3.close(db)
// Do things with database
```

### Run a simple query to create some tables:

```odin
_ = sqlite.execute(db, `
    CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY,
        name VARCHAR(64) NOT NULL,
        flag INTEGER NOT NULL,
    );`
)
_ = sqlite.execute(db, `
    INSERT INTO users (name, flag) VALUES
        (?, ?),
        (?, ?),
        (?, ?),
        (?, ?);`,
    "john", 1,
    "mary", 0,
    "alice", 1,
    "bob", 0)
)
```

Which is equivalent to:

```odin
_ = sqlite.execute(db, `
    CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY,
        name VARCHAR(64) NOT NULL,
        flag INTEGER NOT NULL
   );`
)
query, _ := sqlite.prepare(db, `
    INSERT INTO users (name, flag) VALUES
        (?, ?),
        (?, ?),
        (?, ?),
        (?, ?);`,
    "john", 1,
    "mary", 0,
    "alice", 1,
    "bob", 0)
_ = sqlite.execute(query)
```

### Iterate select results:

```odin
// Create prepared statement
query, status := sqlite.prepare(db, `
    INSERT into users (name, flag) VALUES
       (?, ?),
       (?, ?)
    RETURNING *`, "douglas", 1, "jonathan", 0)

// Iterate the results
for {
	row, status := sqlite.execute(db, query, nil)
    defer delete(row)
    if status != nil { break }
	fmt.println(row)
}
```

Alternatively, the iteration can be performed without allocations.

```odin
// Create prepared statement
query, status := sqlite.prepare(db, `
    INSERT into users (name, flag) VALUES
       (?, ?),
       (?, ?)
    RETURNING *`, "douglas", 1, "jonathan", 0)

// Iterate the results
for {
	row, status := sqlite.execute(db, query, struct { name: string, flag: bool })
    if status != nil { break }
	fmt.println(row)
}
```

### Collect all results

```odin
rows, status := sqlite.execute(db, context.allocator, `
    INSERT into users (name, flag) VALUES
       (?, ?),
       (?, ?)
    RETURNING *`, "douglas", 1, "jonathan", 0)
defer {
	for row in rows {
		delete(row)
	}
	delete(rows)
}
```

Alternatively with structs:

```odin
rows, status := sqlite.execute(db, context.allocator,
    struct { name: string, flag: bool }, `
    INSERT into users (name, flag) VALUES
       (?, ?),
       (?, ?)
    RETURNING *`, "douglas", 1, "jonathan", 0)
defer delete(rows)
```
