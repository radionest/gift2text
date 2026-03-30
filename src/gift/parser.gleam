import gift/ast.{
  type AnswerType, type Choice, type GiftDocument, type GiftItem,
  type MatchPair, type NumericalAnswer, type NumericalChoice, type Option,
  type QuestionData, type RichText, type TextFormat, Category, Choice,
  Description, Essay, GiftDocument, HighLow, Html, Markdown,
  MatchPair, Matching, Moodle, MultipleChoice, None, Numerical, NumericalChoice,
  Plain, Question, QuestionData, Range, RichText, ShortAnswer, SimpleNumber,
  Some, TrueFalse,
}
import gleam/float
import gleam/list
import gleam/string

pub fn parse(input: String) -> Result(GiftDocument, String) {
  let blocks = split_into_blocks(input)
  let items = list.filter_map(blocks, parse_block)
  Ok(GiftDocument(items: items))
}

fn split_into_blocks(input: String) -> List(String) {
  let lines = string.split(input, "\n")
  do_split_blocks(lines, "", [])
}

fn do_split_blocks(
  lines: List(String),
  current: String,
  acc: List(String),
) -> List(String) {
  case lines {
    [] ->
      case string.trim(current) {
        "" -> list.reverse(acc)
        trimmed -> list.reverse([trimmed, ..acc])
      }
    [line, ..rest] ->
      case string.trim(line) {
        "" ->
          case string.trim(current) {
            "" -> do_split_blocks(rest, "", acc)
            trimmed -> do_split_blocks(rest, "", [trimmed, ..acc])
          }
        _ -> {
          let new_current = case current {
            "" -> line
            _ -> current <> "\n" <> line
          }
          do_split_blocks(rest, new_current, acc)
        }
      }
  }
}

fn extract_content(block: String) -> String {
  let lines = string.split(block, "\n")
  case find_content_start(lines) {
    Some(content_lines) -> string.join(content_lines, "\n")
    None -> {
      let non_comment =
        list.filter(lines, fn(l) {
          let t = string.trim(l)
          !string.starts_with(t, "//")
        })
      string.join(non_comment, "\n")
    }
  }
}

fn find_content_start(lines: List(String)) -> Option(List(String)) {
  case lines {
    [] -> None
    [line, ..rest] -> {
      let trimmed = string.trim(line)
      case
        string.starts_with(trimmed, "$CATEGORY:")
        || string.starts_with(trimmed, "::")
      {
        True -> Some([line, ..rest])
        False -> find_content_start(rest)
      }
    }
  }
}

fn parse_block(block: String) -> Result(GiftItem, Nil) {
  let content = string.trim(extract_content(block))
  case content {
    "" -> Error(Nil)
    "$CATEGORY:" <> rest -> {
      let name =
        rest
        |> string.replace("\n", " ")
        |> string.trim
        |> strip_category_path
      Ok(Category(name: name))
    }
    _ ->
      case parse_question(content) {
        Ok(q) -> Ok(Question(data: q))
        Error(_) -> Error(Nil)
      }
  }
}

fn strip_category_path(cat: String) -> String {
  case cat {
    "$course$/" <> rest -> rest
    _ -> cat
  }
}

fn parse_question(block: String) -> Result(QuestionData, String) {
  let #(title, rest) = parse_title(block)
  let #(stem_text, answers_and_tail) = parse_stem_and_answers(rest)
  let #(format, clean_stem) = parse_format(stem_text)
  let stem = RichText(format: format, text: unescape(string.trim(clean_stem)))

  case answers_and_tail {
    None -> {
      Ok(QuestionData(
        title: title,
        stem: stem,
        answers: Description,
        global_feedback: None,
        has_embedded_answers: False,
      ))
    }
    Some(#(answer_block, tail)) -> {
      let #(answers, global_fb) = parse_answer_block(answer_block)
      let has_embedded = case string.trim(tail) {
        "" -> False
        _ -> True
      }
      let final_stem = case has_embedded {
        True -> RichText(format: format, text: stem.text <> " _____ " <> unescape(string.trim(tail)))
        False -> stem
      }
      Ok(QuestionData(
        title: title,
        stem: final_stem,
        answers: answers,
        global_feedback: global_fb,
        has_embedded_answers: has_embedded,
      ))
    }
  }
}

fn parse_title(input: String) -> #(Option(String), String) {
  case string.starts_with(input, "::") {
    False -> #(None, input)
    True -> {
      let rest = string.drop_start(input, 2)
      case string.split_once(rest, "::") {
        Ok(#(title, remainder)) -> #(Some(string.trim(title)), remainder)
        Error(_) -> #(None, input)
      }
    }
  }
}

fn parse_format(text: String) -> #(TextFormat, String) {
  let trimmed = string.trim(text)
  case trimmed {
    "[html]" <> rest -> #(Html, rest)
    "[markdown]" <> rest -> #(Markdown, rest)
    "[plain]" <> rest -> #(Plain, rest)
    "[moodle]" <> rest -> #(Moodle, rest)
    _ -> #(Moodle, trimmed)
  }
}

// --- Grapheme-list based scanning functions ---
// These avoid string.drop_start which has a UTF-8/UTF-16 mismatch bug
// in Gleam's JS stdlib when used with non-ASCII characters.

fn find_open_brace(chars: List(String), pos: Int) -> Option(Int) {
  case chars {
    [] -> None
    ["\\", _, ..rest] -> find_open_brace(rest, pos + 2)
    ["{", ..] -> Some(pos)
    [_, ..rest] -> find_open_brace(rest, pos + 1)
  }
}

fn find_close_brace(chars: List(String), pos: Int, depth: Int) -> Option(Int) {
  case chars {
    [] -> None
    ["\\", _, ..rest] -> find_close_brace(rest, pos + 2, depth)
    ["{", ..rest] -> find_close_brace(rest, pos + 1, depth + 1)
    ["}", ..rest] ->
      case depth {
        0 -> Some(pos)
        _ -> find_close_brace(rest, pos + 1, depth - 1)
      }
    [_, ..rest] -> find_close_brace(rest, pos + 1, depth)
  }
}

fn find_hash(chars: List(String), pos: Int) -> Option(Int) {
  case chars {
    [] -> None
    ["\\", _, ..rest] -> find_hash(rest, pos + 2)
    ["#", ..] -> Some(pos)
    [_, ..rest] -> find_hash(rest, pos + 1)
  }
}

/// Safe substring from position `start` to the end.
/// Uses string.slice (grapheme_slice) which handles non-ASCII correctly,
/// unlike string.drop_start on the JS target.
fn slice_from(s: String, start: Int) -> String {
  string.slice(s, start, string.length(s))
}

fn parse_stem_and_answers(
  input: String,
) -> #(String, Option(#(String, String))) {
  let chars = string.to_graphemes(input)
  case find_open_brace(chars, 0) {
    None -> #(input, None)
    Some(open_pos) -> {
      let stem = string.slice(input, 0, open_pos)
      let after_open = slice_from(input, open_pos + 1)
      let after_chars = string.to_graphemes(after_open)
      case find_close_brace(after_chars, 0, 0) {
        None -> #(input, None)
        Some(close_pos) -> {
          let answer_block = string.slice(after_open, 0, close_pos)
          let tail = slice_from(after_open, close_pos + 1)
          #(stem, Some(#(answer_block, tail)))
        }
      }
    }
  }
}

fn parse_answer_block(
  block: String,
) -> #(AnswerType, Option(RichText)) {
  let trimmed = string.trim(block)
  case trimmed {
    "" -> #(Essay, None)
    _ -> {
      let #(global_fb, clean_block) = extract_global_feedback(trimmed)
      let answers = classify_and_parse_answers(string.trim(clean_block))
      #(answers, global_fb)
    }
  }
}

fn extract_global_feedback(
  block: String,
) -> #(Option(RichText), String) {
  case string.split_once(block, "####") {
    Ok(#(before, fb)) -> #(
      Some(RichText(format: Moodle, text: unescape(string.trim(fb)))),
      before,
    )
    Error(_) -> #(None, block)
  }
}

fn classify_and_parse_answers(block: String) -> AnswerType {
  let lower = string.lowercase(block)
  case lower {
    "t" | "true" ->
      TrueFalse(is_true: True, true_feedback: None, false_feedback: None)
    "f" | "false" ->
      TrueFalse(is_true: False, true_feedback: None, false_feedback: None)
    "t#" <> _ | "true#" <> _ -> {
      let fb = extract_tf_feedback(block)
      TrueFalse(is_true: True, true_feedback: fb.0, false_feedback: fb.1)
    }
    "f#" <> _ | "false#" <> _ -> {
      let fb = extract_tf_feedback(block)
      TrueFalse(is_true: False, true_feedback: fb.0, false_feedback: fb.1)
    }
    "#" <> _ -> Numerical(choices: parse_numerical_choices(block))
    _ ->
      case contains_arrow(block) {
        True -> Matching(pairs: parse_match_pairs(block))
        False -> {
          let choices = parse_choices(block)
          case list.any(choices, fn(c) { !c.is_correct }) {
            True -> MultipleChoice(choices: choices)
            False -> ShortAnswer(choices: choices)
          }
        }
      }
  }
}

fn extract_tf_feedback(block: String) -> #(Option(String), Option(String)) {
  case string.split_once(block, "#") {
    Ok(#(_, after)) ->
      case string.split_once(after, "#") {
        Ok(#(fb1, fb2)) -> #(
          non_empty(string.trim(fb1)),
          non_empty(string.trim(fb2)),
        )
        Error(_) -> #(non_empty(string.trim(after)), None)
      }
    Error(_) -> #(None, None)
  }
}

fn non_empty(s: String) -> Option(String) {
  case s {
    "" -> None
    _ -> Some(s)
  }
}

fn contains_arrow(block: String) -> Bool {
  string.contains(block, "->")
}

fn parse_choices(block: String) -> List(Choice) {
  let entries = split_choices(block)
  list.filter_map(entries, parse_single_choice)
}

fn split_choices(block: String) -> List(String) {
  do_split_choices(string.to_graphemes(block), "", [], False)
}

fn do_split_choices(
  chars: List(String),
  current: String,
  acc: List(String),
  started: Bool,
) -> List(String) {
  case chars {
    [] ->
      case string.trim(current) {
        "" -> list.reverse(acc)
        trimmed -> list.reverse([trimmed, ..acc])
      }
    ["\\", next, ..rest] ->
      do_split_choices(rest, current <> "\\" <> next, acc, started)
    [c, ..rest] if c == "=" || c == "~" ->
      case started {
        False -> do_split_choices(rest, c, acc, True)
        True -> {
          let trimmed = string.trim(current)
          case trimmed {
            "" -> do_split_choices(rest, c, acc, True)
            _ -> do_split_choices(rest, c, [trimmed, ..acc], True)
          }
        }
      }
    [c, ..rest] -> do_split_choices(rest, current <> c, acc, started)
  }
}

fn parse_single_choice(entry: String) -> Result(Choice, Nil) {
  case string.pop_grapheme(entry) {
    Ok(#("=", rest)) -> {
      let #(weight, text_with_fb) = parse_weight(rest)
      let #(text, feedback) = parse_choice_feedback(text_with_fb)
      Ok(Choice(
        is_correct: True,
        text: unescape(string.trim(text)),
        weight: weight,
        feedback: feedback,
      ))
    }
    Ok(#("~", rest)) -> {
      let #(weight, text_with_fb) = parse_weight(rest)
      let #(text, feedback) = parse_choice_feedback(text_with_fb)
      Ok(Choice(
        is_correct: False,
        text: unescape(string.trim(text)),
        weight: weight,
        feedback: feedback,
      ))
    }
    _ -> Error(Nil)
  }
}

fn parse_weight(text: String) -> #(Option(Float), String) {
  case string.starts_with(text, "%") {
    False -> #(None, text)
    True -> {
      let rest = string.drop_start(text, 1)
      case string.split_once(rest, "%") {
        Ok(#(weight_str, remainder)) ->
          case float.parse(weight_str) {
            Ok(w) -> #(Some(w), remainder)
            Error(_) ->
              case parse_int_as_float(weight_str) {
                Ok(w) -> #(Some(w), remainder)
                Error(_) -> #(None, text)
              }
          }
        Error(_) -> #(None, text)
      }
    }
  }
}

fn parse_int_as_float(s: String) -> Result(Float, Nil) {
  case string.starts_with(s, "-") {
    True -> {
      let rest = string.drop_start(s, 1)
      case parse_digits(rest, 0) {
        Ok(n) -> Ok(int_negate_float(n))
        Error(_) -> Error(Nil)
      }
    }
    False ->
      case parse_digits(s, 0) {
        Ok(n) -> Ok(int_to_gleam_float(n))
        Error(_) -> Error(Nil)
      }
  }
}

fn parse_digits(s: String, acc: Int) -> Result(Int, Nil) {
  case string.pop_grapheme(s) {
    Error(_) ->
      case acc {
        0 -> Error(Nil)
        _ -> Ok(acc)
      }
    Ok(#(c, rest)) ->
      case digit_value(c) {
        Ok(d) -> parse_digits(rest, acc * 10 + d)
        Error(_) ->
          case s == "" {
            True -> Ok(acc)
            False ->
              case acc > 0 {
                True -> Ok(acc)
                False -> Error(Nil)
              }
          }
      }
  }
}

fn digit_value(c: String) -> Result(Int, Nil) {
  case c {
    "0" -> Ok(0)
    "1" -> Ok(1)
    "2" -> Ok(2)
    "3" -> Ok(3)
    "4" -> Ok(4)
    "5" -> Ok(5)
    "6" -> Ok(6)
    "7" -> Ok(7)
    "8" -> Ok(8)
    "9" -> Ok(9)
    _ -> Error(Nil)
  }
}

fn int_to_gleam_float(n: Int) -> Float {
  case n {
    0 -> 0.0
    _ -> {
      let assert Ok(f) = float.parse(string.inspect(n) <> ".0")
      f
    }
  }
}

fn int_negate_float(n: Int) -> Float {
  let f = int_to_gleam_float(n)
  float.negate(f)
}

fn parse_choice_feedback(text: String) -> #(String, Option(String)) {
  let chars = string.to_graphemes(text)
  case find_hash(chars, 0) {
    None -> #(text, None)
    Some(pos) -> {
      let before = string.slice(text, 0, pos)
      let after = slice_from(text, pos + 1)
      #(before, Some(unescape(string.trim(after))))
    }
  }
}

fn parse_match_pairs(block: String) -> List(MatchPair) {
  let entries = split_choices(block)
  list.filter_map(entries, fn(entry) {
    case string.pop_grapheme(entry) {
      Ok(#("=", rest)) ->
        case string.split_once(rest, "->") {
          Ok(#(q, a)) ->
            Ok(MatchPair(
              subquestion: unescape(string.trim(q)),
              subanswer: unescape(string.trim(a)),
            ))
          Error(_) -> Error(Nil)
        }
      _ -> Error(Nil)
    }
  })
}

fn parse_numerical_choices(block: String) -> List(NumericalChoice) {
  let content = string.drop_start(block, 1)
  let entries = string.split(content, "=")
  list.filter_map(entries, fn(entry) {
    let trimmed = string.trim(entry)
    case trimmed {
      "" -> Error(Nil)
      _ -> {
        let #(answer_text, feedback) = parse_choice_feedback(trimmed)
        let #(weight, answer_str) = parse_weight(string.trim(answer_text))
        case parse_numerical_answer(string.trim(answer_str)) {
          Ok(answer) ->
            Ok(NumericalChoice(answer: answer, weight: weight, feedback: feedback))
          Error(_) -> Error(Nil)
        }
      }
    }
  })
}

fn parse_numerical_answer(text: String) -> Result(NumericalAnswer, Nil) {
  case string.split_once(text, "..") {
    Ok(#(low_str, high_str)) ->
      case parse_number(string.trim(low_str)), parse_number(string.trim(high_str)) {
        Ok(low), Ok(high) -> Ok(HighLow(low: low, high: high))
        _, _ -> Error(Nil)
      }
    Error(_) ->
      case string.split_once(text, ":") {
        Ok(#(val_str, tol_str)) ->
          case parse_number(string.trim(val_str)), parse_number(string.trim(tol_str)) {
            Ok(val), Ok(tol) -> Ok(Range(value: val, tolerance: tol))
            _, _ -> Error(Nil)
          }
        Error(_) ->
          case parse_number(text) {
            Ok(val) -> Ok(SimpleNumber(value: val))
            Error(_) -> Error(Nil)
          }
      }
  }
}

fn parse_number(text: String) -> Result(Float, Nil) {
  case float.parse(text) {
    Ok(f) -> Ok(f)
    Error(_) -> parse_int_as_float(string.trim(text))
  }
}

fn unescape(text: String) -> String {
  do_unescape(string.to_graphemes(text), "")
}

fn do_unescape(chars: List(String), acc: String) -> String {
  case chars {
    [] -> acc
    ["\\", "n", ..rest] -> do_unescape(rest, acc <> "\n")
    ["\\", c, ..rest] -> do_unescape(rest, acc <> c)
    [c, ..rest] -> do_unescape(rest, acc <> c)
  }
}
