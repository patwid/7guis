//// A coordinate inside the sheet.

import cells/scan
import gleam/int
import gleam/list
import gleam/result
import gleam/string

pub const num_cols = 26

pub const num_rows = 100

/// Opaque, so every `CellRef` is guaranteed to lie within the sheet: the only
/// ways to get one are `new`, `parse`, and functions that stay in range.
pub opaque type CellRef {
  CellRef(col: Int, row: Int)
}

pub fn new(col: Int, row: Int) -> Result(CellRef, Nil) {
  case col >= 0 && col < num_cols && row >= 0 && row < num_rows {
    True -> Ok(CellRef(col:, row:))
    False -> Error(Nil)
  }
}

/// A row of the sheet: its name, as shown in the row header, and its cells,
/// left to right.
pub type Row {
  Row(name: String, cells: List(CellRef))
}

/// Every row of the sheet, top to bottom.
pub fn rows() -> List(Row) {
  list.range(0, num_rows - 1)
  |> list.map(fn(row) {
    Row(
      name: int.to_string(row),
      cells: list.map(columns(), fn(col) { CellRef(col:, row:) }),
    )
  })
}

/// The name of every column, left to right, as shown in the column header.
pub fn column_names() -> List(String) {
  list.map(columns(), column_letter)
}

fn columns() -> List(Int) {
  list.range(0, num_cols - 1)
}

/// The next cell in row-major order, wrapping around at the end.
pub fn next(ref: CellRef) -> CellRef {
  step(ref, 1)
}

/// The previous cell in row-major order, wrapping around at the start.
pub fn previous(ref: CellRef) -> CellRef {
  step(ref, -1)
}

fn step(ref: CellRef, delta: Int) -> CellRef {
  let total = num_cols * num_rows
  let index = ref.row * num_cols + ref.col
  let moved = { index + delta + total } % total

  CellRef(col: moved % num_cols, row: moved / num_cols)
}

/// All cells in the rectangle spanned by the two corners (inclusive).
pub fn range(from: CellRef, to: CellRef) -> List(CellRef) {
  let min_col = int.min(from.col, to.col)
  let max_col = int.max(from.col, to.col)
  let min_row = int.min(from.row, to.row)
  let max_row = int.max(from.row, to.row)

  list.flat_map(list.range(min_col, max_col), fn(col) {
    list.map(list.range(min_row, max_row), fn(row) { CellRef(col:, row:) })
  })
}

/// The column name, `A` to `Z`. Only called with columns in range; the `?`
/// merely keeps the function total.
fn column_letter(col: Int) -> String {
  case col >= 0 && col < num_cols, string.utf_codepoint(65 + col) {
    True, Ok(codepoint) -> string.from_utf_codepoints([codepoint])
    _, _ -> "?"
  }
}

/// Parses a reference such as `B12` from the start of `input` and returns
/// the rest of the input.
pub fn parse(input: String) -> Result(#(CellRef, String), Nil) {
  use #(letter, rest) <- result.try(string.pop_grapheme(input))
  use col <- result.try(column_from_letter(letter))
  let #(digits, rest) = scan.take_while(rest, scan.is_digit)
  use row <- result.try(int.parse(digits))
  use ref <- result.try(new(col, row))
  Ok(#(ref, rest))
}

fn column_from_letter(letter: String) -> Result(Int, Nil) {
  case scan.is_upper(letter), string.to_utf_codepoints(letter) {
    True, [codepoint] -> {
      let col = string.utf_codepoint_to_int(codepoint) - 65
      case col < num_cols {
        True -> Ok(col)
        False -> Error(Nil)
      }
    }
    _, _ -> Error(Nil)
  }
}
