import gift/ast.{
  Category, Description, Essay,
  Matching, MultipleChoice, Numerical, Question, ShortAnswer, Some, TrueFalse,
}
import gift/parser
import gift/serializer
import gleam/list
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn parse_simple_mc_test() {
  let input = "::Sample:: What is 2+2? {=4 ~3 ~5 ~6}"
  let assert Ok(doc) = parser.parse(input)
  let assert [Question(q)] = doc.items
  let assert Some("Sample") = q.title
  let assert MultipleChoice(choices) = q.answers
  should.equal(list.length(choices), 4)
  let assert [c1, ..] = choices
  should.be_true(c1.is_correct)
  should.equal(c1.text, "4")
}

pub fn parse_true_false_test() {
  let input = "The earth is round. {T}"
  let assert Ok(doc) = parser.parse(input)
  let assert [Question(q)] = doc.items
  let assert TrueFalse(is_true, _, _) = q.answers
  should.be_true(is_true)
}

pub fn parse_essay_test() {
  let input = "Write an essay about climate change. {}"
  let assert Ok(doc) = parser.parse(input)
  let assert [Question(q)] = doc.items
  let assert Essay = q.answers
}

pub fn parse_short_answer_test() {
  let input = "Who painted the Mona Lisa? {=Leonardo da Vinci =da Vinci}"
  let assert Ok(doc) = parser.parse(input)
  let assert [Question(q)] = doc.items
  let assert ShortAnswer(choices) = q.answers
  should.equal(list.length(choices), 2)
}

pub fn parse_matching_test() {
  let input =
    "Match the capitals. {=France -> Paris =Germany -> Berlin =Italy -> Rome}"
  let assert Ok(doc) = parser.parse(input)
  let assert [Question(q)] = doc.items
  let assert Matching(pairs) = q.answers
  should.equal(list.length(pairs), 3)
  let assert [p1, ..] = pairs
  should.equal(p1.subquestion, "France")
  should.equal(p1.subanswer, "Paris")
}

pub fn parse_numerical_test() {
  let input = "What is pi? {#3.14:0.01}"
  let assert Ok(doc) = parser.parse(input)
  let assert [Question(q)] = doc.items
  let assert Numerical(choices) = q.answers
  should.equal(list.length(choices), 1)
}

pub fn parse_category_test() {
  let input = "$CATEGORY: $course$/Math\n\nWhat is 1+1? {=2 ~3}"
  let assert Ok(doc) = parser.parse(input)
  let assert [Category(name), Question(_)] = doc.items
  should.equal(name, "Math")
}

pub fn parse_description_test() {
  let input = "This is just a description with no question."
  let assert Ok(doc) = parser.parse(input)
  let assert [Question(q)] = doc.items
  let assert Description = q.answers
}

pub fn parse_comment_skipped_test() {
  let input = "// This is a comment\n\nWhat is 1+1? {=2 ~3}"
  let assert Ok(doc) = parser.parse(input)
  should.equal(list.length(doc.items), 1)
}

pub fn parse_feedback_test() {
  let input = "What color is the sky? {=Blue#Correct! ~Red#Wrong ~Green#Nope}"
  let assert Ok(doc) = parser.parse(input)
  let assert [Question(q)] = doc.items
  let assert MultipleChoice(choices) = q.answers
  let assert [c1, ..] = choices
  should.equal(c1.feedback, Some("Correct!"))
}

pub fn parse_multiple_questions_test() {
  let input =
    "Q1 {T}\n\nQ2 {F}\n\n::Title:: Q3 {=yes ~no}"
  let assert Ok(doc) = parser.parse(input)
  should.equal(list.length(doc.items), 3)
}

pub fn parse_multiline_moodle_question_test() {
  let input =
    "// question: 123  name: Test\n::Test::Test{\n\t=correct\n\t~wrong\n}"
  let assert Ok(doc) = parser.parse(input)
  let assert [Question(q)] = doc.items
  let assert Some("Test") = q.title
  let assert MultipleChoice(choices) = q.answers
  should.equal(list.length(choices), 2)
}

pub fn parse_moodle_export_with_comments_test() {
  let input =
    "// comment line\n$CATEGORY: $course$/Science\n\n// another comment\n::Q1:: What is H2O? {=Water ~Fire}\n\n// wrapped\n// category comment\n$CATEGORY: $course$/Very Long\nCategory Name\n\n// standalone comment"
  let assert Ok(doc) = parser.parse(input)
  let assert [Category(cat1), Question(q), Category(cat2)] = doc.items
  should.equal(cat1, "Science")
  should.equal(q.title, Some("Q1"))
  let assert MultipleChoice(_) = q.answers
  should.equal(cat2, "Very Long Category Name")
}

pub fn serialize_basic_test() {
  let input = "::Sample:: What is 2+2? {=4 ~3 ~5 ~6}"
  let assert Ok(doc) = parser.parse(input)
  let config = serializer.default_config()
  let output = serializer.serialize(doc, config)
  should.be_true(string.contains(output, "Sample"))
  should.be_true(string.contains(output, "2+2"))
  should.be_true(string.contains(output, "4"))
}

pub fn parse_moodle_cyrillic_export_test() {
  let input =
    "// question: 0  name: Switch category to $course$/Тестовая категория/Подкатегория
$CATEGORY: $course$/Тестовая категория/Подкатегория


// question: 12345  name: Вопрос по теме
::Вопрос по теме::[html]<p>Какой из вариантов является правильным?</p>{
\t~%0%<p>Неправильный ответ</p>
\t=%100%<p>Правильный ответ</p>#<p>Верно!</p>
\t~%0%<p>Ещё неправильный</p>
}"
  let assert Ok(doc) = parser.parse(input)
  let assert [Category(cat), Question(q)] = doc.items
  should.equal(cat, "Тестовая категория/Подкатегория")
  should.equal(q.title, Some("Вопрос по теме"))
  let assert MultipleChoice(choices) = q.answers
  should.equal(list.length(choices), 3)
  let assert [c1, c2, c3] = choices
  should.be_false(c1.is_correct)
  should.be_true(c2.is_correct)
  should.be_false(c3.is_correct)
}

pub fn serialize_no_numbers_test() {
  let input = "What is 1+1? {=2 ~3}"
  let assert Ok(doc) = parser.parse(input)
  let config =
    serializer.SerializerConfig(
      ..serializer.default_config(),
      number_questions: False,
    )
  let output = serializer.serialize(doc, config)
  should.be_false(string.contains(output, "1."))
}
