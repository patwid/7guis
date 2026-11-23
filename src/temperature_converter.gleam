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

type Celsius {
  Celsius(Float)
}

type Fahrenheit {
  Fahrenheit(Float)
}

type Input(a) {
  Empty
  Valid(a)
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
      case parse(text, Celsius) {
        Valid(celsius) ->
          Model(
            celsius: text,
            fahrenheit: fahrenheit_to_string(to_fahrenheit(celsius)),
          )
        Empty | Invalid -> Model(..model, celsius: text)
      }

    UserUpdatedFahrenheit(text) ->
      case parse(text, Fahrenheit) {
        Valid(fahrenheit) ->
          Model(
            celsius: celsius_to_string(to_celsius(fahrenheit)),
            fahrenheit: text,
          )
        Empty | Invalid -> Model(..model, fahrenheit: text)
      }
  }
}

fn parse(text: String, unit: fn(Float) -> a) -> Input(a) {
  case string.trim(text) {
    "" -> Empty
    trimmed ->
      case parse_number(trimmed) {
        Ok(value) -> Valid(unit(value))
        Error(_) -> Invalid
      }
  }
}

/// Accepts whole numbers as well as decimals.
fn parse_number(text: String) -> Result(Float, Nil) {
  float.parse(text)
  |> result.lazy_or(fn() { int.parse(text) |> result.map(int.to_float) })
}

fn to_celsius(fahrenheit: Fahrenheit) -> Celsius {
  let Fahrenheit(f) = fahrenheit
  Celsius({ f -. 32.0 } *. { 5.0 /. 9.0 })
}

fn to_fahrenheit(celsius: Celsius) -> Fahrenheit {
  let Celsius(c) = celsius
  Fahrenheit(c *. { 9.0 /. 5.0 } +. 32.0)
}

fn celsius_to_string(celsius: Celsius) -> String {
  let Celsius(c) = celsius
  format_number(c)
}

fn fahrenheit_to_string(fahrenheit: Fahrenheit) -> String {
  let Fahrenheit(f) = fahrenheit
  format_number(f)
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
      invalid: parse(model.celsius, Celsius) == Invalid,
      label: "Celsius",
      on_input: UserUpdatedCelsius,
    ),
    html.text(" = "),
    view_temperature_input(
      value: model.fahrenheit,
      invalid: parse(model.fahrenheit, Fahrenheit) == Invalid,
      label: "Fahrenheit",
      on_input: UserUpdatedFahrenheit,
    ),
  ])
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
