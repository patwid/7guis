import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set.{type Set}
import gleam/string
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

const num_cols = 26

const num_rows = 100

// --- Types ---

/// A cell coordinate. Only construct through `cell_ref`, which guarantees
/// the coordinate lies within the sheet.
type CellRef {
  CellRef(col: Int, row: Int)
}

/// What the user entered into a cell, after parsing.
type Content {
  Blank
  Number(Float)
  Text(String)
  Formula(Expr)
  Malformed
}

/// The expression of a formula (the part after `=`).
type Expr {
  Literal(Float)
  Ref(CellRef)
  Call(Function, List(Arg))
}

/// A function argument. Ranges are only meaningful as arguments, so they are
/// not an `Expr`.
type Arg {
  Single(Expr)
  Range(CellRef, CellRef)
}

type Function {
  Add
  Sub
  Mul
  Div
  Mod
  Sum
  Prod
}

type Value {
  VEmpty
  VNumber(Float)
  VText(String)
  VError(CellError)
}

type CellError {
  ParseError
  CircularRef
  TypeError
  DivByZero
}

/// A non-blank cell. `value` is a cache of evaluating `content`, kept up to
/// date by `recalculate`.
type Cell {
  Cell(raw: String, content: Content, value: Value)
}

type Model {
  Model(cells: Dict(CellRef, Cell), editor: Option(Editor))
}

type Editor {
  Editor(ref: CellRef, text: String)
}

type Direction {
  Forward
  Backward
}

type Msg {
  UserDoubleClickedCell(CellRef)
  UserClickedCell
  UserUpdatedFormula(String)
  UserFinishedEditing
  UserCancelledEditing
  UserPressedTab(Direction)
}

fn cell_ref(col: Int, row: Int) -> Result(CellRef, Nil) {
  case col >= 0 && col < num_cols && row >= 0 && row < num_rows {
    True -> Ok(CellRef(col:, row:))
    False -> Error(Nil)
  }
}

// --- Main / Init ---

pub fn main() {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)

  Nil
}

fn init(_: flags) -> #(Model, Effect(Msg)) {
  #(Model(cells: dict.new(), editor: None), effect.none())
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
      model |> close_editor(commit: True) |> open_editor(ref),
      focus_editor(),
    )

    UserClickedCell -> #(close_editor(model, commit: True), effect.none())

    UserUpdatedFormula(text) -> {
      let editor =
        option.map(model.editor, fn(editor) { Editor(..editor, text:) })
      #(Model(..model, editor:), effect.none())
    }

    UserFinishedEditing -> #(close_editor(model, commit: True), effect.none())

    UserCancelledEditing -> #(close_editor(model, commit: False), effect.none())

    UserPressedTab(direction) ->
      case model.editor {
        None -> #(model, effect.none())
        Some(editor) -> #(
          model
            |> close_editor(commit: True)
            |> open_editor(next_cell(editor.ref, direction)),
          focus_editor(),
        )
      }
  }
}

fn open_editor(model: Model, ref: CellRef) -> Model {
  let text = case dict.get(model.cells, ref) {
    Ok(cell) -> cell.raw
    Error(_) -> ""
  }

  Model(..model, editor: Some(Editor(ref:, text:)))
}

fn close_editor(model: Model, commit commit: Bool) -> Model {
  case model.editor, commit {
    Some(Editor(ref:, text:)), True ->
      Model(cells: set_cell(model.cells, ref, text), editor: None)
    _, _ -> Model(..model, editor: None)
  }
}

/// Moves through the sheet in row-major order, wrapping around at the ends.
fn next_cell(ref: CellRef, direction: Direction) -> CellRef {
  let total = num_cols * num_rows
  let index = ref.row * num_cols + ref.col
  let next = case direction {
    Forward -> { index + 1 } % total
    Backward -> { index - 1 + total } % total
  }

  CellRef(col: next % num_cols, row: next / num_cols)
}

// --- Sheet ---

fn set_cell(cells: Dict(CellRef, Cell), ref: CellRef, raw: String) {
  let cells = case parse_content(raw) {
    Blank -> dict.delete(cells, ref)
    content -> dict.insert(cells, ref, Cell(raw:, content:, value: VEmpty))
  }

  recalculate(cells, ref)
}

fn lookup(cells: Dict(CellRef, Cell), ref: CellRef) -> Value {
  case dict.get(cells, ref) {
    Ok(cell) -> cell.value
    Error(_) -> VEmpty
  }
}

/// Re-evaluates `changed` and every cell that (transitively) depends on it.
/// Cells on a reference cycle evaluate to `CircularRef`; cells depending on
/// them pick that error up through normal evaluation.
fn recalculate(cells: Dict(CellRef, Cell), changed: CellRef) {
  let deps = dependencies(cells)
  let affected =
    collect_dependents(changed, invert(deps), set.from_list([changed]))
  let circular =
    set.filter(affected, fn(ref) { has_cycle(ref, deps_of(deps, ref), deps) })

  let cells =
    set.fold(circular, cells, fn(cells, ref) {
      set_value(cells, ref, fn(_) { VError(CircularRef) })
    })

  set.difference(affected, circular)
  |> topological_order(deps)
  |> list.fold(cells, fn(cells, ref) {
    set_value(cells, ref, fn(content) { evaluate(content, cells) })
  })
}

fn set_value(
  cells: Dict(CellRef, Cell),
  ref: CellRef,
  value: fn(Content) -> Value,
) -> Dict(CellRef, Cell) {
  case dict.get(cells, ref) {
    Ok(cell) ->
      dict.insert(cells, ref, Cell(..cell, value: value(cell.content)))
    Error(_) -> cells
  }
}

// --- Dependency Graph ---

/// For every cell, the cells it references.
fn dependencies(cells: Dict(CellRef, Cell)) -> Dict(CellRef, Set(CellRef)) {
  dict.map_values(cells, fn(_, cell) { content_refs(cell.content) })
}

fn deps_of(deps: Dict(CellRef, Set(CellRef)), ref: CellRef) -> Set(CellRef) {
  dict.get(deps, ref) |> result.unwrap(set.new())
}

fn content_refs(content: Content) -> Set(CellRef) {
  case content {
    Formula(expr) -> expr_refs(expr)
    Blank | Number(_) | Text(_) | Malformed -> set.new()
  }
}

fn expr_refs(expr: Expr) -> Set(CellRef) {
  case expr {
    Literal(_) -> set.new()
    Ref(ref) -> set.from_list([ref])
    Call(_, args) ->
      list.fold(args, set.new(), fn(acc, arg) {
        case arg {
          Single(expr) -> set.union(acc, expr_refs(expr))
          Range(from, to) ->
            set.union(acc, set.from_list(expand_range(from, to)))
        }
      })
  }
}

fn expand_range(from: CellRef, to: CellRef) -> List(CellRef) {
  let min_col = int.min(from.col, to.col)
  let max_col = int.max(from.col, to.col)
  let min_row = int.min(from.row, to.row)
  let max_row = int.max(from.row, to.row)

  list.flat_map(list.range(min_col, max_col), fn(col) {
    list.map(list.range(min_row, max_row), fn(row) { CellRef(col, row) })
  })
}

/// For every cell, the cells referencing it.
fn invert(deps: Dict(CellRef, Set(CellRef))) -> Dict(CellRef, Set(CellRef)) {
  dict.fold(deps, dict.new(), fn(reverse, cell, cell_deps) {
    set.fold(cell_deps, reverse, fn(reverse, dep) {
      dict.upsert(reverse, dep, fn(existing) {
        existing |> option.unwrap(set.new()) |> set.insert(cell)
      })
    })
  })
}

fn collect_dependents(
  ref: CellRef,
  reverse: Dict(CellRef, Set(CellRef)),
  visited: Set(CellRef),
) -> Set(CellRef) {
  set.fold(deps_of(reverse, ref), visited, fn(visited, dep) {
    case set.contains(visited, dep) {
      True -> visited
      False -> collect_dependents(dep, reverse, set.insert(visited, dep))
    }
  })
}

/// Whether `target` is reachable from `refs`, i.e. lies on a cycle.
fn has_cycle(
  target: CellRef,
  refs: Set(CellRef),
  deps: Dict(CellRef, Set(CellRef)),
) -> Bool {
  has_cycle_loop(target, set.to_list(refs), deps, set.new())
}

fn has_cycle_loop(
  target: CellRef,
  stack: List(CellRef),
  deps: Dict(CellRef, Set(CellRef)),
  visited: Set(CellRef),
) -> Bool {
  case stack {
    [] -> False
    [ref, ..] if ref == target -> True
    [ref, ..rest] ->
      case set.contains(visited, ref) {
        True -> has_cycle_loop(target, rest, deps, visited)
        False ->
          has_cycle_loop(
            target,
            list.append(set.to_list(deps_of(deps, ref)), rest),
            deps,
            set.insert(visited, ref),
          )
      }
  }
}

/// Orders `cells` so that each cell comes after the cells it depends on.
/// Dependencies outside `cells` are ignored; `cells` must be acyclic.
fn topological_order(
  cells: Set(CellRef),
  deps: Dict(CellRef, Set(CellRef)),
) -> List(CellRef) {
  let #(order, _) =
    set.fold(cells, #([], set.new()), fn(acc, ref) {
      visit(ref, cells, deps, acc)
    })

  list.reverse(order)
}

fn visit(
  ref: CellRef,
  cells: Set(CellRef),
  deps: Dict(CellRef, Set(CellRef)),
  acc: #(List(CellRef), Set(CellRef)),
) -> #(List(CellRef), Set(CellRef)) {
  let #(order, seen) = acc
  case set.contains(seen, ref) || !set.contains(cells, ref) {
    True -> acc
    False -> {
      let #(order, seen) =
        set.fold(
          deps_of(deps, ref),
          #(order, set.insert(seen, ref)),
          fn(acc, dep) { visit(dep, cells, deps, acc) },
        )
      #([ref, ..order], seen)
    }
  }
}

// --- Parser ---

fn parse_content(raw: String) -> Content {
  case string.trim(raw) {
    "" -> Blank
    "=" <> formula ->
      case parse_formula(formula) {
        Ok(expr) -> Formula(expr)
        Error(_) -> Malformed
      }
    text ->
      case parse_number(text) {
        Ok(n) -> Number(n)
        Error(_) -> Text(text)
      }
  }
}

fn parse_number(text: String) -> Result(Float, Nil) {
  float.parse(text)
  |> result.lazy_or(fn() { int.parse(text) |> result.map(int.to_float) })
}

/// Parses a whole formula; trailing input is an error.
fn parse_formula(input: String) -> Result(Expr, Nil) {
  use #(expr, rest) <- result.try(parse_expr(input))
  case string.trim(rest) {
    "" -> Ok(expr)
    _ -> Error(Nil)
  }
}

fn parse_expr(input: String) -> Result(#(Expr, String), Nil) {
  let input = string.trim_start(input)
  let first = string.first(input) |> result.unwrap("")

  case
    is_digit(first) || first == "-" || first == ".",
    is_upper(first),
    is_lower(first)
  {
    True, _, _ -> parse_literal(input)
    _, True, _ ->
      parse_cell_ref(input) |> result.map(fn(p) { #(Ref(p.0), p.1) })
    _, _, True -> parse_call(input)
    _, _, _ -> Error(Nil)
  }
}

fn parse_literal(input: String) -> Result(#(Expr, String), Nil) {
  let #(sign, rest) = case input {
    "-" <> rest -> #("-", rest)
    _ -> #("", input)
  }
  let #(digits, rest) = take_while(rest, fn(ch) { is_digit(ch) || ch == "." })

  parse_number(sign <> digits) |> result.map(fn(n) { #(Literal(n), rest) })
}

fn parse_cell_ref(input: String) -> Result(#(CellRef, String), Nil) {
  use #(letter, rest) <- result.try(string.pop_grapheme(input))
  use col <- result.try(column_from_letter(letter))
  let #(digits, rest) = take_while(rest, is_digit)
  use row <- result.try(int.parse(digits))
  use ref <- result.try(cell_ref(col, row))
  Ok(#(ref, rest))
}

fn parse_call(input: String) -> Result(#(Expr, String), Nil) {
  let #(name, rest) = take_while(input, fn(ch) { is_lower(ch) || is_upper(ch) })
  use function <- result.try(function_from_name(name))
  use rest <- result.try(expect(rest, "("))
  use #(args, rest) <- result.try(parse_args(rest))
  use rest <- result.try(expect(rest, ")"))
  Ok(#(Call(function, args), rest))
}

fn function_from_name(name: String) -> Result(Function, Nil) {
  case name {
    "add" -> Ok(Add)
    "sub" -> Ok(Sub)
    "mul" -> Ok(Mul)
    "div" -> Ok(Div)
    "mod" -> Ok(Mod)
    "sum" -> Ok(Sum)
    "prod" -> Ok(Prod)
    _ -> Error(Nil)
  }
}

fn parse_args(input: String) -> Result(#(List(Arg), String), Nil) {
  case string.trim_start(input) {
    ")" <> _ -> Ok(#([], input))
    _ -> parse_args_loop(input, [])
  }
}

fn parse_args_loop(
  input: String,
  acc: List(Arg),
) -> Result(#(List(Arg), String), Nil) {
  use #(arg, rest) <- result.try(parse_arg(input))
  let acc = [arg, ..acc]
  case string.trim_start(rest) {
    "," <> rest -> parse_args_loop(rest, acc)
    rest -> Ok(#(list.reverse(acc), rest))
  }
}

fn parse_arg(input: String) -> Result(#(Arg, String), Nil) {
  let input = string.trim_start(input)
  case parse_cell_ref(input) {
    Ok(#(from, rest)) ->
      case string.trim_start(rest) {
        ":" <> rest -> {
          use #(to, rest) <- result.try(parse_cell_ref(string.trim_start(rest)))
          Ok(#(Range(from, to), rest))
        }
        _ -> Ok(#(Single(Ref(from)), rest))
      }
    Error(_) -> parse_expr(input) |> result.map(fn(p) { #(Single(p.0), p.1) })
  }
}

// --- Parser Helpers ---

fn expect(input: String, token: String) -> Result(String, Nil) {
  let input = string.trim_start(input)
  case string.starts_with(input, token) {
    True -> Ok(string.drop_start(input, string.length(token)))
    False -> Error(Nil)
  }
}

fn take_while(
  input: String,
  predicate: fn(String) -> Bool,
) -> #(String, String) {
  take_while_loop(input, predicate, "")
}

fn take_while_loop(
  input: String,
  predicate: fn(String) -> Bool,
  acc: String,
) -> #(String, String) {
  case string.pop_grapheme(input) {
    Ok(#(ch, rest)) ->
      case predicate(ch) {
        True -> take_while_loop(rest, predicate, acc <> ch)
        False -> #(acc, input)
      }
    Error(_) -> #(acc, input)
  }
}

fn is_digit(ch: String) -> Bool {
  case ch {
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    _ -> False
  }
}

fn is_upper(ch: String) -> Bool {
  case ascii_code(ch) {
    Ok(code) -> code >= 65 && code <= 90
    Error(_) -> False
  }
}

fn is_lower(ch: String) -> Bool {
  case ascii_code(ch) {
    Ok(code) -> code >= 97 && code <= 122
    Error(_) -> False
  }
}

fn ascii_code(ch: String) -> Result(Int, Nil) {
  case string.to_utf_codepoints(ch) {
    [codepoint] -> Ok(string.utf_codepoint_to_int(codepoint))
    _ -> Error(Nil)
  }
}

fn column_from_letter(ch: String) -> Result(Int, Nil) {
  case is_upper(ch), ascii_code(ch) {
    True, Ok(code) if code - 65 < num_cols -> Ok(code - 65)
    _, _ -> Error(Nil)
  }
}

fn column_to_letter(col: Int) -> String {
  let assert Ok(codepoint) = string.utf_codepoint(65 + col)
  string.from_utf_codepoints([codepoint])
}

// --- Evaluation ---

fn evaluate(content: Content, cells: Dict(CellRef, Cell)) -> Value {
  case content {
    Blank -> VEmpty
    Number(n) -> VNumber(n)
    Text(s) -> VText(s)
    Formula(expr) -> evaluate_expr(expr, cells)
    Malformed -> VError(ParseError)
  }
}

fn evaluate_expr(expr: Expr, cells: Dict(CellRef, Cell)) -> Value {
  case expr {
    Literal(n) -> VNumber(n)
    Ref(ref) -> lookup(cells, ref)
    Call(function, args) ->
      args
      |> list.flat_map(fn(arg) {
        case arg {
          Single(expr) -> [evaluate_expr(expr, cells)]
          Range(from, to) ->
            expand_range(from, to) |> list.map(lookup(cells, _))
        }
      })
      |> apply(function, _)
  }
}

fn apply(function: Function, values: List(Value)) -> Value {
  case function {
    Add -> binary_op(values, fn(a, b) { Ok(a +. b) })
    Sub -> binary_op(values, fn(a, b) { Ok(a -. b) })
    Mul -> binary_op(values, fn(a, b) { Ok(a *. b) })
    Div ->
      binary_op(values, fn(a, b) {
        float.divide(a, b) |> result.replace_error(DivByZero)
      })
    Mod ->
      binary_op(values, fn(a, b) {
        float.modulo(a, b) |> result.replace_error(DivByZero)
      })
    Sum -> aggregate_op(values, float.sum)
    Prod -> aggregate_op(values, float.product)
  }
}

fn coerce_number(value: Value) -> Result(Float, CellError) {
  case value {
    VEmpty -> Ok(0.0)
    VNumber(n) -> Ok(n)
    VText(_) -> Error(TypeError)
    VError(e) -> Error(e)
  }
}

fn binary_op(
  values: List(Value),
  op: fn(Float, Float) -> Result(Float, CellError),
) -> Value {
  case values {
    [a, b] -> {
      let result = {
        use a <- result.try(coerce_number(a))
        use b <- result.try(coerce_number(b))
        op(a, b)
      }
      case result {
        Ok(n) -> VNumber(n)
        Error(e) -> VError(e)
      }
    }
    _ -> VError(TypeError)
  }
}

fn aggregate_op(values: List(Value), op: fn(List(Float)) -> Float) -> Value {
  case list.try_map(values, coerce_number) {
    Ok(nums) -> VNumber(op(nums))
    Error(e) -> VError(e)
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
    list.range(0, num_cols - 1)
    |> list.map(fn(col) {
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
        [html.text(column_to_letter(col))],
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
  let rows =
    list.range(0, num_rows - 1)
    |> list.map(fn(row) { view_row(model, row) })

  html.tbody([], rows)
}

fn view_row(model: Model, row: Int) -> Element(Msg) {
  let cells =
    list.range(0, num_cols - 1)
    |> list.map(fn(col) { view_cell(model, CellRef(col, row)) })

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
      [html.text(int.to_string(row))],
    ),
    ..cells
  ])
}

fn view_cell(model: Model, ref: CellRef) -> Element(Msg) {
  case model.editor {
    Some(Editor(ref: editing, text:)) if editing == ref ->
      view_cell_editing(text)
    _ -> view_cell_display(lookup(model.cells, ref), ref)
  }
}

fn view_cell_editing(text: String) -> Element(Msg) {
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
        event.on_blur(UserFinishedEditing),
        handle_editor_keydown(),
      ]),
    ],
  )
}

fn view_cell_display(value: Value, ref: CellRef) -> Element(Msg) {
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

fn format_value(value: Value) -> #(String, List(#(String, String))) {
  case value {
    VEmpty -> #("", [])
    VNumber(n) -> #(format_number(n), [#("text-align", "right")])
    VText(s) -> #(s, [])
    VError(CircularRef) -> #("#CIRC", [#("color", "red")])
    VError(DivByZero) -> #("#DIV/0", [#("color", "red")])
    VError(TypeError) -> #("#TYPE", [#("color", "red")])
    VError(ParseError) -> #("#ERR", [#("color", "red")])
  }
}

fn format_number(n: Float) -> String {
  // Display as integer if it's a whole number
  let rounded = float.truncate(n)
  case int.to_float(rounded) == n {
    True -> int.to_string(rounded)
    False -> float.to_string(n)
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
