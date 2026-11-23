import cells/cell_ref

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

pub fn in_row_test() {
  let cells = cell_ref.in_row(3)
  assert cells != []
  assert cell_ref.in_row(cell_ref.num_rows) == []
}

pub fn column_letter_test() {
  assert cell_ref.column_letter(0) == "A"
  assert cell_ref.column_letter(25) == "Z"
}
