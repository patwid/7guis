import gleam/float
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import lustre
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub fn main() {
  let app = lustre.simple(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)

  Nil
}

/// Only the field the user last typed into holds their text, exactly as
/// typed, so it is never reformatted while typing. The other field is derived
/// from `last_valid`, so the two can never disagree.
///
/// `last_valid` is the last temperature entered, in degrees Celsius. It is
/// kept while the input does not parse, as the specification requires: when
/// the user enters a non-numerical string into one field, the other is not
/// updated.
type Model {
  Model(source: Scale, input: String, last_valid: Option(Float))
}

type Scale {
  Celsius
  Fahrenheit
}

/// The text of a field, parsed into a number of degrees.
type Input {
  Empty
  Valid(Float)
  Invalid
}

fn init(_: flags) -> Model {
  Model(source: Celsius, input: "", last_valid: None)
}

type Msg {
  UserUpdatedTemperature(Scale, String)
}

fn update(model: Model, msg: Msg) -> Model {
  case msg {
    UserUpdatedTemperature(scale, text) ->
      Model(source: scale, input: text, last_valid: case parse(text) {
        Valid(degrees) -> Some(to_celsius(scale, degrees))
        Empty | Invalid -> model.last_valid
      })
  }
}

fn parse(text: String) -> Input {
  case string.trim(text) {
    "" -> Empty
    trimmed ->
      case parse_number(trimmed) {
        Ok(value) -> Valid(value)
        Error(_) -> Invalid
      }
  }
}

/// Accepts whole numbers as well as decimals.
fn parse_number(text: String) -> Result(Float, Nil) {
  float.parse(text)
  |> result.lazy_or(fn() { int.parse(text) |> result.map(int.to_float) })
}

fn to_celsius(scale: Scale, degrees: Float) -> Float {
  case scale {
    Celsius -> degrees
    Fahrenheit -> { degrees -. 32.0 } *. { 5.0 /. 9.0 }
  }
}

fn from_celsius(scale: Scale, celsius: Float) -> Float {
  case scale {
    Celsius -> celsius
    Fahrenheit -> celsius *. { 9.0 /. 5.0 } +. 32.0
  }
}

/// Rounds to two decimals and drops a zero fraction, so conversions read
/// `98.6` and `212` rather than `98.60000000000001` and `212.0`.
fn format_number(n: Float) -> String {
  let rounded = float.to_precision(n, 2)
  let whole = float.truncate(rounded)

  case int.to_float(whole) == rounded {
    True -> int.to_string(whole)
    False -> float.to_string(rounded)
  }
}

fn view(model: Model) -> Element(Msg) {
  html.div([attribute.class("row")], [
    view_temperature_input(model, Celsius, label: "Celsius"),
    html.text(" = "),
    view_temperature_input(model, Fahrenheit, label: "Fahrenheit"),
  ])
}

/// The text of a field: as typed for the field being edited, else the last
/// valid temperature converted to its scale.
fn field_text(model: Model, scale: Scale) -> String {
  case model.source == scale, model.last_valid {
    True, _ -> model.input
    False, Some(celsius) -> format_number(from_celsius(scale, celsius))
    False, None -> ""
  }
}

fn is_invalid(text: String) -> Bool {
  case parse(text) {
    Invalid -> True
    Empty | Valid(_) -> False
  }
}

fn view_temperature_input(
  model: Model,
  scale: Scale,
  label label: String,
) -> Element(Msg) {
  let value = field_text(model, scale)

  let styles = case is_invalid(value) {
    False -> [#("width", "6em")]
    True -> [
      #("width", "6em"),
      #("outline", "none"),
      #("border", "2px solid red"),
      #("border-radius", "0.2em"),
    ]
  }

  element.fragment([
    html.input([
      attribute.styles(styles),
      attribute.value(value),
      event.on_input(UserUpdatedTemperature(scale, _)),
    ]),
    html.text(" " <> label),
  ])
}
