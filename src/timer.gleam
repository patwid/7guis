import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/order
import gleam/time/duration.{type Duration}
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub fn main() {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)

  Nil
}

/// `ticked` is the time counted so far. It only advances while below
/// `duration`, but stays as it is when the user shortens the duration, so it
/// may exceed `duration`. What is shown and compared against is `elapsed`.
type Model {
  Model(ticked: Duration, duration: Duration)
}

/// The elapsed time: `ticked`, capped at the current duration.
fn elapsed(model: Model) -> Duration {
  min(model.ticked, model.duration)
}

const tick_ms = 100

const max_duration_ms = 30_000

fn init(_: flags) -> #(Model, Effect(Msg)) {
  #(
    Model(ticked: duration.milliseconds(0), duration: duration.seconds(15)),
    every(tick_ms, TimerTicked),
  )
}

fn every(interval: Int, msg: Msg) -> Effect(Msg) {
  effect.from(fn(dispatch) { do_every(interval, fn() { dispatch(msg) }) })
}

@external(javascript, "./timer.ffi.mjs", "every")
fn do_every(interval: Int, cb: fn() -> Nil) -> Nil

type Msg {
  TimerTicked
  UserUpdatedDuration(Duration)
  UserResetTimer
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    TimerTicked ->
      case duration.compare(elapsed(model), model.duration) {
        order.Lt -> {
          let ticked =
            duration.add(model.ticked, duration.milliseconds(tick_ms))
            |> min(model.duration)
          #(Model(..model, ticked:), effect.none())
        }
        order.Eq | order.Gt -> #(model, effect.none())
      }

    UserUpdatedDuration(duration) -> #(
      Model(..model, duration: clamp_duration(duration)),
      effect.none(),
    )

    UserResetTimer -> #(
      Model(..model, ticked: duration.milliseconds(0)),
      effect.none(),
    )
  }
}

/// Keeps a duration within what the slider offers.
fn clamp_duration(time: Duration) -> Duration {
  duration.to_milliseconds(time)
  |> int.clamp(min: 0, max: max_duration_ms)
  |> duration.milliseconds
}

fn min(a: Duration, b: Duration) -> Duration {
  case duration.compare(a, b) {
    order.Gt -> b
    order.Lt | order.Eq -> a
  }
}

fn view(model: Model) -> Element(Msg) {
  let shown = elapsed(model)

  html.div([attribute.class("column")], [
    html.label([], [
      html.text("Elapsed Time:"),
      html.progress(
        [
          attribute.styles([#("width", "15em")]),
          attribute.max(to_ms_string(model.duration)),
          attribute.value(to_ms_string(shown)),
        ],
        [],
      ),
    ]),
    html.text(format_time(shown)),
    html.label([], [
      html.text("Duration:"),
      html.input([
        attribute.type_("range"),
        attribute.min("0"),
        attribute.max(int.to_string(max_duration_ms)),
        attribute.step(int.to_string(tick_ms)),
        attribute.value(to_ms_string(model.duration)),
        event.on("input", duration_decoder()),
      ]),
    ]),
    html.button([event.on_click(UserResetTimer)], [html.text("Reset")]),
  ])
}

fn duration_decoder() -> Decoder(Msg) {
  use value <- decode.subfield(["target", "value"], decode.string)
  case int.parse(value) {
    Ok(ms) -> decode.success(UserUpdatedDuration(duration.milliseconds(ms)))
    Error(_) ->
      decode.failure(UserUpdatedDuration(duration.milliseconds(0)), "duration")
  }
}

fn to_ms_string(time: Duration) -> String {
  duration.to_milliseconds(time) |> int.to_string
}

/// Formats as seconds with one decimal, e.g. "12.3s".
fn format_time(time: Duration) -> String {
  let ms = duration.to_milliseconds(time)

  int.to_string(ms / 1000) <> "." <> int.to_string(ms % 1000 / 100) <> "s"
}
