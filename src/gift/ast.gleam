pub type GiftDocument {
  GiftDocument(items: List(GiftItem))
}

pub type GiftItem {
  Category(name: String)
  Question(data: QuestionData)
}

pub type QuestionData {
  QuestionData(
    title: Option(String),
    stem: RichText,
    answers: AnswerType,
    global_feedback: Option(RichText),
    has_embedded_answers: Bool,
  )
}

pub type AnswerType {
  Description
  Essay
  TrueFalse(is_true: Bool, true_feedback: Option(String), false_feedback: Option(String))
  MultipleChoice(choices: List(Choice))
  ShortAnswer(choices: List(Choice))
  Matching(pairs: List(MatchPair))
  Numerical(choices: List(NumericalChoice))
}

pub type Choice {
  Choice(
    is_correct: Bool,
    text: String,
    weight: Option(Float),
    feedback: Option(String),
  )
}

pub type MatchPair {
  MatchPair(subquestion: String, subanswer: String)
}

pub type NumericalChoice {
  NumericalChoice(
    answer: NumericalAnswer,
    weight: Option(Float),
    feedback: Option(String),
  )
}

pub type NumericalAnswer {
  SimpleNumber(value: Float)
  Range(value: Float, tolerance: Float)
  HighLow(low: Float, high: Float)
}

pub type RichText {
  RichText(format: TextFormat, text: String)
}

pub type TextFormat {
  Html
  Markdown
  Plain
  Moodle
}

pub type Option(a) {
  Some(a)
  None
}
