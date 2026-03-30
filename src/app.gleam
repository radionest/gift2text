import gift/ast.{type Option, None, Some}
import gift/parser
import gift/serializer.{type SerializerConfig, SerializerConfig}
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub type Model {
  Model(
    input: String,
    config: SerializerConfig,
    result: Option(Result(String, String)),
    copied: Bool,
  )
}

pub type Msg {
  InputChanged(String)
  ToggleCorrectAnswers(Bool)
  Convert
  CopyResult
  Copied
  CopyFailed
}

fn init(_flags) -> #(Model, Effect(Msg)) {
  #(
    Model(
      input: "",
      config: serializer.default_config(),
      result: None,
      copied: False,
    ),
    effect.none(),
  )
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    InputChanged(text) -> #(Model(..model, input: text, copied: False), effect.none())
    ToggleCorrectAnswers(v) -> #(
      Model(
        ..model,
        config: SerializerConfig(..model.config, show_correct_answers: v),
      ),
      effect.none(),
    )
    Convert -> {
      let result = case parser.parse(model.input) {
        Ok(doc) -> {
          let text = serializer.serialize(doc, model.config)
          case text {
            "" ->
              Error(
                "Не удалось распознать ни одного вопроса в GIFT тексте. Проверьте формат ввода.",
              )
            _ -> Ok(text)
          }
        }
        Error(e) -> Error(e)
      }
      #(Model(..model, result: Some(result), copied: False), effect.none())
    }
    CopyResult -> {
      case model.result {
        Some(Ok(text)) -> #(model, copy_to_clipboard(text))
        _ -> #(model, effect.none())
      }
    }
    Copied -> #(Model(..model, copied: True), effect.none())
    CopyFailed -> #(model, effect.none())
  }
}

@external(javascript, "./clipboard_ffi.mjs", "copyToClipboard")
fn do_copy(text: String, on_success: fn() -> Nil, on_failure: fn() -> Nil) -> Nil

fn copy_to_clipboard(text: String) -> Effect(Msg) {
  effect.from(fn(dispatch) {
    do_copy(
      text,
      fn() { dispatch(Copied) },
      fn() { dispatch(CopyFailed) },
    )
  })
}

fn view(model: Model) -> Element(Msg) {
  html.div([attribute.class("app")], [
    html.div([attribute.class("toolbar")], [
      html.h1([], [element.text("GIFT → Текст")]),
      html.div([attribute.class("toolbar-controls")], [
        html.label([attribute.class("checkbox-label")], [
          html.input([
            attribute.type_("checkbox"),
            attribute.checked(model.config.show_correct_answers),
            event.on_check(ToggleCorrectAnswers),
          ]),
          element.text(" Показывать правильные ответы"),
        ]),
        html.button(
          [attribute.class("convert-btn"), event.on_click(Convert)],
          [element.text("Конвертировать")],
        ),
      ]),
    ]),
    html.div([attribute.class("main")], [
      html.div([attribute.class("panel")], [
        html.div([attribute.class("panel-header")], [
          html.h2([], [element.text("GIFT текст")]),
        ]),
        html.textarea(
          [
            attribute.class("text-area"),
            attribute.placeholder("Вставьте GIFT текст сюда..."),
            attribute.value(model.input),
            event.on_input(InputChanged),
          ],
          "",
        ),
      ]),
      html.div([attribute.class("panel")], [
        html.div([attribute.class("panel-header")], [
          html.h2([], [element.text("Результат")]),
          view_copy_button(model),
        ]),
        view_result(model.result),
      ]),
    ]),
  ])
}

fn view_copy_button(model: Model) -> Element(Msg) {
  case model.result {
    Some(Ok(_)) ->
      html.button(
        [attribute.class("copy-btn"), event.on_click(CopyResult)],
        [
          element.text(case model.copied {
            True -> "✓ Скопировано"
            False -> "Копировать"
          }),
        ],
      )
    _ -> element.none()
  }
}

fn view_result(result: Option(Result(String, String))) -> Element(Msg) {
  case result {
    None ->
      html.p([attribute.class("placeholder-text")], [
        element.text("Результат появится здесь после конвертации"),
      ])
    Some(Ok(text)) ->
      html.textarea(
        [
          attribute.class("text-area output-area"),
          attribute.readonly(True),
        ],
        text,
      )
    Some(Error(err)) ->
      html.div([attribute.class("error")], [
        html.p([], [element.text("Ошибка: " <> err)]),
      ])
  }
}

pub fn main() {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}
