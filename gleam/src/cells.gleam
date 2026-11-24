import cells/cell_ref.{type CellRef}
import cells/sheet.{
  type Sheet, type Value, CircularRef, DivByZero, Failed, Number, ParseError,
  Text, TypeError,
}
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

// --- Types ---

type Model {
  Model(sheet: Sheet, editor: Option(Editor))
}

type Editor {
  Editor(ref: CellRef, text: String)
}

type Direction {
  Forward
  Backward
}

/// What happens to the editor's text when the editor closes.
type Closing {
  Commit
  Discard
}

type Msg {
  UserDoubleClickedCell(CellRef)
  UserClickedCell
  UserUpdatedFormula(String)
  UserFinishedEditing
  UserCancelledEditing
  UserPressedTab(Direction)
  /// Carries the cell of the input that lost focus: the input of a cell that
  /// has already been left (e.g. via Tab) must not close its successor.
  UserBlurredEditor(CellRef)
}

// --- Main / Init ---

pub fn main() {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)

  Nil
}

fn init(_: flags) -> #(Model, Effect(Msg)) {
  #(Model(sheet: sheet.new(), editor: None), effect.none())
}

// --- FFI ---

fn focus_editor() -> Effect(Msg) {
  effect.from(fn(_) { do_focus_cell_editor() })
}

@external(javascript, "./cells.ffi.mjs", "focus_cell_editor")
fn do_focus_cell_editor() -> Nil

// --- Update ---

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    UserDoubleClickedCell(ref) -> #(
      model |> close_editor(Commit) |> open_editor(ref),
      focus_editor(),
    )

    UserClickedCell -> #(close_editor(model, Commit), effect.none())

    UserUpdatedFormula(text) -> {
      let editor =
        option.map(model.editor, fn(editor) { Editor(..editor, text:) })
      #(Model(..model, editor:), effect.none())
    }

    UserFinishedEditing -> #(close_editor(model, Commit), effect.none())

    UserCancelledEditing -> #(close_editor(model, Discard), effect.none())

    UserBlurredEditor(ref) ->
      case model.editor {
        Some(Editor(ref: editing, ..)) if editing == ref -> #(
          close_editor(model, Commit),
          effect.none(),
        )
        _ -> #(model, effect.none())
      }

    UserPressedTab(direction) ->
      case model.editor {
        None -> #(model, effect.none())
        Some(editor) -> {
          let target = case direction {
            Forward -> cell_ref.next(editor.ref)
            Backward -> cell_ref.previous(editor.ref)
          }

          #(
            model |> close_editor(Commit) |> open_editor(target),
            focus_editor(),
          )
        }
      }
  }
}

fn open_editor(model: Model, ref: CellRef) -> Model {
  Model(..model, editor: Some(Editor(ref:, text: sheet.raw(model.sheet, ref))))
}

fn close_editor(model: Model, closing: Closing) -> Model {
  case model.editor, closing {
    Some(Editor(ref:, text:)), Commit ->
      Model(sheet: sheet.set(model.sheet, ref, text), editor: None)
    None, _ | Some(_), Discard -> Model(..model, editor: None)
  }
}

// --- View ---

fn view(model: Model) -> Element(Msg) {
  html.div(
    [
      attribute.styles([
        #("width", "100%"),
        #("height", "calc(100vh - 2rem)"),
        #("overflow", "auto"),
        #("font-family", "monospace"),
        #("font-size", "13px"),
      ]),
    ],
    [
      html.table(
        [
          attribute.styles([
            #("border-collapse", "collapse"),
            #("table-layout", "fixed"),
          ]),
        ],
        [view_header(), view_body(model)],
      ),
    ],
  )
}

fn view_header() -> Element(Msg) {
  let cols =
    cell_ref.column_names()
    |> list.map(fn(name) {
      html.th(
        [
          attribute.styles([
            #("border", "1px solid #ccc"),
            #("background", "#f0f0f0"),
            #("padding", "2px 4px"),
            #("width", "80px"),
            #("min-width", "80px"),
            #("position", "sticky"),
            #("top", "0"),
            #("z-index", "2"),
          ]),
        ],
        [html.text(name)],
      )
    })

  html.thead([], [
    html.tr([], [
      html.th(
        [
          attribute.styles([
            #("border", "1px solid #ccc"),
            #("background", "#e0e0e0"),
            #("padding", "2px 4px"),
            #("width", "30px"),
            #("min-width", "30px"),
            #("position", "sticky"),
            #("top", "0"),
            #("left", "0"),
            #("z-index", "3"),
          ]),
        ],
        [],
      ),
      ..cols
    ]),
  ])
}

fn view_body(model: Model) -> Element(Msg) {
  let rows = cell_ref.rows() |> list.map(view_row(model, _))

  html.tbody([], rows)
}

fn view_row(model: Model, row: cell_ref.Row) -> Element(Msg) {
  let cells = list.map(row.cells, view_cell(model, _))

  html.tr([], [
    html.td(
      [
        attribute.styles([
          #("border", "1px solid #ccc"),
          #("background", "#f0f0f0"),
          #("padding", "2px 4px"),
          #("text-align", "center"),
          #("position", "sticky"),
          #("left", "0"),
          #("z-index", "1"),
        ]),
      ],
      [html.text(row.name)],
    ),
    ..cells
  ])
}

fn view_cell(model: Model, ref: CellRef) -> Element(Msg) {
  case model.editor {
    Some(Editor(ref: editing, text:)) if editing == ref ->
      view_cell_editing(ref, text)
    _ -> view_cell_display(sheet.value(model.sheet, ref), ref)
  }
}

fn view_cell_editing(ref: CellRef, text: String) -> Element(Msg) {
  html.td(
    [
      attribute.styles([
        #("border", "1px solid #4a90d9"),
        #("padding", "0"),
      ]),
    ],
    [
      html.input([
        attribute.id("cell-editor"),
        attribute.value(text),
        attribute.styles([
          #("width", "100%"),
          #("height", "100%"),
          #("border", "none"),
          #("outline", "none"),
          #("padding", "2px 4px"),
          #("font-family", "monospace"),
          #("font-size", "13px"),
          #("box-sizing", "border-box"),
        ]),
        event.on_input(UserUpdatedFormula),
        event.on_blur(UserBlurredEditor(ref)),
        handle_editor_keydown(),
      ]),
    ],
  )
}

fn view_cell_display(value: Option(Value), ref: CellRef) -> Element(Msg) {
  let #(display, styles) = format_value(value)

  html.td(
    [
      attribute.styles([
        #("border", "1px solid #ccc"),
        #("padding", "2px 4px"),
        #("overflow", "hidden"),
        #("white-space", "nowrap"),
        #("text-overflow", "ellipsis"),
        #("cursor", "default"),
        #("height", "20px"),
        ..styles
      ]),
      event.on("dblclick", decode.success(UserDoubleClickedCell(ref))),
      event.on("mousedown", decode.success(UserClickedCell)),
    ],
    [html.text(display)],
  )
}

fn format_value(value: Option(Value)) -> #(String, List(#(String, String))) {
  case value {
    None -> #("", [])
    Some(Number(n)) -> #(format_number(n), [#("text-align", "right")])
    Some(Text(s)) -> #(s, [])
    Some(Failed(CircularRef)) -> #("#CIRC", [#("color", "red")])
    Some(Failed(DivByZero)) -> #("#DIV/0", [#("color", "red")])
    Some(Failed(TypeError)) -> #("#TYPE", [#("color", "red")])
    Some(Failed(ParseError)) -> #("#ERR", [#("color", "red")])
  }
}

/// Rounds to two decimals and drops a zero fraction, so values read `0.3` and
/// `3` rather than `0.30000000000000004` and `3.0`. Only the display is
/// rounded; dependent cells compute with the exact value.
fn format_number(n: Float) -> String {
  let rounded = float.to_precision(n, 2)
  let whole = float.truncate(rounded)

  case int.to_float(whole) == rounded {
    True -> int.to_string(whole)
    False -> float.to_string(rounded)
  }
}

fn handle_editor_keydown() -> attribute.Attribute(Msg) {
  event.advanced("keydown", {
    use key <- decode.field("key", decode.string)
    use shift <- decode.field("shiftKey", decode.bool)
    let handle = fn(msg) {
      decode.success(event.handler(
        msg,
        prevent_default: True,
        stop_propagation: True,
      ))
    }

    case key {
      "Enter" -> handle(UserFinishedEditing)
      "Escape" -> handle(UserCancelledEditing)
      "Tab" if shift -> handle(UserPressedTab(Backward))
      "Tab" -> handle(UserPressedTab(Forward))
      _ ->
        decode.failure(
          event.handler(
            UserFinishedEditing,
            prevent_default: False,
            stop_propagation: False,
          ),
          "unhandled key",
        )
    }
  })
}
