//// The expression language of cell formulas (the part after `=`).

import cells/cell_ref.{type CellRef}
import cells/scan
import gleam/list
import gleam/result
import gleam/set.{type Set}
import gleam/string

pub type Expr {
  Literal(Float)
  Ref(CellRef)
  /// A function of exactly two operands.
  Binary(BinOp, Expr, Expr)
  /// A function folding any number of arguments, including ranges.
  Aggregate(AggOp, List(Arg))
}

/// An argument of an aggregate. Ranges are only meaningful here, so they are
/// not an `Expr`.
pub type Arg {
  Single(Expr)
  Range(CellRef, CellRef)
}

pub type BinOp {
  Add
  Sub
  Mul
  Div
  Mod
}

pub type AggOp {
  Sum
  Prod
}

/// All cells the expression reads.
pub fn refs(expr: Expr) -> Set(CellRef) {
  case expr {
    Literal(_) -> set.new()
    Ref(ref) -> set.from_list([ref])
    Binary(_, left, right) -> set.union(refs(left), refs(right))
    Aggregate(_, args) ->
      list.fold(args, set.new(), fn(acc, arg) {
        case arg {
          Single(expr) -> set.union(acc, refs(expr))
          Range(from, to) ->
            set.union(acc, set.from_list(cell_ref.range(from, to)))
        }
      })
  }
}

// --- Parser ---

/// Parses a whole formula; trailing input is an error.
pub fn parse(input: String) -> Result(Expr, Nil) {
  use #(expr, rest) <- result.try(parse_expr(input))
  case string.trim(rest) {
    "" -> Ok(expr)
    _ -> Error(Nil)
  }
}

fn parse_expr(input: String) -> Result(#(Expr, String), Nil) {
  let input = string.trim_start(input)
  let first = string.first(input) |> result.unwrap("")
  let starts_number = scan.is_digit(first) || first == "-" || first == "."

  case starts_number, scan.is_lower(first) {
    True, _ -> parse_literal(input)
    _, True -> parse_call(input)
    _, _ -> cell_ref.parse(input) |> result.map(fn(p) { #(Ref(p.0), p.1) })
  }
}

fn parse_literal(input: String) -> Result(#(Expr, String), Nil) {
  let #(sign, rest) = case input {
    "-" <> rest -> #("-", rest)
    _ -> #("", input)
  }
  let #(digits, rest) =
    scan.take_while(rest, fn(ch) { scan.is_digit(ch) || ch == "." })

  scan.parse_number(sign <> digits)
  |> result.map(fn(n) { #(Literal(n), rest) })
}

/// What a function name stands for, before its arguments are checked.
type Function {
  Operator(BinOp)
  Reducer(AggOp)
}

fn function_from_name(name: String) -> Result(Function, Nil) {
  case name {
    "add" -> Ok(Operator(Add))
    "sub" -> Ok(Operator(Sub))
    "mul" -> Ok(Operator(Mul))
    "div" -> Ok(Operator(Div))
    "mod" -> Ok(Operator(Mod))
    "sum" -> Ok(Reducer(Sum))
    "prod" -> Ok(Reducer(Prod))
    _ -> Error(Nil)
  }
}

fn parse_call(input: String) -> Result(#(Expr, String), Nil) {
  let #(name, rest) = scan.take_while(input, scan.is_lower)
  use function <- result.try(function_from_name(name))
  use rest <- result.try(expect(rest, "("))
  use #(args, rest) <- result.try(parse_args(rest))
  use rest <- result.try(expect(rest, ")"))
  use expr <- result.try(build_call(function, args))
  Ok(#(expr, rest))
}

/// Checks the arguments against what the function accepts, so that a call
/// with the wrong arity or a range operand never becomes an `Expr`.
fn build_call(function: Function, args: List(Arg)) -> Result(Expr, Nil) {
  case function, args {
    Operator(op), [Single(left), Single(right)] -> Ok(Binary(op, left, right))
    Operator(_), _ -> Error(Nil)
    Reducer(op), _ -> Ok(Aggregate(op, args))
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
  case cell_ref.parse(input) {
    Ok(#(from, rest)) ->
      case string.trim_start(rest) {
        ":" <> rest -> {
          use #(to, rest) <- result.try(cell_ref.parse(string.trim_start(rest)))
          Ok(#(Range(from, to), rest))
        }
        _ -> Ok(#(Single(Ref(from)), rest))
      }
    Error(_) -> parse_expr(input) |> result.map(fn(p) { #(Single(p.0), p.1) })
  }
}

fn expect(input: String, token: String) -> Result(String, Nil) {
  let input = string.trim_start(input)
  case string.starts_with(input, token) {
    True -> Ok(string.drop_start(input, string.length(token)))
    False -> Error(Nil)
  }
}
