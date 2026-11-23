import cells/cell_ref
import cells/formula.{
  Add, Aggregate, Binary, Div, Literal, Prod, Range, Ref, Single, Sum,
}
import gleam/set

fn ref(col: Int, row: Int) -> cell_ref.CellRef {
  let assert Ok(ref) = cell_ref.new(col, row)
  ref
}

pub fn parses_literals_test() {
  assert formula.parse("1") == Ok(Literal(1.0))
  assert formula.parse("-2.5") == Ok(Literal(-2.5))
  assert formula.parse("  3  ") == Ok(Literal(3.0))
}

pub fn parses_references_test() {
  assert formula.parse("B2") == Ok(Ref(ref(1, 2)))
}

pub fn parses_binary_calls_test() {
  assert formula.parse("add(1, A0)")
    == Ok(Binary(Add, Literal(1.0), Ref(ref(0, 0))))
  assert formula.parse("div(add(1,2),3)")
    == Ok(Binary(Div, Binary(Add, Literal(1.0), Literal(2.0)), Literal(3.0)))
}

pub fn parses_aggregates_test() {
  assert formula.parse("sum(A0:B1, 3)")
    == Ok(Aggregate(Sum, [Range(ref(0, 0), ref(1, 1)), Single(Literal(3.0))]))
  assert formula.parse("prod()") == Ok(Aggregate(Prod, []))
}

pub fn rejects_wrong_arity_test() {
  assert formula.parse("add(1)") == Error(Nil)
  assert formula.parse("add(1,2,3)") == Error(Nil)
  assert formula.parse("add()") == Error(Nil)
}

pub fn rejects_ranges_as_binary_operands_test() {
  assert formula.parse("add(A0:A3, 1)") == Error(Nil)
}

pub fn rejects_malformed_input_test() {
  assert formula.parse("") == Error(Nil)
  assert formula.parse("foo(1)") == Error(Nil)
  assert formula.parse("add(1,2") == Error(Nil)
  assert formula.parse("1 2") == Error(Nil)
  assert formula.parse("A100") == Error(Nil)
}

pub fn refs_test() {
  let assert Ok(expr) = formula.parse("add(A0, sum(B0:B1))")
  let refs = formula.refs(expr)

  assert set.size(refs) == 3
  assert set.contains(refs, ref(0, 0))
  assert set.contains(refs, ref(1, 0))
  assert set.contains(refs, ref(1, 1))
}
