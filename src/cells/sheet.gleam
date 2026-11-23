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
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set.{type Set}
import gleam/string

pub type Value {
  VEmpty
  VNumber(Float)
  VText(String)
  VError(CellError)
}

pub type CellError {
  ParseError
  CircularRef
  TypeError
  DivByZero
}

/// What the user entered into a non-blank cell, after parsing.
type Content {
  Number(Float)
  Text(String)
  Formula(Expr)
  Malformed
}

/// A non-blank cell. Only `parse_cell` builds one, so `content` is always the
/// parse of `raw`.
type Cell {
  Cell(raw: String, content: Content)
}

/// Invariants, maintained by `set`:
/// - `values` has an entry for exactly the cells in `cells`, evaluated from
///   their current content;
/// - `dependencies` maps a cell to the cells it reads, `dependents` is its
///   inverse, and neither holds empty sets.
pub opaque type Sheet {
  Sheet(
    cells: Dict(CellRef, Cell),
    values: Dict(CellRef, Value),
    dependencies: Dict(CellRef, Set(CellRef)),
    dependents: Dict(CellRef, Set(CellRef)),
  )
}

pub fn new() -> Sheet {
  Sheet(
    cells: dict.new(),
    values: dict.new(),
    dependencies: dict.new(),
    dependents: dict.new(),
  )
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
  let sheet = case parse_cell(raw) {
    Some(cell) -> insert(sheet, ref, cell)
    None -> remove(sheet, ref)
  }

  recalculate(sheet, ref)
}

fn parse_cell(raw: String) -> Option(Cell) {
  parse_content(raw) |> option.map(fn(content) { Cell(raw:, content:) })
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
        Ok(n) -> Some(Number(n))
        Error(_) -> Some(Text(text))
      }
  }
}

fn insert(sheet: Sheet, ref: CellRef, cell: Cell) -> Sheet {
  Sheet(..sheet, cells: dict.insert(sheet.cells, ref, cell))
  |> set_dependencies(ref, content_refs(cell.content))
}

fn remove(sheet: Sheet, ref: CellRef) -> Sheet {
  Sheet(
    ..sheet,
    cells: dict.delete(sheet.cells, ref),
    values: dict.delete(sheet.values, ref),
  )
  |> set_dependencies(ref, set.new())
}

fn lookup(values: Dict(CellRef, Value), ref: CellRef) -> Value {
  dict.get(values, ref) |> result.unwrap(VEmpty)
}

fn content_refs(content: Content) -> Set(CellRef) {
  case content {
    Formula(expr) -> formula.refs(expr)
    Number(_) | Text(_) | Malformed -> set.new()
  }
}

// --- Dependency graph ---

/// Records that `ref` now reads exactly `new_deps`, keeping `dependents` in
/// sync.
fn set_dependencies(
  sheet: Sheet,
  ref: CellRef,
  new_deps: Set(CellRef),
) -> Sheet {
  let old_deps = neighbours(sheet.dependencies, ref)

  let dependents =
    set.fold(old_deps, sheet.dependents, fn(dependents, dep) {
      remove_neighbour(dependents, dep, ref)
    })
  let dependents =
    set.fold(new_deps, dependents, fn(dependents, dep) {
      add_neighbour(dependents, dep, ref)
    })
  let dependencies = case set.is_empty(new_deps) {
    True -> dict.delete(sheet.dependencies, ref)
    False -> dict.insert(sheet.dependencies, ref, new_deps)
  }

  Sheet(..sheet, dependencies:, dependents:)
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
  let circular =
    set.filter(affected, fn(ref) {
      has_cycle(ref, neighbours(sheet.dependencies, ref), sheet.dependencies)
    })

  let values =
    set.fold(circular, sheet.values, fn(values, ref) {
      dict.insert(values, ref, VError(CircularRef))
    })

  let values =
    set.difference(affected, circular)
    |> topological_order(sheet.dependencies)
    |> list.fold(values, fn(values, ref) {
      case dict.get(sheet.cells, ref) {
        Ok(cell) -> dict.insert(values, ref, evaluate(cell.content, values))
        Error(_) -> dict.delete(values, ref)
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

/// Whether `target` is reachable from `refs`, i.e. lies on a cycle.
fn has_cycle(
  target: CellRef,
  refs: Set(CellRef),
  dependencies: Dict(CellRef, Set(CellRef)),
) -> Bool {
  has_cycle_loop(target, set.to_list(refs), dependencies, set.new())
}

fn has_cycle_loop(
  target: CellRef,
  stack: List(CellRef),
  dependencies: Dict(CellRef, Set(CellRef)),
  visited: Set(CellRef),
) -> Bool {
  case stack {
    [] -> False
    [ref, ..] if ref == target -> True
    [ref, ..rest] ->
      case set.contains(visited, ref) {
        True -> has_cycle_loop(target, rest, dependencies, visited)
        False ->
          has_cycle_loop(
            target,
            list.append(set.to_list(neighbours(dependencies, ref)), rest),
            dependencies,
            set.insert(visited, ref),
          )
      }
  }
}

/// Orders `cells` so that each cell comes after the cells it depends on.
/// Dependencies outside `cells` are ignored; `cells` must be acyclic.
fn topological_order(
  cells: Set(CellRef),
  dependencies: Dict(CellRef, Set(CellRef)),
) -> List(CellRef) {
  let #(order, _) =
    set.fold(cells, #([], set.new()), fn(acc, ref) {
      visit(ref, cells, dependencies, acc)
    })

  list.reverse(order)
}

fn visit(
  ref: CellRef,
  cells: Set(CellRef),
  dependencies: Dict(CellRef, Set(CellRef)),
  acc: #(List(CellRef), Set(CellRef)),
) -> #(List(CellRef), Set(CellRef)) {
  let #(order, seen) = acc
  case set.contains(seen, ref) || !set.contains(cells, ref) {
    True -> acc
    False -> {
      let #(order, seen) =
        set.fold(
          neighbours(dependencies, ref),
          #(order, set.insert(seen, ref)),
          fn(acc, dep) { visit(dep, cells, dependencies, acc) },
        )
      #([ref, ..order], seen)
    }
  }
}

// --- Evaluation ---

fn evaluate(content: Content, values: Dict(CellRef, Value)) -> Value {
  case content {
    Number(n) -> VNumber(n)
    Text(s) -> VText(s)
    Formula(expr) -> evaluate_expr(expr, values)
    Malformed -> VError(ParseError)
  }
}

fn evaluate_expr(expr: Expr, values: Dict(CellRef, Value)) -> Value {
  case expr {
    Literal(n) -> VNumber(n)
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
    VEmpty -> Ok(0.0)
    VNumber(n) -> Ok(n)
    VText(_) -> Error(TypeError)
    VError(e) -> Error(e)
  }
}

fn to_value(result: Result(Float, CellError)) -> Value {
  case result {
    Ok(n) -> VNumber(n)
    Error(e) -> VError(e)
  }
}
