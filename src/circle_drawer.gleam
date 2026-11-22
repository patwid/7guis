import gleam/dict.{type Dict}
import gleam/dynamic/decode.{type Decoder}
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
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
  Model(history: History(Circles), next_id: Int, interaction: Interaction)
}

type Circles =
  Dict(CircleId, Circle)

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
  Adjusting(circle: CircleId, original_diameter: Int)
}

const default_diameter = 60

const menu_id = "menu"

const dialog_id = "dialog"

fn init(_: flags) -> #(Model, Effect(Msg)) {
  #(
    Model(
      history: history_new(dict.new()),
      next_id: 0,
      interaction: Idle(hovered: None),
    ),
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
      let id = CircleId(model.next_id)
      let circle = Circle(center: position, diameter: default_diameter)

      Model(
        history: history_push(model.history, dict.insert(circles, id, circle)),
        next_id: model.next_id + 1,
        interaction: Idle(hovered: Some(id)),
      )
    }

    UserRightClickedCanvas, Idle(hovered: Some(id)) ->
      Model(..model, interaction: MenuOpen(id))

    UserMovedMouse(position), Idle(_) ->
      Model(..model, interaction: Idle(hovered: circle_at(circles, position)))

    UserLeftCanvas, Idle(_) -> Model(..model, interaction: Idle(hovered: None))

    UserClickedAdjustDiameter, MenuOpen(id) ->
      case dict.get(circles, id) {
        Ok(circle) ->
          Model(..model, interaction: Adjusting(id, circle.diameter))
        Error(_) -> Model(..model, interaction: Idle(hovered: None))
      }

    UserClosedMenu, MenuOpen(_) ->
      Model(..model, interaction: Idle(hovered: None))

    // Live preview while dragging the slider: changes the present state
    // without recording history; the change is committed on close.
    UserAdjustedDiameter(diameter), Adjusting(id, _) ->
      Model(
        ..model,
        history: history_replace(
          model.history,
          set_diameter(circles, id, diameter),
        ),
      )

    UserClosedDialog, Adjusting(id, original_diameter) -> {
      let history = case dict.get(circles, id) {
        Ok(circle) if circle.diameter != original_diameter ->
          model.history
          |> history_replace(set_diameter(circles, id, original_diameter))
          |> history_push(circles)
        _ -> model.history
      }

      Model(..model, history:, interaction: Idle(hovered: None))
    }

    UserClickedUndo, Idle(_) ->
      Model(
        ..model,
        history: history_undo(model.history),
        interaction: Idle(hovered: None),
      )

    UserClickedRedo, Idle(_) ->
      Model(
        ..model,
        history: history_redo(model.history),
        interaction: Idle(hovered: None),
      )

    // Any other combination is not meaningful in the current interaction
    // state (e.g. hovering while a modal dialog is open) and is ignored.
    _, _ -> model
  }
}

fn set_diameter(circles: Circles, id: CircleId, diameter: Int) -> Circles {
  case dict.get(circles, id) {
    Ok(circle) -> dict.insert(circles, id, Circle(..circle, diameter:))
    Error(_) -> circles
  }
}

/// The circle nearest to `position` among those containing it.
fn circle_at(circles: Circles, position: Position) -> Option(CircleId) {
  circles
  |> dict.to_list
  |> list.filter(fn(entry) { contains(entry.1, position) })
  |> list.sort(fn(a, b) {
    int.compare(
      square_distance(a.1.center, position),
      square_distance(b.1.center, position),
    )
  })
  |> list.first
  |> option.from_result
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

/// Replaces the present state without recording a step.
fn history_replace(history: History(a), present: a) -> History(a) {
  History(..history, present:)
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
    Adjusting(id, _) ->
      dict.get(model.history.present, id) |> option.from_result
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
          attribute.min("4"),
          attribute.max("200"),
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

  model.history.present
  |> dict.to_list
  |> list.map(fn(entry) {
    let #(id, circle) = entry
    view_circle(circle, highlighted == Some(id))
  })
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
