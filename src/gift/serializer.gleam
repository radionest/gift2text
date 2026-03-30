import gift/ast.{
  type AnswerType, type Choice, type GiftDocument,
  type MatchPair, type NumericalChoice, type Option,
  type QuestionData, Category, Description, Essay,
  HighLow, Matching, MultipleChoice, None, Numerical,
  Question, Range, ShortAnswer, SimpleNumber,
  Some, TrueFalse,
}
import gleam/float
import gleam/list
import gleam/string

pub type ChoiceStyle {
  Letters
  Numbers
  Bullets
}

pub type SerializerConfig {
  SerializerConfig(
    show_correct_answers: Bool,
    show_feedback: Bool,
    show_weights: Bool,
    number_questions: Bool,
    choice_style: ChoiceStyle,
    show_categories: Bool,
  )
}

pub fn default_config() -> SerializerConfig {
  SerializerConfig(
    show_correct_answers: True,
    show_feedback: False,
    show_weights: False,
    number_questions: True,
    choice_style: Letters,
    show_categories: True,
  )
}

pub fn serialize(doc: GiftDocument, config: SerializerConfig) -> String {
  let #(_, parts) =
    list.fold(doc.items, #(1, []), fn(acc, item) {
      let #(num, parts) = acc
      case item {
        Category(name) ->
          case config.show_categories {
            True -> #(num, ["\n--- " <> name <> " ---\n", ..parts])
            False -> #(num, parts)
          }
        Question(data) -> {
          let text = serialize_question(data, num, config)
          #(num + 1, [text, ..parts])
        }
      }
    })
  list.reverse(parts)
  |> string.join("\n")
  |> string.trim
}

fn is_redundant_title(title: String, stem: String) -> Bool {
  let trimmed = case string.ends_with(title, "...") {
    True -> string.drop_end(title, 3)
    False -> title
  }
  case trimmed {
    "" -> True
    _ -> string.starts_with(stem, trimmed)
  }
}

fn serialize_question(
  q: QuestionData,
  num: Int,
  config: SerializerConfig,
) -> String {
  let title_part = case q.title {
    Some(t) ->
      case is_redundant_title(t, q.stem.text) {
        True -> ""
        False -> t
      }
    None -> ""
  }

  let prefix = case config.number_questions {
    True -> int_to_string(num) <> ". "
    False -> ""
  }

  let header = case title_part {
    "" -> prefix <> q.stem.text
    t ->
      case config.number_questions {
        True -> prefix <> t <> "\n" <> q.stem.text
        False -> t <> "\n" <> q.stem.text
      }
  }

  let answers_text = serialize_answers(q.answers, config)

  let fb_text = case q.global_feedback, config.show_feedback {
    Some(fb), True -> "\n   Общий комментарий: " <> fb.text
    _, _ -> ""
  }

  header <> answers_text <> fb_text
}

fn serialize_answers(answers: AnswerType, config: SerializerConfig) -> String {
  case answers {
    Description -> ""
    Essay -> "\n   [Поле для ответа]"
    TrueFalse(is_true, true_fb, false_fb) ->
      serialize_true_false(is_true, true_fb, false_fb, config)
    MultipleChoice(choices) -> serialize_choices(choices, config)
    ShortAnswer(choices) -> serialize_short_answer(choices, config)
    Matching(pairs) -> serialize_matching(pairs, config)
    Numerical(choices) -> serialize_numerical(choices, config)
  }
}

fn serialize_true_false(
  is_true: Bool,
  true_fb: Option(String),
  false_fb: Option(String),
  config: SerializerConfig,
) -> String {
  let answer = case config.show_correct_answers {
    True ->
      case is_true {
        True -> "\n   Ответ: Верно"
        False -> "\n   Ответ: Неверно"
      }
    False -> "\n   (Верно / Неверно)"
  }

  let fb = case config.show_feedback {
    True -> {
      let tfb = case true_fb {
        Some(f) -> "\n   Комментарий (Верно): " <> f
        None -> ""
      }
      let ffb = case false_fb {
        Some(f) -> "\n   Комментарий (Неверно): " <> f
        None -> ""
      }
      tfb <> ffb
    }
    False -> ""
  }

  answer <> fb
}

fn serialize_choices(choices: List(Choice), config: SerializerConfig) -> String {
  let indexed =
    list.index_map(choices, fn(choice, i) { #(i, choice) })
  list.fold(indexed, "", fn(acc, pair) {
    let #(i, choice) = pair
    let marker = choice_marker(i, config.choice_style)
    let correct_mark = case config.show_correct_answers, choice.is_correct {
      True, True -> " ✓"
      True, False -> ""
      _, _ -> ""
    }
    let weight_mark = case config.show_weights, choice.weight {
      True, Some(w) -> " [" <> float_to_string(w) <> "%]"
      _, _ -> ""
    }
    let fb = case config.show_feedback, choice.feedback {
      True, Some(f) -> " — " <> f
      _, _ -> ""
    }
    acc <> "\n   " <> marker <> " " <> choice.text <> correct_mark <> weight_mark <> fb
  })
}

fn serialize_short_answer(
  choices: List(Choice),
  config: SerializerConfig,
) -> String {
  case config.show_correct_answers {
    True -> {
      let answers =
        list.map(choices, fn(c) { c.text })
        |> string.join(", ")
      "\n   Ответ: " <> answers
    }
    False -> "\n   [Короткий ответ]"
  }
}

fn serialize_matching(
  pairs: List(MatchPair),
  config: SerializerConfig,
) -> String {
  let indexed =
    list.index_map(pairs, fn(pair, i) { #(i, pair) })
  list.fold(indexed, "", fn(acc, item) {
    let #(i, pair) = item
    let marker = choice_marker(i, config.choice_style)
    case config.show_correct_answers {
      True ->
        acc <> "\n   " <> marker <> " " <> pair.subquestion <> " → " <> pair.subanswer
      False ->
        acc <> "\n   " <> marker <> " " <> pair.subquestion <> " → ?"
    }
  })
}

fn serialize_numerical(
  choices: List(NumericalChoice),
  config: SerializerConfig,
) -> String {
  case config.show_correct_answers {
    True ->
      list.fold(choices, "", fn(acc, nc) {
        let answer_text = case nc.answer {
          SimpleNumber(v) -> float_to_string(v)
          Range(v, t) ->
            float_to_string(v) <> " ± " <> float_to_string(t)
          HighLow(l, h) ->
            float_to_string(l) <> " .. " <> float_to_string(h)
        }
        let fb = case config.show_feedback, nc.feedback {
          True, Some(f) -> " — " <> f
          _, _ -> ""
        }
        acc <> "\n   Ответ: " <> answer_text <> fb
      })
    False -> "\n   [Числовой ответ]"
  }
}

fn choice_marker(index: Int, style: ChoiceStyle) -> String {
  case style {
    Letters ->
      case index {
        0 -> "A)"
        1 -> "B)"
        2 -> "C)"
        3 -> "D)"
        4 -> "E)"
        5 -> "F)"
        6 -> "G)"
        7 -> "H)"
        _ -> int_to_string(index + 1) <> ")"
      }
    Numbers -> int_to_string(index + 1) <> ")"
    Bullets -> "•"
  }
}

fn float_to_string(f: Float) -> String {
  let s = float.to_string(f)
  case string.ends_with(s, ".0") {
    True -> string.drop_end(s, 2)
    False -> s
  }
}

fn int_to_string(n: Int) -> String {
  case n {
    0 -> "0"
    _ -> do_int_to_string(n, "")
  }
}

fn do_int_to_string(n: Int, acc: String) -> String {
  case n {
    0 -> acc
    _ -> {
      let digit = n % 10
      let char = case digit {
        0 -> "0"
        1 -> "1"
        2 -> "2"
        3 -> "3"
        4 -> "4"
        5 -> "5"
        6 -> "6"
        7 -> "7"
        8 -> "8"
        9 -> "9"
        _ -> "?"
      }
      do_int_to_string(n / 10, char <> acc)
    }
  }
}
