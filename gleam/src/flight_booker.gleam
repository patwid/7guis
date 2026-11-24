import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
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
  let #(today, _) =
    timestamp.system_time() |> timestamp.to_calendar(calendar.local_offset())

  let app = lustre.simple(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", today)

  Nil
}

/// The date fields hold the text exactly as typed; dates are parsed from it
/// on demand, so the user's input is never reformatted while typing.
///
/// `booked` is the booking last made, shown as a confirmation. Any edit
/// clears it, so it always matches the fields.
type Model {
  Model(flight: Flight, start: String, return: String, booked: Option(Booking))
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

/// The date fields a flight uses after checking, each with its date or why it
/// has none. The start date can only be unreadable; only the return date can
/// also be out of order.
type Checked {
  CheckedOneWay(start: Result(Date, Nil))
  CheckedReturn(start: Result(Date, Nil), return: Result(Date, ReturnProblem))
}

type ReturnProblem {
  Unreadable
  BeforeStart
}

/// Starts with both dates set to `today`, the user's local date.
fn init(today: Date) -> Model {
  let today = format_date(today)

  Model(flight: OneWay, start: today, return: today, booked: None)
}

type Msg {
  UserSelectedFlight(Flight)
  UserUpdatedStart(String)
  UserUpdatedReturn(String)
  UserClickedBook
}

fn update(model: Model, msg: Msg) -> Model {
  case msg {
    UserSelectedFlight(flight) -> Model(..model, flight:, booked: None)
    UserUpdatedStart(start) -> Model(..model, start:, booked: None)
    UserUpdatedReturn(return) -> Model(..model, return:, booked: None)
    UserClickedBook -> Model(..model, booked: booking(check(model)))
  }
}

/// Checks every field on its own, so all problems are reported, not just the
/// first.
fn check(model: Model) -> Checked {
  let start = parse_date(model.start)

  case model.flight {
    OneWay -> CheckedOneWay(start:)
    Return ->
      CheckedReturn(
        start:,
        return: check_return(start, parse_date(model.return)),
      )
  }
}

/// A return date can only be out of order with a readable start date.
fn check_return(
  start: Result(Date, Nil),
  return: Result(Date, Nil),
) -> Result(Date, ReturnProblem) {
  case start, return {
    _, Error(_) -> Error(Unreadable)
    Ok(start), Ok(return) ->
      case calendar.naive_date_compare(start, return) {
        order.Gt -> Error(BeforeStart)
        order.Lt | order.Eq -> Ok(return)
      }
    Error(_), Ok(return) -> Ok(return)
  }
}

/// The booking the checked fields make, if every field used has a date.
fn booking(checked: Checked) -> Option(Booking) {
  case checked {
    CheckedOneWay(start: Ok(start)) -> Some(OneWayBooking(start))
    CheckedReturn(start: Ok(start), return: Ok(return)) ->
      Some(ReturnBooking(start:, return:))
    CheckedOneWay(..) | CheckedReturn(..) -> None
  }
}

fn view(model: Model) -> Element(Msg) {
  let flight_options =
    [OneWay, Return]
    |> list.map(fn(flight) {
      html.option(
        [
          attribute.value(format_flight(flight)),
          attribute.selected(flight == model.flight),
        ],
        format_flight(flight) <> " flight",
      )
    })

  let checked = check(model)
  let booking = booking(checked)

  let start_problem = case checked.start {
    Ok(_) -> None
    Error(_) -> Some(unreadable_message)
  }
  let return_problem = case checked {
    CheckedReturn(return: Error(Unreadable), ..) -> Some(unreadable_message)
    CheckedReturn(return: Error(BeforeStart), ..) ->
      Some("The return date is before the start date")
    CheckedReturn(return: Ok(_), ..) | CheckedOneWay(..) -> None
  }

  html.div([attribute.class("column")], [
    html.select([event.on("input", flight_decoder())], flight_options),
    view_date_input(
      value: model.start,
      problem: start_problem,
      disabled: False,
      on_input: UserUpdatedStart,
    ),
    view_date_input(
      value: model.return,
      problem: return_problem,
      disabled: model.flight == OneWay,
      on_input: UserUpdatedReturn,
    ),
    html.button(
      [
        attribute.disabled(option.is_none(booking)),
        event.on_click(UserClickedBook),
      ],
      [html.text("Book")],
    ),
    case model.booked {
      Some(booked) -> html.p([], [html.text(format_booking(booked))])
      None -> element.none()
    },
  ])
}

const unreadable_message = "Not a date in the form d.m.yyyy"

/// An invalid field is highlighted and explains its problem on hover.
fn view_date_input(
  value value: String,
  problem problem: Option(String),
  disabled disabled: Bool,
  on_input handle_input: fn(String) -> Msg,
) -> Element(Msg) {
  let problem_attributes = case problem {
    Some(message) -> [
      attribute.style("background", "lightcoral"),
      attribute.title(message),
    ]
    None -> []
  }

  html.input([
    attribute.value(value),
    attribute.disabled(disabled),
    event.on_input(handle_input),
    ..problem_attributes
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
