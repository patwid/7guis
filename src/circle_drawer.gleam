import gleam/dynamic/decode.{type Decoder}
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
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
  List(#(CircleId, Circle))

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
type Interaction {
  Idle(hovered: Option(CircleId))
  MenuOpen(circle: CircleId)
  /// `diameter` is a preview: the circle in the history keeps its diameter
  /// until the dialog is closed.
  Adjusting(circle: CircleId, diameter: Int)
}

const default_diameter = 60

const min_diameter = 4

const max_diameter = 200

const menu_id = "menu"

const dialog_id = "dialog"

fn init(_: flags) -> #(Model, Effect(Msg)) {
  #(
    Model(history: history_new([]), interaction: Idle(hovered: None)),
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
  UserRightClickedCanvas
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

fn update_model(model: Model, msg: Msg) -> Model {
  let circles = model.history.present

  case msg, model.interaction {
    UserClickedCanvas(position), Idle(hovered: None) -> {
      let id = next_id(circles)
      let circle = Circle(center: position, diameter: default_diameter)

      Model(
        history: history_push(
          model.history,
          list.append(circles, [#(id, circle)]),
        ),
        interaction: Idle(hovered: Some(id)),
      )
    }

    UserRightClickedCanvas, Idle(hovered: Some(id)) ->
      Model(..model, interaction: MenuOpen(id))

    UserMovedMouse(position), Idle(_) ->
      Model(..model, interaction: Idle(hovered: circle_at(circles, position)))

    UserLeftCanvas, Idle(_) -> Model(..model, interaction: Idle(hovered: None))

    UserClickedAdjustDiameter, MenuOpen(id) ->
      case list.key_find(circles, id) {
        Ok(circle) ->
          Model(..model, interaction: Adjusting(id, circle.diameter))
        // The menu only opens for an existing circle and the history cannot
        // change while it is open.
        Error(_) -> model
      }

    UserClosedMenu, MenuOpen(_) ->
      Model(..model, interaction: Idle(hovered: None))

    // Only the preview changes while dragging the slider; the history is
    // touched once, when the dialog is closed.
    UserAdjustedDiameter(diameter), Adjusting(id, _) ->
      Model(
        ..model,
        interaction: Adjusting(
          id,
          int.clamp(diameter, min: min_diameter, max: max_diameter),
        ),
      )

    UserClosedDialog, Adjusting(id, diameter) -> {
      let history = case list.key_find(circles, id) {
        Ok(circle) if circle.diameter != diameter ->
          history_push(model.history, set_diameter(circles, id, diameter))
        _ -> model.history
      }

      Model(history:, interaction: Idle(hovered: None))
    }

    UserClickedUndo, Idle(_) ->
      Model(
        history: history_undo(model.history),
        interaction: Idle(hovered: None),
      )

    UserClickedRedo, Idle(_) ->
      Model(
        history: history_redo(model.history),
        interaction: Idle(hovered: None),
      )

    // Any other combination is not meaningful in the current interaction
    // state (e.g. hovering while a modal dialog is open) and is ignored.
    _, _ -> model
  }
}

/// The id for the next circle: one more than the newest. Derived from the
/// circles, so undoing a creation also frees its id.
fn next_id(circles: Circles) -> CircleId {
  case list.last(circles) {
    Ok(#(CircleId(last), _)) -> CircleId(last + 1)
    Error(_) -> CircleId(0)
  }
}

fn set_diameter(circles: Circles, id: CircleId, diameter: Int) -> Circles {
  list.map(circles, fn(entry) {
    case entry.0 == id {
      True -> #(id, Circle(..entry.1, diameter:))
      False -> entry
    }
  })
}

/// The circle nearest to `position` among those containing it; of equally
/// near ones, the topmost.
fn circle_at(circles: Circles, position: Position) -> Option(CircleId) {
  circles
  |> list.filter(fn(entry) { contains(entry.1, position) })
  |> list.fold(None, fn(best: Option(#(CircleId, Circle)), entry) {
    case best {
      Some(current) ->
        case
          int.compare(
            square_distance(entry.1.center, position),
            square_distance(current.1.center, position),
          )
        {
          order.Gt -> best
          order.Lt | order.Eq -> Some(entry)
        }
      None -> Some(entry)
    }
  })
  |> option.map(fn(entry) { entry.0 })
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
        event.on("contextmenu", decode.success(UserRightClickedCanvas))
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
    Adjusting(id, diameter) ->
      list.key_find(model.history.present, id)
      |> result.map(fn(circle) { Circle(..circle, diameter:) })
      |> option.from_result
    _ -> None
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
    ],
    content,
  )
}

fn view_circles(model: Model) -> List(Element(Msg)) {
  let highlighted = case model.interaction {
    Idle(hovered:) -> hovered
    MenuOpen(id) | Adjusting(id, _) -> Some(id)
  }

  displayed_circles(model)
  |> list.map(fn(entry) {
    let #(id, circle) = entry
    view_circle(circle, highlighted == Some(id))
  })
}

/// The circles as shown: the one being adjusted has its preview diameter.
fn displayed_circles(model: Model) -> Circles {
  case model.interaction {
    Adjusting(id, diameter) -> set_diameter(model.history.present, id, diameter)
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
