import cells/cell_ref
import gleam/list

fn ref(text: String) -> cell_ref.CellRef {
  let assert Ok(#(ref, "")) = cell_ref.parse(text)
  ref
}

pub fn new_rejects_out_of_range_test() {
  assert cell_ref.new(-1, 0) == Error(Nil)
  assert cell_ref.new(0, -1) == Error(Nil)
  assert cell_ref.new(cell_ref.num_cols, 0) == Error(Nil)
  assert cell_ref.new(0, cell_ref.num_rows) == Error(Nil)
}

pub fn parse_test() {
  let assert Ok(a0) = cell_ref.new(0, 0)
  let assert Ok(z99) = cell_ref.new(25, 99)
  let assert Ok(b2) = cell_ref.new(1, 2)

  assert cell_ref.parse("A0") == Ok(#(a0, ""))
  assert cell_ref.parse("Z99") == Ok(#(z99, ""))
  assert cell_ref.parse("B2+") == Ok(#(b2, "+"))
}

pub fn parse_rejects_invalid_test() {
  assert cell_ref.parse("a1") == Error(Nil)
  assert cell_ref.parse("A") == Error(Nil)
  assert cell_ref.parse("A100") == Error(Nil)
  assert cell_ref.parse("1A") == Error(Nil)
  assert cell_ref.parse("") == Error(Nil)
}

pub fn next_wraps_around_test() {
  assert cell_ref.next(ref("Z0")) == ref("A1")
  assert cell_ref.next(ref("Z99")) == ref("A0")
}

pub fn previous_wraps_around_test() {
  assert cell_ref.previous(ref("A1")) == ref("Z0")
  assert cell_ref.previous(ref("A0")) == ref("Z99")
}

pub fn range_is_corner_order_independent_test() {
  assert cell_ref.range(ref("A0"), ref("B1"))
    == [ref("A0"), ref("A1"), ref("B0"), ref("B1")]
  assert cell_ref.range(ref("B1"), ref("A0"))
    == cell_ref.range(ref("A0"), ref("B1"))
}

pub fn rows_test() {
  let rows = cell_ref.rows()
  assert list.length(rows) == cell_ref.num_rows

  let assert [first, ..] = rows
  let assert Ok(last) = list.last(rows)
  assert first.name == "0"
  assert list.take(first.cells, 2) == [ref("A0"), ref("B0")]
  assert list.length(first.cells) == cell_ref.num_cols
  assert last.name == "99"
  assert list.last(last.cells) == Ok(ref("Z99"))
}

pub fn column_names_test() {
  let names = cell_ref.column_names()
  assert list.length(names) == cell_ref.num_cols
  assert list.first(names) == Ok("A")
  assert list.last(names) == Ok("Z")
}
