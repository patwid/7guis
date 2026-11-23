import cells/cell_ref
import cells/sheet.{
  type Sheet, type Value, CircularRef, DivByZero, ParseError, TypeError, VEmpty,
  VError, VNumber, VText,
}

fn ref(text: String) -> cell_ref.CellRef {
  let assert Ok(#(ref, "")) = cell_ref.parse(text)
  ref
}

fn with(s: Sheet, cells: List(#(String, String))) -> Sheet {
  case cells {
    [] -> s
    [#(at, raw), ..rest] -> with(sheet.set(s, ref(at), raw), rest)
  }
}

fn value(s: Sheet, at: String) -> Value {
  sheet.value(s, ref(at))
}

pub fn plain_contents_test() {
  let s = sheet.new() |> with([#("A0", "42"), #("A1", "hello"), #("A2", "1.5")])

  assert value(s, "A0") == VNumber(42.0)
  assert value(s, "A1") == VText("hello")
  assert value(s, "A2") == VNumber(1.5)
  assert value(s, "A3") == VEmpty
}

pub fn raw_is_kept_verbatim_test() {
  let s = sheet.new() |> with([#("A0", " =add(1,2) ")])

  assert sheet.raw(s, ref("A0")) == " =add(1,2) "
  assert sheet.raw(s, ref("A1")) == ""
}

pub fn arithmetic_test() {
  let s =
    sheet.new()
    |> with([
      #("A0", "=add(1,2)"),
      #("A1", "=sub(5,2)"),
      #("A2", "=mul(3,4)"),
      #("A3", "=div(9,2)"),
      #("A4", "=mod(7,4)"),
    ])

  assert value(s, "A0") == VNumber(3.0)
  assert value(s, "A1") == VNumber(3.0)
  assert value(s, "A2") == VNumber(12.0)
  assert value(s, "A3") == VNumber(4.5)
  assert value(s, "A4") == VNumber(3.0)
}

pub fn aggregates_over_ranges_test() {
  let s =
    sheet.new()
    |> with([
      #("A0", "1"),
      #("A1", "2"),
      #("A2", "3"),
      #("B0", "=sum(A0:A2)"),
      #("B1", "=prod(A0:A2, 2)"),
    ])

  assert value(s, "B0") == VNumber(6.0)
  assert value(s, "B1") == VNumber(12.0)
}

pub fn empty_cells_count_as_zero_test() {
  let s = sheet.new() |> with([#("A0", "=add(B0, 1)")])

  assert value(s, "A0") == VNumber(1.0)
}

pub fn errors_test() {
  let s =
    sheet.new()
    |> with([
      #("A0", "=div(1,0)"),
      #("A1", "=mod(1,0)"),
      #("A2", "text"),
      #("A3", "=add(A2, 1)"),
      #("A4", "=add(1"),
      #("A5", "=add(1,2,3)"),
    ])

  assert value(s, "A0") == VError(DivByZero)
  assert value(s, "A1") == VError(DivByZero)
  assert value(s, "A3") == VError(TypeError)
  assert value(s, "A4") == VError(ParseError)
  assert value(s, "A5") == VError(ParseError)
}

pub fn errors_propagate_test() {
  let s = sheet.new() |> with([#("A0", "=div(1,0)"), #("A1", "=add(A0, 1)")])

  assert value(s, "A1") == VError(DivByZero)
}

pub fn dependents_update_transitively_test() {
  let s =
    sheet.new()
    |> with([#("A0", "1"), #("A1", "=add(A0,1)"), #("A2", "=mul(A1,10)")])
  assert value(s, "A2") == VNumber(20.0)

  let s = sheet.set(s, ref("A0"), "4")
  assert value(s, "A1") == VNumber(5.0)
  assert value(s, "A2") == VNumber(50.0)
}

pub fn dependents_update_when_defined_later_test() {
  let s = sheet.new() |> with([#("A1", "=add(A0,1)"), #("A0", "7")])

  assert value(s, "A1") == VNumber(8.0)
}

pub fn dependents_update_across_ranges_test() {
  let s = sheet.new() |> with([#("B0", "=sum(A0:A2)"), #("A1", "5")])

  assert value(s, "B0") == VNumber(5.0)
}

pub fn changing_a_formula_drops_old_dependencies_test() {
  let s =
    sheet.new()
    |> with([#("A0", "1"), #("B0", "2"), #("C0", "=add(A0,1)")])
    |> sheet.set(ref("C0"), "=add(B0,1)")
  assert value(s, "C0") == VNumber(3.0)

  // C0 no longer reads A0, so changing A0 must not touch it.
  let s = sheet.set(s, ref("A0"), "100")
  assert value(s, "C0") == VNumber(3.0)

  let s = sheet.set(s, ref("B0"), "10")
  assert value(s, "C0") == VNumber(11.0)
}

pub fn clearing_a_cell_test() {
  let s = sheet.new() |> with([#("A0", "5"), #("A1", "=add(A0,1)")])
  let s = sheet.set(s, ref("A0"), "  ")

  assert sheet.raw(s, ref("A0")) == ""
  assert value(s, "A0") == VEmpty
  assert value(s, "A1") == VNumber(1.0)
}

pub fn self_reference_is_circular_test() {
  let s = sheet.new() |> with([#("A0", "=add(A0,1)")])

  assert value(s, "A0") == VError(CircularRef)
}

pub fn cycles_are_detected_test() {
  let s =
    sheet.new()
    |> with([#("A0", "=add(A1,1)"), #("A1", "=add(A2,1)"), #("A2", "=A0")])

  assert value(s, "A0") == VError(CircularRef)
  assert value(s, "A1") == VError(CircularRef)
  assert value(s, "A2") == VError(CircularRef)
}

pub fn dependents_of_a_cycle_see_the_error_test() {
  let s =
    sheet.new()
    |> with([#("A0", "=A1"), #("A1", "=A0"), #("B0", "=add(A0,1)")])

  assert value(s, "B0") == VError(CircularRef)
}

pub fn breaking_a_cycle_recovers_test() {
  let s = sheet.new() |> with([#("A0", "=A1"), #("A1", "=A0")])
  assert value(s, "A0") == VError(CircularRef)

  let s = sheet.set(s, ref("A1"), "3")
  assert value(s, "A0") == VNumber(3.0)
  assert value(s, "A1") == VNumber(3.0)
}
