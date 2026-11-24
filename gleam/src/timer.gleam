import gleam/dynamic/decode.{type Decoder}
import gleam/float
import gleam/int
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

/// Times are in milliseconds; `elapsed` never exceeds `duration`.
///
/// Whether the timer is running is not stored: it runs exactly while
/// `elapsed < duration`. So lowering the duration below the elapsed time stops
/// it, raising it again resumes it, and a reset restarts it.
type Model {
  Model(elapsed: Float, duration: Float)
}

/// The resolution of the duration slider.
const step_ms = 100

const max_duration_ms = 30_000

fn init(_: flags) -> #(Model, Effect(Msg)) {
  #(Model(elapsed: 0.0, duration: 15_000.0), start_ticking())
}

fn is_running(model: Model) -> Bool {
  model.elapsed <. model.duration
}

type Msg {
  /// An animation frame at `now`, following one at `previous`; both are on
  /// the `performance.now()` clock.
  TimerTicked(previous: Float, now: Float)
  UserUpdatedDuration(Float)
  UserClickedReset
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    // Ticks are measured between real frame timestamps, so a background tab,
    // which gets no frames, catches up on its first frame back.
    TimerTicked(previous:, now:) -> {
      let delta = float.max(0.0, now -. previous)
      let model =
        Model(
          ..model,
          elapsed: float.min(model.duration, model.elapsed +. delta),
        )

      case is_running(model) {
        True -> #(model, tick_after(now))
        False -> #(model, effect.none())
      }
    }

    UserUpdatedDuration(duration) -> {
      let duration =
        float.clamp(duration, min: 0.0, max: int.to_float(max_duration_ms))

      resume(
        model,
        Model(elapsed: float.min(model.elapsed, duration), duration:),
      )
    }

    UserClickedReset -> resume(model, Model(..model, elapsed: 0.0))
  }
}

/// Moves from `before` to `after`, and starts ticking if that starts the
/// timer. While it was already running, the next tick is on its way. If the
/// timer stopped and restarts before that tick arrived, `next_frame` replaces
/// it rather than starting a second tick loop.
fn resume(before: Model, after: Model) -> #(Model, Effect(Msg)) {
  case is_running(before), is_running(after) {
    False, True -> #(after, start_ticking())
    _, _ -> #(after, effect.none())
  }
}

/// Ticks on the next animation frame, measuring from now.
fn start_ticking() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    let now = do_now()
    do_next_frame(fn(next) { dispatch(TimerTicked(previous: now, now: next)) })
  })
}

/// Ticks on the next animation frame, measuring from the frame at `previous`.
fn tick_after(previous: Float) -> Effect(Msg) {
  effect.from(fn(dispatch) {
    do_next_frame(fn(next) { dispatch(TimerTicked(previous:, now: next)) })
  })
}

@external(javascript, "./timer.ffi.mjs", "next_frame")
fn do_next_frame(cb: fn(Float) -> Nil) -> Nil

@external(javascript, "./timer.ffi.mjs", "now")
fn do_now() -> Float

fn view(model: Model) -> Element(Msg) {
  html.div([attribute.class("column")], [
    html.label([], [
      html.text("Elapsed Time:"),
      html.progress(
        [
          attribute.styles([#("width", "15em")]),
          attribute.max(float.to_string(model.duration)),
          attribute.value(float.to_string(model.elapsed)),
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
        attribute.value(float.to_string(model.duration)),
        event.on("input", duration_decoder()),
      ]),
    ]),
    html.button([event.on_click(UserClickedReset)], [html.text("Reset")]),
  ])
}

fn duration_decoder() -> Decoder(Msg) {
  use value <- decode.subfield(["target", "value"], decode.string)
  case int.parse(value) {
    Ok(ms) -> decode.success(UserUpdatedDuration(int.to_float(ms)))
    Error(_) -> decode.failure(UserUpdatedDuration(0.0), "duration")
  }
}

/// Formats as seconds with one decimal, e.g. "12.3s".
fn format_time(ms: Float) -> String {
  let tenths = float.truncate(ms /. 100.0)

  int.to_string(tenths / 10) <> "." <> int.to_string(tenths % 10) <> "s"
}
