//// Small character-level helpers shared by the cell reference and formula
//// parsers.

import gleam/float
import gleam/int
import gleam/result
import gleam/string

/// Splits off the longest prefix whose graphemes all satisfy `predicate`.
pub fn take_while(
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

pub fn is_digit(ch: String) -> Bool {
  case ch {
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    _ -> False
  }
}

pub fn is_upper(ch: String) -> Bool {
  case ascii_code(ch) {
    Ok(code) -> code >= 65 && code <= 90
    Error(_) -> False
  }
}

pub fn is_lower(ch: String) -> Bool {
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

/// Parses an integer or decimal number.
pub fn parse_number(text: String) -> Result(Float, Nil) {
  float.parse(text)
  |> result.lazy_or(fn() { int.parse(text) |> result.map(int.to_float) })
}
