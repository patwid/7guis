import gleam/dynamic/decode.{type Decoder}
import gleam/float
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
  let assert Ok(_) = lustre.start(app, "#app", now())

  Nil
}

/// `elapsed` never exceeds `duration`. `last_tick` is when `elapsed` was last
/// brought up to date; the next tick adds the time that really passed since,
/// so late or throttled ticks (e.g. in a background tab) lose no time.
type Model {
  Model(elapsed: Duration, duration: Duration, last_tick: Instant)
}

/// A point in time on the browser's monotonic clock (`performance.now()`,
/// which, unlike the system clock, never jumps). Ticks and DOM events are both
/// stamped with it.
type Instant {
  Instant(since_origin: Duration)
}

/// How often the display is refreshed; it does not affect the measured time.
const tick_ms = 100

/// The resolution of the duration slider.
const step_ms = 100

const max_duration_ms = 30_000

/// Starts measuring at `started`, which `main` reads from the clock, so that
/// `init` needs no access to the current time.
fn init(started: Instant) -> #(Model, Effect(Msg)) {
  #(
    Model(
      elapsed: duration.milliseconds(0),
      duration: duration.seconds(15),
      last_tick: started,
    ),
    every(tick_ms, TimerTicked),
  )
}

fn every(interval: Int, to_msg: fn(Instant) -> Msg) -> Effect(Msg) {
  effect.from(fn(dispatch) {
    do_every(interval, fn(now) { dispatch(to_msg(instant_from_ms(now))) })
  })
}

@external(javascript, "./timer.ffi.mjs", "every")
fn do_every(interval: Int, cb: fn(Float) -> Nil) -> Nil

fn now() -> Instant {
  instant_from_ms(do_now())
}

@external(javascript, "./timer.ffi.mjs", "now")
fn do_now() -> Float

fn instant_from_ms(ms: Float) -> Instant {
  Instant(duration.nanoseconds(float.round(ms *. 1_000_000.0)))
}

fn time_between(earlier: Instant, later: Instant) -> Duration {
  duration.difference(earlier.since_origin, later.since_origin)
}

fn latest(a: Instant, b: Instant) -> Instant {
  case duration.compare(a.since_origin, b.since_origin) {
    order.Lt -> b
    order.Gt | order.Eq -> a
  }
}

type Msg {
  TimerTicked(Instant)
  UserUpdatedDuration(Duration)
  UserResetTimer(Instant)
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    // Ticks keep moving `last_tick` even once the duration is reached, so a
    // longer duration resumes from that moment rather than catching up.
    TimerTicked(now) -> {
      // A tick stamped before a reset can still arrive after it; time must
      // not run backwards then.
      let now = latest(model.last_tick, now)
      let elapsed =
        duration.add(model.elapsed, time_between(model.last_tick, now))
        |> min(model.duration)
      #(Model(..model, elapsed:, last_tick: now), effect.none())
    }

    UserUpdatedDuration(duration) -> {
      let duration = clamp_duration(duration)
      #(
        Model(..model, elapsed: min(model.elapsed, duration), duration:),
        effect.none(),
      )
    }

    UserResetTimer(at) -> #(
      Model(..model, elapsed: duration.milliseconds(0), last_tick: at),
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
  html.div([attribute.class("column")], [
    html.label([], [
      html.text("Elapsed Time:"),
      html.progress(
        [
          attribute.styles([#("width", "15em")]),
          attribute.max(to_ms_string(model.duration)),
          attribute.value(to_ms_string(model.elapsed)),
        ],
        [],
      ),
    ]),
    html.text(format_time(model.elapsed)),
    html.label([], [
      html.text("Duration:"),
      html.input([
        attribute.type_("range"),
        attribute.min("0"),
        attribute.max(int.to_string(max_duration_ms)),
        attribute.step(int.to_string(step_ms)),
        attribute.value(to_ms_string(model.duration)),
        event.on("input", duration_decoder()),
      ]),
    ]),
    html.button([event.on("click", reset_decoder())], [html.text("Reset")]),
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

/// Stamps the reset with the click's `timeStamp`, which is on the same clock
/// as the ticks, so `update` needs no access to the current time.
fn reset_decoder() -> Decoder(Msg) {
  use ms <- decode.field("timeStamp", decode.float)
  decode.success(UserResetTimer(instant_from_ms(ms)))
}

fn to_ms_string(time: Duration) -> String {
  duration.to_milliseconds(time) |> int.to_string
}

/// Formats as seconds with one decimal, e.g. "12.3s".
fn format_time(time: Duration) -> String {
  let ms = duration.to_milliseconds(time)

  int.to_string(ms / 1000) <> "." <> int.to_string(ms % 1000 / 100) <> "s"
}
