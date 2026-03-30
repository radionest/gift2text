---
paths:
  - "src/gift/parser.gleam"
  - "test/gift_test.gleam"
---

# GIFT Parser

## String scanning

The parser uses grapheme lists (`string.to_graphemes`) for character-by-character scanning.
DO NOT use `string.drop_start` for scanning — on the JS target it breaks on Cyrillic and other non-ASCII characters (UTF-8/UTF-16 mismatch).

Safe functions:
- `string.to_graphemes` → recursion over `List(String)`
- `string.slice(s, start, length)` — handles Unicode correctly
- `slice_from(s, start)` — wrapper over `string.slice` to end of string

Scanning functions (`find_open_brace`, `find_close_brace`, `find_hash`) take `List(String)` and `pos: Int`, handle escape sequences `\\`.

## Parsing pipeline

1. `split_into_blocks` — splits input by blank lines
2. `extract_content` / `find_content_start` — skips `//` comments before `$CATEGORY:` or `::`
3. `parse_block` — category or question
4. `parse_question` — title → stem+answers → format → answer_block

## Testing

Tests must include Cyrillic text — this is the primary source of bugs.
Run `gleam test` after any parser change.
