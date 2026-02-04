import gleam/int
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

type Model =
  Int

fn init(_: flags) -> Model {
  0
}

type Msg {
  UserIncrementedCount
}

fn update(model: Model, msg: Msg) -> Model {
  case msg {
    UserIncrementedCount -> model + 1
  }
}

fn view(model: Model) -> Element(Msg) {
  let count = int.to_string(model)

  html.div([], [
    html.input([
      attribute.type_("number"),
      attribute.value(count),
      attribute.readonly(True),
    ]),
    html.button([event.on_click(UserIncrementedCount)], [html.text("Count")]),
  ])
}
