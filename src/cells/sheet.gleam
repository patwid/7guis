//// The spreadsheet model: cell contents, their evaluated values and the
//// dependencies between them.

import cells/cell_ref.{type CellRef}
import cells/formula.{
  type AggOp, type BinOp, type Expr, Add, Aggregate, Binary, Div, Literal, Mod,
  Mul, Prod, Range, Ref, Single, Sub, Sum,
}
import cells/scan
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set.{type Set}
import gleam/string

/// What a cell evaluates to.
pub type Value {
  /// A blank cell. A formula never evaluates to it: a blank cell it reads
  /// counts as `0`, as in other spreadsheets.
  Empty
  Number(Float)
  Text(String)
  /// The cell could not be evaluated; shown as an error code.
  Failed(CellError)
}

pub type CellError {
  ParseError
  CircularRef
  TypeError
  DivByZero
}

/// What the user entered into a non-blank cell, after parsing.
type Content {
  /// A number, e.g. `42`.
  Constant(Float)
  /// Any other text, e.g. `hello`.
  Label(String)
  Formula(Expr)
  Malformed
}

/// A non-blank cell. Only `parse_cell` builds one, so `content` is always the
/// parse of `raw` and `refs` the cells it reads.
type Cell {
  Cell(raw: String, content: Content, refs: Set(CellRef))
}

/// Invariants, maintained by `set`:
/// - `values` has an entry for exactly the cells in `cells`, evaluated from
///   their current content;
/// - `dependents` is the inverse of the cells' `refs` and holds no empty sets.
pub opaque type Sheet {
  Sheet(
    cells: Dict(CellRef, Cell),
    values: Dict(CellRef, Value),
    dependents: Dict(CellRef, Set(CellRef)),
  )
}

pub fn new() -> Sheet {
  Sheet(cells: dict.new(), values: dict.new(), dependents: dict.new())
}

/// The text the user entered into the cell; empty for a blank cell.
pub fn raw(sheet: Sheet, ref: CellRef) -> String {
  case dict.get(sheet.cells, ref) {
    Ok(cell) -> cell.raw
    Error(_) -> ""
  }
}

pub fn value(sheet: Sheet, ref: CellRef) -> Value {
  lookup(sheet.values, ref)
}

/// Replaces the content of a cell and re-evaluates everything affected. A
/// blank `raw` clears the cell.
pub fn set(sheet: Sheet, ref: CellRef, raw: String) -> Sheet {
  let old_refs = dependencies(sheet.cells, ref)
  let #(cells, new_refs) = case parse_cell(raw) {
    Some(cell) -> #(dict.insert(sheet.cells, ref, cell), cell.refs)
    None -> #(dict.delete(sheet.cells, ref), set.new())
  }
  let dependents = update_dependents(sheet.dependents, ref, old_refs, new_refs)

  recalculate(Sheet(..sheet, cells:, dependents:), ref)
}

fn parse_cell(raw: String) -> Option(Cell) {
  parse_content(raw)
  |> option.map(fn(content) {
    Cell(raw:, content:, refs: content_refs(content))
  })
}

fn parse_content(raw: String) -> Option(Content) {
  case string.trim(raw) {
    "" -> None
    "=" <> source ->
      case formula.parse(source) {
        Ok(expr) -> Some(Formula(expr))
        Error(_) -> Some(Malformed)
      }
    text ->
      case scan.parse_number(text) {
        Ok(n) -> Some(Constant(n))
        Error(_) -> Some(Label(text))
      }
  }
}

fn lookup(values: Dict(CellRef, Value), ref: CellRef) -> Value {
  dict.get(values, ref) |> result.unwrap(Empty)
}

fn content_refs(content: Content) -> Set(CellRef) {
  case content {
    Formula(expr) -> formula.refs(expr)
    Constant(_) | Label(_) | Malformed -> set.new()
  }
}

// --- Dependency graph ---

/// The cells `ref` reads.
fn dependencies(cells: Dict(CellRef, Cell), ref: CellRef) -> Set(CellRef) {
  case dict.get(cells, ref) {
    Ok(cell) -> cell.refs
    Error(_) -> set.new()
  }
}

/// Moves `ref` from the dependents of `old_refs` to those of `new_refs`.
fn update_dependents(
  dependents: Dict(CellRef, Set(CellRef)),
  ref: CellRef,
  old_refs: Set(CellRef),
  new_refs: Set(CellRef),
) -> Dict(CellRef, Set(CellRef)) {
  let dependents =
    set.fold(old_refs, dependents, fn(dependents, dep) {
      remove_neighbour(dependents, dep, ref)
    })

  set.fold(new_refs, dependents, fn(dependents, dep) {
    add_neighbour(dependents, dep, ref)
  })
}

fn neighbours(
  graph: Dict(CellRef, Set(CellRef)),
  ref: CellRef,
) -> Set(CellRef) {
  dict.get(graph, ref) |> result.unwrap(set.new())
}

fn add_neighbour(
  graph: Dict(CellRef, Set(CellRef)),
  ref: CellRef,
  neighbour: CellRef,
) -> Dict(CellRef, Set(CellRef)) {
  dict.insert(graph, ref, set.insert(neighbours(graph, ref), neighbour))
}

fn remove_neighbour(
  graph: Dict(CellRef, Set(CellRef)),
  ref: CellRef,
  neighbour: CellRef,
) -> Dict(CellRef, Set(CellRef)) {
  let remaining = set.delete(neighbours(graph, ref), neighbour)
  case set.is_empty(remaining) {
    True -> dict.delete(graph, ref)
    False -> dict.insert(graph, ref, remaining)
  }
}

/// Re-evaluates `changed` and every cell that (transitively) depends on it.
/// Cells on a reference cycle evaluate to `CircularRef`; cells depending on
/// them pick that error up through normal evaluation.
fn recalculate(sheet: Sheet, changed: CellRef) -> Sheet {
  let affected =
    collect_dependents(changed, sheet.dependents, set.from_list([changed]))

  let values =
    strongly_connected(affected, sheet.cells)
    |> list.fold(sheet.values, fn(values, component) {
      case is_cycle(component, sheet.cells) {
        True ->
          list.fold(component, values, fn(values, ref) {
            dict.insert(values, ref, Failed(CircularRef))
          })
        False ->
          list.fold(component, values, fn(values, ref) {
            case dict.get(sheet.cells, ref) {
              Ok(cell) ->
                dict.insert(values, ref, evaluate(cell.content, values))
              Error(_) -> dict.delete(values, ref)
            }
          })
      }
    })

  Sheet(..sheet, values:)
}

fn collect_dependents(
  ref: CellRef,
  dependents: Dict(CellRef, Set(CellRef)),
  visited: Set(CellRef),
) -> Set(CellRef) {
  set.fold(neighbours(dependents, ref), visited, fn(visited, dep) {
    case set.contains(visited, dep) {
      True -> visited
      False -> collect_dependents(dep, dependents, set.insert(visited, dep))
    }
  })
}

/// Whether a strongly connected component is a cycle: it has several cells,
/// or one that reads itself.
fn is_cycle(component: List(CellRef), cells: Dict(CellRef, Cell)) -> Bool {
  case component {
    [ref] -> set.contains(dependencies(cells, ref), ref)
    _ -> True
  }
}

/// The strongly connected components of the cells in `refs`, following the
/// cells they read and ignoring cells outside `refs`. Each component comes
/// after the components it reads, so evaluating them in order sees every
/// dependency up to date.
///
/// `affected` can be passed as `refs` without missing a cycle: every cell on a
/// cycle through an affected cell depends on it, so is affected too.
///
/// Tarjan's algorithm, which finds all components in one depth-first search.
fn strongly_connected(
  refs: Set(CellRef),
  cells: Dict(CellRef, Cell),
) -> List(List(CellRef)) {
  let search =
    Search(
      next_index: 0,
      index: dict.new(),
      low_link: dict.new(),
      stack: [],
      on_stack: set.new(),
      components: [],
    )

  let search =
    set.fold(refs, search, fn(search, ref) {
      case dict.has_key(search.index, ref) {
        True -> search
        False -> strong_connect(ref, refs, cells, search)
      }
    })

  list.reverse(search.components)
}

/// The state of the search in `strongly_connected`. `index` is the order in
/// which cells were reached, `low_link` the lowest index reachable from a
/// cell through cells still on the stack.
type Search {
  Search(
    next_index: Int,
    index: Dict(CellRef, Int),
    low_link: Dict(CellRef, Int),
    stack: List(CellRef),
    on_stack: Set(CellRef),
    components: List(List(CellRef)),
  )
}

fn strong_connect(
  ref: CellRef,
  refs: Set(CellRef),
  cells: Dict(CellRef, Cell),
  search: Search,
) -> Search {
  let index = search.next_index
  let search =
    Search(
      ..search,
      next_index: index + 1,
      index: dict.insert(search.index, ref, index),
      low_link: dict.insert(search.low_link, ref, index),
      stack: [ref, ..search.stack],
      on_stack: set.insert(search.on_stack, ref),
    )

  let search =
    set.fold(dependencies(cells, ref), search, fn(search, dep) {
      case set.contains(refs, dep), dict.get(search.index, dep) {
        False, _ -> search
        True, Error(_) -> {
          let search = strong_connect(dep, refs, cells, search)
          lower_link(search, ref, low_link(search, dep))
        }
        True, Ok(dep_index) ->
          case set.contains(search.on_stack, dep) {
            True -> lower_link(search, ref, dep_index)
            False -> search
          }
      }
    })

  case low_link(search, ref) == index {
    False -> search
    True -> {
      let #(component, stack) = pop_component(search.stack, ref, [])
      Search(
        ..search,
        stack:,
        on_stack: set.drop(search.on_stack, component),
        components: [component, ..search.components],
      )
    }
  }
}

/// Only called for cells the search has reached, which always have one.
fn low_link(search: Search, ref: CellRef) -> Int {
  dict.get(search.low_link, ref) |> result.unwrap(0)
}

fn lower_link(search: Search, ref: CellRef, candidate: Int) -> Search {
  let lowered = int.min(low_link(search, ref), candidate)
  Search(..search, low_link: dict.insert(search.low_link, ref, lowered))
}

/// Pops the stack down to and including `root`, which closes a component.
fn pop_component(
  stack: List(CellRef),
  root: CellRef,
  component: List(CellRef),
) -> #(List(CellRef), List(CellRef)) {
  case stack {
    [] -> #(component, [])
    [ref, ..rest] if ref == root -> #([ref, ..component], rest)
    [ref, ..rest] -> pop_component(rest, root, [ref, ..component])
  }
}

// --- Evaluation ---

fn evaluate(content: Content, values: Dict(CellRef, Value)) -> Value {
  case content {
    Constant(n) -> Number(n)
    Label(s) -> Text(s)
    Formula(expr) ->
      case evaluate_expr(expr, values) {
        Empty -> Number(0.0)
        value -> value
      }
    Malformed -> Failed(ParseError)
  }
}

fn evaluate_expr(expr: Expr, values: Dict(CellRef, Value)) -> Value {
  case expr {
    Literal(n) -> Number(n)
    Ref(ref) -> lookup(values, ref)
    Binary(op, left, right) ->
      apply_binary(
        op,
        evaluate_expr(left, values),
        evaluate_expr(right, values),
      )
    Aggregate(op, args) ->
      args
      |> list.flat_map(fn(arg) {
        case arg {
          Single(expr) -> [evaluate_expr(expr, values)]
          Range(from, to) ->
            cell_ref.range(from, to) |> list.map(lookup(values, _))
        }
      })
      |> apply_aggregate(op, _)
  }
}

fn apply_binary(op: BinOp, left: Value, right: Value) -> Value {
  let result = {
    use a <- result.try(coerce_number(left))
    use b <- result.try(coerce_number(right))
    case op {
      Add -> Ok(a +. b)
      Sub -> Ok(a -. b)
      Mul -> Ok(a *. b)
      Div -> float.divide(a, b) |> result.replace_error(DivByZero)
      Mod -> float.modulo(a, b) |> result.replace_error(DivByZero)
    }
  }

  to_value(result)
}

fn apply_aggregate(op: AggOp, values: List(Value)) -> Value {
  list.try_map(values, coerce_number)
  |> result.map(fn(numbers) {
    case op {
      Sum -> float.sum(numbers)
      Prod -> float.product(numbers)
    }
  })
  |> to_value
}

fn coerce_number(value: Value) -> Result(Float, CellError) {
  case value {
    Empty -> Ok(0.0)
    Number(n) -> Ok(n)
    Text(_) -> Error(TypeError)
    Failed(e) -> Error(e)
  }
}

fn to_value(result: Result(Float, CellError)) -> Value {
  case result {
    Ok(n) -> Number(n)
    Error(e) -> Failed(e)
  }
}
