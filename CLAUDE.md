# GIFT Converter

Gleam library for parsing and serializing the [GIFT format](https://docs.moodle.org/en/GIFT_format) (General Import Format Technology) — Moodle's text-based quiz question format.

Target: JavaScript (browser app built with Lustre).

## Commands

```sh
gleam build    # Build
gleam test     # Tests (gleeunit)
gleam format   # Format
```

## Architecture

- `src/gift/ast.gleam` — AST types for a GIFT document
- `src/gift/parser.gleam` — parser: GIFT → AST
- `src/gift/serializer.gleam` — serializer: AST → GIFT
- `src/app.gleam` — Lustre UI
- `index.html` — browser entry point

## GIFT format: key features

- Questions are separated by blank lines
- Special characters `~ = # { } :` are escaped with backslash
- Text format is specified in brackets: `[html]`, `[markdown]`, `[plain]`, `[moodle]`
- Question types: essay, true/false, multiple choice, short answer, matching, numerical
- Categories are set as `$CATEGORY: path/to/category`

## Gleam: idioms and practices

### Custom types over boolean flags
Instead of `Bool` fields, create custom types — this gives exhaustive matching and self-documenting code. Instead of `is_admin: Bool` → `type Role { Admin User }`.

### Make illegal states unrepresentable
Instead of `Option` fields + flags — split into separate type variants:
```gleam
// Bad: verified can be True when email is None
type User { User(email: Option(String), verified: Bool) }
// Good:
type User { Unverified(email: String) Verified(email: String) }
```

### `use` for Result/Option chains
`use` unwraps a callback — code after `use` becomes the body of the passed function:
```gleam
use user <- result.try(get_user(id))
use email <- result.try(validate_email(user.email))
Ok(email)
```
Don't use `use` for one-line lambdas — a plain `fn(x) { ... }` reads better.

### `use <- bool.guard(condition, default)` — early return
Equivalent to `if condition { return default }` in imperative languages.

### Pipeline `|>` — from 2+ steps
Pipelines are justified from two transformations onward. `x |> foo()` is no better than `foo(x)`.

### Strings
For building strings in a loop — use `string_tree` (formerly `StringBuilder`), not `<>` (O(n²)).

### Error handling
- `Result` — for expected errors. Custom error type per module.
- `let assert` / `panic` — only for invariants (programmer bug, not a runtime situation).
- `todo` — for unfinished branches during development.

### Pattern matching
- Spread `..` for records: `case user { User(name: "Admin", ..) -> ... }`
- Or-patterns: `case x { 1 | 2 | 3 -> "small" _ -> "big" }`
- Destructure nested structures directly: `case resp { Ok(User(name, ..)) -> name ... }`

### Modules
- Keep public API minimal — `pub` only for external use.
- Opaque types + smart constructors for encapsulation.
- Labeled arguments for functions with >2 parameters.

## Gleam: common pitfalls (from past sessions)

- **Imports: types vs constructors.** Types require `type` keyword: `import gift/ast.{type GiftDocument, Category, Question}`. Without `type` — it's a constructor, not a type.
- **`io.debug` does not exist** in the current `gleam/io`. For debugging: `io.println(string.inspect(value))`.
- **`_name` is a discard, not a variable.** You cannot pass `_depth` as a function argument. Use `depth` and suppress warnings with `_` only in patterns.
- **JS target: `string.drop_start` breaks on Unicode.** For character-by-character scanning of non-ASCII text — use `string.to_graphemes` + recursion over grapheme list. `string.slice` is safe.
- **`gleam/option.{type Option, Some, None}` exists in stdlib.** Don't define your own `Option` type. (This project uses a custom `Option` in `ast.gleam` — this is a legacy decision.)
- **Guards don't support function calls.** `case x { y if string.starts_with(y, "foo") -> ...` — won't compile. Use `<>` patterns: `"foo" <> rest -> ...`
