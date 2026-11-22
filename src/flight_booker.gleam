import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/list
import gleam/order
import gleam/pair
import gleam/result
import gleam/string
import gleam/time/calendar.{type Date}
import gleam/time/timestamp
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

/// The date fields hold the text exactly as typed; dates are parsed from it
/// on demand, so the user's input is never reformatted while typing.
type Model {
  Model(flight: Flight, start: String, return: String)
}

type Flight {
  OneWay
  Return
}

/// A booking that passed validation.
type Booking {
  OneWayBooking(date: Date)
  ReturnBooking(start: Date, return: Date)
}

fn init(_: flags) -> Model {
  let #(today, _) =
    timestamp.system_time() |> timestamp.to_calendar(calendar.utc_offset)
  let today = format_date(today)

  Model(flight: OneWay, start: today, return: today)
}

type Msg {
  UserSelectedFlight(Flight)
  UserUpdatedStart(String)
  UserUpdatedReturn(String)
}

fn update(model: Model, msg: Msg) -> Model {
  case msg {
    UserSelectedFlight(flight) -> Model(..model, flight:)
    UserUpdatedStart(start) -> Model(..model, start:)
    UserUpdatedReturn(return) -> Model(..model, return:)
  }
}

fn booking(model: Model) -> Result(Booking, Nil) {
  use start <- result.try(parse_date(model.start))
  case model.flight {
    OneWay -> Ok(OneWayBooking(start))
    Return -> {
      use return <- result.try(parse_date(model.return))
      case calendar.naive_date_compare(start, return) {
        order.Gt -> Error(Nil)
        order.Lt | order.Eq -> Ok(ReturnBooking(start:, return:))
      }
    }
  }
}

fn view(model: Model) -> Element(Msg) {
  let flight_options =
    [OneWay, Return]
    |> list.map(format_flight)
    |> list.map(fn(value) {
      html.option([attribute.value(value)], value <> " flight")
    })

  let booking = booking(model)

  html.div([attribute.class("column")], [
    html.select([event.on("input", flight_decoder())], flight_options),
    view_date_input(
      value: model.start,
      disabled: False,
      on_input: UserUpdatedStart,
    ),
    view_date_input(
      value: model.return,
      disabled: model.flight == OneWay,
      on_input: UserUpdatedReturn,
    ),
    html.button(
      [
        attribute.disabled(result.is_error(booking)),
        attribute.attribute("popovertarget", "booking"),
      ],
      [html.text("Book")],
    ),
    html.div([attribute.id("booking"), attribute.attribute("popover", "")], [
      html.text(case booking {
        Ok(booking) -> format_booking(booking)
        Error(_) -> ""
      }),
    ]),
  ])
}

fn view_date_input(
  value value: String,
  disabled disabled: Bool,
  on_input handle_input: fn(String) -> Msg,
) -> Element(Msg) {
  let styles = case parse_date(value), disabled {
    Error(_), False -> [#("background", "lightcoral")]
    _, _ -> []
  }

  html.input([
    attribute.styles(styles),
    attribute.value(value),
    attribute.disabled(disabled),
    event.on_input(handle_input),
  ])
}

fn flight_decoder() -> Decoder(Msg) {
  use value <- decode.subfield(["target", "value"], decode.string)
  case flight_from_string(value) {
    Ok(flight) -> decode.success(UserSelectedFlight(flight))
    Error(_) -> decode.failure(UserSelectedFlight(OneWay), "flight")
  }
}

/// Parses dates in the form `d.m.yyyy`.
fn parse_date(value: String) -> Result(Date, Nil) {
  case string.split(value, ".") {
    [day, month, year] ->
      timestamp.parse_rfc3339(
        year
        <> "-"
        <> string.pad_start(month, to: 2, with: "0")
        <> "-"
        <> string.pad_start(day, to: 2, with: "0")
        <> "T00:00:00Z",
      )
      |> result.map(timestamp.to_calendar(_, calendar.utc_offset))
      |> result.map(pair.first)
    _ -> Error(Nil)
  }
}

fn format_booking(booking: Booking) -> String {
  let details = case booking {
    OneWayBooking(date) -> "one-way flight on " <> format_date(date)
    ReturnBooking(start, return) ->
      "return flight from "
      <> format_date(start)
      <> " to "
      <> format_date(return)
  }

  "You have booked a " <> details <> "."
}

fn format_date(date: Date) -> String {
  let calendar.Date(year, month, day) = date

  string.pad_start(int.to_string(day), to: 2, with: "0")
  <> "."
  <> calendar.month_to_int(month)
  |> int.to_string
  |> string.pad_start(to: 2, with: "0")
  <> "."
  <> int.to_string(year)
}

fn format_flight(flight: Flight) -> String {
  case flight {
    OneWay -> "one-way"
    Return -> "return"
  }
}

fn flight_from_string(s: String) -> Result(Flight, Nil) {
  case s {
    "one-way" -> Ok(OneWay)
    "return" -> Ok(Return)
    _ -> Error(Nil)
  }
}
