import gleam/float
import gleam/int
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

/// The text of both fields, exactly as shown. Numbers are parsed from it on
/// demand, so the user's input is never reformatted while typing.
type Model {
  Model(celsius: String, fahrenheit: String)
}

/// The text of a field, parsed into a number of degrees.
type Input {
  Empty
  Valid(Float)
  Invalid
}

fn init(_: flags) -> Model {
  Model(celsius: "", fahrenheit: "")
}

type Msg {
  UserUpdatedCelsius(String)
  UserUpdatedFahrenheit(String)
}

fn update(model: Model, msg: Msg) -> Model {
  // The specification requires: When the user enters a non-numerical
  // string into TC the value in TF is not updated and vice versa.
  case msg {
    UserUpdatedCelsius(text) ->
      case parse(text) {
        Valid(celsius) ->
          Model(
            celsius: text,
            fahrenheit: format_number(to_fahrenheit(celsius)),
          )
        Empty | Invalid -> Model(..model, celsius: text)
      }

    UserUpdatedFahrenheit(text) ->
      case parse(text) {
        Valid(fahrenheit) ->
          Model(
            celsius: format_number(to_celsius(fahrenheit)),
            fahrenheit: text,
          )
        Empty | Invalid -> Model(..model, fahrenheit: text)
      }
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

fn to_celsius(fahrenheit: Float) -> Float {
  { fahrenheit -. 32.0 } *. { 5.0 /. 9.0 }
}

fn to_fahrenheit(celsius: Float) -> Float {
  celsius *. { 9.0 /. 5.0 } +. 32.0
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
    view_temperature_input(
      value: model.celsius,
      invalid: is_invalid(model.celsius),
      label: "Celsius",
      on_input: UserUpdatedCelsius,
    ),
    html.text(" = "),
    view_temperature_input(
      value: model.fahrenheit,
      invalid: is_invalid(model.fahrenheit),
      label: "Fahrenheit",
      on_input: UserUpdatedFahrenheit,
    ),
  ])
}

fn is_invalid(text: String) -> Bool {
  case parse(text) {
    Invalid -> True
    Empty | Valid(_) -> False
  }
}

fn view_temperature_input(
  value value: String,
  invalid invalid: Bool,
  label label: String,
  on_input handle_input: fn(String) -> Msg,
) -> Element(Msg) {
  let styles = case invalid {
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
      event.on_input(handle_input),
    ]),
    html.text(" " <> label),
  ])
}
