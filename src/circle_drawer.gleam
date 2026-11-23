import gleam/dynamic/decode.{type Decoder}
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import lustre
import lustre/attribute.{type Attribute}
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/element/svg
import lustre/event

pub fn main() {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)

  Nil
}

// --- Types ---

type Model {
  Model(history: History(Circles), interaction: Interaction)
}

/// The circles in creation order, which is also the order they are drawn in
/// (later circles on top). Ids increase along the list.
type Circles =
  List(Entry)

/// A circle together with the id it is known by.
type Entry {
  Entry(id: CircleId, circle: Circle)
}

type CircleId {
  CircleId(Int)
}

type Circle {
  Circle(center: Position, diameter: Int)
}

type Position {
  Position(x: Int, y: Int)
}

/// What the user is currently doing. Each variant carries exactly the data
/// that is meaningful in that state, so e.g. an open dialog always refers to
/// a circle.
///
/// `target` is a snapshot of the circle the menu or dialog is for. It cannot
/// go stale: the history only changes while idle, or as the dialog closes.
type Interaction {
  Idle(pointer: Option(Position))
  MenuOpen(target: Entry)
  /// `diameter` is a preview: the circle in the history keeps its diameter
  /// until the dialog is closed.
  Adjusting(target: Entry, diameter: Int)
}

const default_diameter = 60

const min_diameter = 4

const max_diameter = 200

const menu_id = "menu"

const dialog_id = "dialog"

fn init(_: flags) -> #(Model, Effect(Msg)) {
  #(
    Model(history: history_new([]), interaction: Idle(pointer: None)),
    init_dialog(),
  )
}

fn init_dialog() -> Effect(Msg) {
  effect.from(fn(_) { do_init_dialog() })
}

@external(javascript, "./circle_drawer.ffi.mjs", "init_dialog")
fn do_init_dialog() -> Nil

// --- Update ---

type Msg {
  UserClickedCanvas(Position)
  UserRightClickedCanvas(Position)
  UserMovedMouse(Position)
  UserLeftCanvas
  UserClickedAdjustDiameter
  UserAdjustedDiameter(Int)
  UserClosedMenu
  UserClosedDialog
  UserClickedUndo
  UserClickedRedo
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  #(update_model(model, msg), effect.none())
}

/// Dispatches on the interaction first, so each state lists every message it
/// ignores: a new message has to be handled or explicitly ignored in each.
fn update_model(model: Model, msg: Msg) -> Model {
  case model.interaction {
    Idle(_) -> update_idle(model, msg)
    MenuOpen(target) -> update_menu_open(model, target, msg)
    Adjusting(target, diameter) ->
      update_adjusting(model, target, diameter, msg)
  }
}

fn update_idle(model: Model, msg: Msg) -> Model {
  let circles = model.history.present

  case msg {
    UserClickedCanvas(position) ->
      case circle_at(circles, position) {
        None -> {
          let circle = Circle(center: position, diameter: default_diameter)

          Model(
            history: history_push(
              model.history,
              list.append(circles, [Entry(id: next_id(circles), circle:)]),
            ),
            interaction: Idle(pointer: Some(position)),
          )
        }
        Some(_) -> model
      }

    UserRightClickedCanvas(position) ->
      case circle_at(circles, position) {
        Some(target) -> Model(..model, interaction: MenuOpen(target))
        None -> model
      }

    UserMovedMouse(position) ->
      Model(..model, interaction: Idle(pointer: Some(position)))

    UserLeftCanvas -> Model(..model, interaction: Idle(pointer: None))

    UserClickedUndo -> Model(..model, history: history_undo(model.history))

    UserClickedRedo -> Model(..model, history: history_redo(model.history))

    // The menu and the dialog fire their close events after the model has
    // already closed them; see `on_close`.
    UserClosedMenu | UserClosedDialog -> model

    // Only the menu and the dialog offer these.
    UserClickedAdjustDiameter | UserAdjustedDiameter(_) -> model
  }
}

fn update_menu_open(model: Model, target: Entry, msg: Msg) -> Model {
  case msg {
    UserClickedAdjustDiameter ->
      Model(..model, interaction: Adjusting(target, target.circle.diameter))

    UserClosedMenu -> Model(..model, interaction: Idle(pointer: None))

    // The menu is modal: the canvas and the undo/redo buttons are inert.
    UserClickedCanvas(_)
    | UserRightClickedCanvas(_)
    | UserMovedMouse(_)
    | UserLeftCanvas
    | UserClickedUndo
    | UserClickedRedo
    | UserAdjustedDiameter(_)
    | UserClosedDialog -> model
  }
}

fn update_adjusting(
  model: Model,
  target: Entry,
  diameter: Int,
  msg: Msg,
) -> Model {
  case msg {
    // Only the preview changes while dragging the slider; the history is
    // touched once, when the dialog is closed.
    UserAdjustedDiameter(diameter) ->
      Model(
        ..model,
        interaction: Adjusting(
          target,
          int.clamp(diameter, min: min_diameter, max: max_diameter),
        ),
      )

    UserClosedDialog -> {
      let history = case target.circle.diameter == diameter {
        True -> model.history
        False ->
          history_push(
            model.history,
            set_diameter(model.history.present, target.id, diameter),
          )
      }

      Model(history:, interaction: Idle(pointer: None))
    }

    // The menu fires its close event after the model has already closed it;
    // see `on_close`.
    UserClosedMenu -> model

    // The dialog is modal: the canvas and the undo/redo buttons are inert.
    UserClickedCanvas(_)
    | UserRightClickedCanvas(_)
    | UserMovedMouse(_)
    | UserLeftCanvas
    | UserClickedUndo
    | UserClickedRedo
    | UserClickedAdjustDiameter -> model
  }
}

/// The id for the next circle: one more than the newest. Derived from the
/// circles, so undoing a creation also frees its id.
fn next_id(circles: Circles) -> CircleId {
  case list.last(circles) {
    Ok(Entry(id: CircleId(last), ..)) -> CircleId(last + 1)
    Error(_) -> CircleId(0)
  }
}

fn set_diameter(circles: Circles, id: CircleId, diameter: Int) -> Circles {
  list.map(circles, fn(entry) {
    case entry.id == id {
      True -> Entry(..entry, circle: Circle(..entry.circle, diameter:))
      False -> entry
    }
  })
}

/// The circle nearest to `position` among those containing it; of equally
/// near ones, the topmost.
fn circle_at(circles: Circles, position: Position) -> Option(Entry) {
  circles
  |> list.filter(fn(entry) { contains(entry.circle, position) })
  |> list.fold(None, fn(best: Option(Entry), entry) {
    case best {
      Some(current) ->
        case
          int.compare(
            square_distance(entry.circle.center, position),
            square_distance(current.circle.center, position),
          )
        {
          order.Gt -> best
          order.Lt | order.Eq -> Some(entry)
        }
      None -> Some(entry)
    }
  })
}

fn contains(circle: Circle, position: Position) -> Bool {
  // distance <= diameter / 2, kept in integers to stay exact for odd diameters
  4 * square_distance(circle.center, position)
  <= circle.diameter * circle.diameter
}

fn square_distance(a: Position, b: Position) -> Int {
  let dx = b.x - a.x
  let dy = b.y - a.y

  dx * dx + dy * dy
}

// --- History ---

/// Undo/redo history of snapshots of some state `a`.
type History(a) {
  History(past: List(a), present: a, future: List(a))
}

fn history_new(present: a) -> History(a) {
  History(past: [], present:, future: [])
}

/// Records `present` as a new step, discarding any redoable steps.
fn history_push(history: History(a), present: a) -> History(a) {
  History(past: [history.present, ..history.past], present:, future: [])
}

fn history_undo(history: History(a)) -> History(a) {
  case history.past {
    [] -> history
    [previous, ..past] ->
      History(past:, present: previous, future: [
        history.present,
        ..history.future
      ])
  }
}

fn history_redo(history: History(a)) -> History(a) {
  case history.future {
    [] -> history
    [next, ..future] ->
      History(past: [history.present, ..history.past], present: next, future:)
  }
}

fn history_can_undo(history: History(a)) -> Bool {
  !list.is_empty(history.past)
}

fn history_can_redo(history: History(a)) -> Bool {
  !list.is_empty(history.future)
}

// --- View ---

fn view(model: Model) -> Element(Msg) {
  html.div([attribute.class("column")], [
    html.div([attribute.class("row")], [
      button("Undo", UserClickedUndo, !history_can_undo(model.history)),
      button("Redo", UserClickedRedo, !history_can_redo(model.history)),
    ]),
    svg.svg(
      [
        attribute.styles([#("outline", "1px solid"), #("display", "block")]),
        attribute.attribute("width", "500"),
        attribute.attribute("height", "500"),
        event.on("mousemove", position_decoder() |> decode.map(UserMovedMouse)),
        event.on_mouse_leave(UserLeftCanvas),
        event.on("click", position_decoder() |> decode.map(UserClickedCanvas)),
        event.on(
          "contextmenu",
          position_decoder() |> decode.map(UserRightClickedCanvas),
        )
          |> event.prevent_default,
      ],
      view_circles(model),
    ),
    view_menu(model),
    view_dialog(model),
  ])
}

fn button(label: String, msg: Msg, disabled: Bool) -> Element(Msg) {
  html.button([attribute.disabled(disabled), event.on_click(msg)], [
    html.text(label),
  ])
}

fn view_menu(model: Model) -> Element(Msg) {
  let open = case model.interaction {
    MenuOpen(_) -> True
    _ -> False
  }

  html.dialog(
    [
      attribute.id(menu_id),
      attribute.property("modalopen", json.bool(open)),
      on_backdrop_click(menu_id, UserClosedMenu),
      on_close(UserClosedMenu),
    ],
    [
      html.div([event.on_click(UserClickedAdjustDiameter)], [
        html.text("Adjust diameter.."),
      ]),
    ],
  )
}

fn view_dialog(model: Model) -> Element(Msg) {
  let adjusting = case model.interaction {
    Adjusting(target, diameter) -> Some(Circle(..target.circle, diameter:))
    Idle(_) | MenuOpen(_) -> None
  }

  let content = case adjusting {
    None -> []
    Some(Circle(center:, diameter:)) -> [
      html.label([], [
        html.text(
          "Adjust diameter of circle at ("
          <> int.to_string(center.x)
          <> ", "
          <> int.to_string(center.y)
          <> ")",
        ),
        html.input([
          attribute.type_("range"),
          attribute.min(int.to_string(min_diameter)),
          attribute.max(int.to_string(max_diameter)),
          attribute.value(int.to_string(diameter)),
          event.on("input", diameter_decoder()),
        ]),
      ]),
    ]
  }

  html.dialog(
    [
      attribute.id(dialog_id),
      attribute.property("modalopen", json.bool(option.is_some(adjusting))),
      on_backdrop_click(dialog_id, UserClosedDialog),
      on_close(UserClosedDialog),
    ],
    content,
  )
}

fn view_circles(model: Model) -> List(Element(Msg)) {
  let highlighted = case model.interaction {
    Idle(pointer:) ->
      option.then(pointer, circle_at(model.history.present, _))
      |> option.map(fn(entry) { entry.id })
    MenuOpen(target) | Adjusting(target, _) -> Some(target.id)
  }

  displayed_circles(model)
  |> list.map(fn(entry) {
    let Entry(id:, circle:) = entry
    view_circle(circle, highlighted == Some(id))
  })
}

/// The circles as shown: the one being adjusted has its preview diameter.
fn displayed_circles(model: Model) -> Circles {
  case model.interaction {
    Adjusting(target, diameter) ->
      set_diameter(model.history.present, target.id, diameter)
    Idle(_) | MenuOpen(_) -> model.history.present
  }
}

fn view_circle(circle: Circle, highlighted: Bool) -> Element(Msg) {
  let fill = case highlighted {
    True -> "lightgray"
    False -> "transparent"
  }

  svg.circle([
    attribute.attribute("cx", int.to_string(circle.center.x)),
    attribute.attribute("cy", int.to_string(circle.center.y)),
    attribute.attribute(
      "r",
      float.to_string(int.to_float(circle.diameter) /. 2.0),
    ),
    attribute.attribute("fill", fill),
    attribute.attribute("stroke", "black"),
  ])
}

// --- Event decoders ---

fn position_decoder() -> Decoder(Position) {
  use x <- decode.field("offsetX", decode.int)
  use y <- decode.field("offsetY", decode.int)
  decode.success(Position(x:, y:))
}

fn diameter_decoder() -> Decoder(Msg) {
  use value <- decode.subfield(["target", "value"], decode.string)
  case int.parse(value) {
    Ok(diameter) -> decode.success(UserAdjustedDiameter(diameter))
    Error(_) -> decode.failure(UserAdjustedDiameter(0), "diameter")
  }
}

/// Fires `msg` whenever the dialog closes, however that happens. The browser
/// closes a modal dialog on its own, e.g. on Escape, and the model must follow
/// or it would stay in a state that ignores all canvas input. Closing it from
/// the model fires this too; the message is then ignored, as the interaction
/// has already moved on.
fn on_close(msg: Msg) -> Attribute(Msg) {
  event.on("close", decode.success(msg))
}

/// Fires `msg` only for clicks on the dialog element itself (its backdrop),
/// not for clicks on its content.
fn on_backdrop_click(id: String, msg: Msg) -> Attribute(Msg) {
  event.on("click", {
    use target <- decode.subfield(["target", "id"], decode.string)
    case target == id {
      True -> decode.success(msg)
      False -> decode.failure(msg, "click inside dialog")
    }
  })
}
