import gleam/dict.{type Dict}
import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
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

type Model {
  Model(
    people: Dict(PersonId, Person),
    next_id: Int,
    selected: Option(PersonId),
    draft: Person,
    query: String,
  )
}

/// Identifies a person independently of its position in the (filtered)
/// list. Ids increase monotonically, so they also give the insertion order.
type PersonId {
  PersonId(Int)
}

type Person {
  Person(name: String, surname: String)
}

const empty_person = Person(name: "", surname: "")

fn init(_: flags) -> Model {
  Model(
    people: dict.new(),
    next_id: 0,
    selected: None,
    draft: empty_person,
    query: "",
  )
}

type Msg {
  UserCreatedPerson
  UserUpdatedPerson
  UserDeletedPerson
  UserSelectedPerson(PersonId)
  UserUpdatedName(String)
  UserUpdatedSurname(String)
  UserUpdatedQuery(String)
}

fn update(model: Model, msg: Msg) -> Model {
  case msg, model.selected {
    UserCreatedPerson, _ ->
      Model(
        ..model,
        people: dict.insert(model.people, PersonId(model.next_id), model.draft),
        next_id: model.next_id + 1,
        selected: None,
        draft: empty_person,
      )

    UserUpdatedPerson, Some(id) ->
      Model(
        ..model,
        people: dict.insert(model.people, id, model.draft),
        selected: None,
        draft: empty_person,
      )

    UserDeletedPerson, Some(id) ->
      Model(
        ..model,
        people: dict.delete(model.people, id),
        selected: None,
        draft: empty_person,
      )

    UserSelectedPerson(id), _ ->
      case dict.get(model.people, id) {
        Ok(person) -> Model(..model, selected: Some(id), draft: person)
        Error(_) -> model
      }

    UserUpdatedName(name), _ ->
      Model(..model, draft: Person(..model.draft, name:))

    UserUpdatedSurname(surname), _ ->
      Model(..model, draft: Person(..model.draft, surname:))

    // Deselect a person that is no longer visible with the new filter.
    UserUpdatedQuery(query), selected -> {
      let selected =
        option.then(selected, fn(id) {
          case dict.get(model.people, id) {
            Ok(person) ->
              case matches(person, query) {
                True -> Some(id)
                False -> None
              }
            Error(_) -> None
          }
        })

      Model(..model, selected:, query:)
    }

    // Update and delete need a selection; the buttons are disabled otherwise.
    UserUpdatedPerson, None | UserDeletedPerson, None -> model
  }
}

fn matches(person: Person, query: String) -> Bool {
  string.starts_with(string.lowercase(person.surname), string.lowercase(query))
}

/// The people matching the current filter, in insertion order.
fn visible_people(model: Model) -> List(#(PersonId, Person)) {
  model.people
  |> dict.to_list
  |> list.filter(fn(entry) { matches(entry.1, model.query) })
  |> list.sort(fn(a, b) {
    let PersonId(a) = a.0
    let PersonId(b) = b.0
    int.compare(a, b)
  })
}

fn view(model: Model) -> Element(Msg) {
  let no_selection = option.is_none(model.selected)

  html.div([attribute.class("column")], [
    view_input(
      value: model.query,
      label: "Filter prefix:",
      on_input: UserUpdatedQuery,
    ),
    html.div(
      [attribute.class("row"), attribute.style("align-items", "flex-start")],
      [
        html.select(
          [
            attribute.style("width", "15em"),
            attribute.id("person"),
            attribute.attribute("size", "5"),
            event.on("input", person_id_decoder()),
          ],
          view_person_options(model),
        ),
        html.div(
          [
            attribute.style("display", "grid"),
            attribute.style("grid-template-columns", "auto 1fr"),
            attribute.style("gap", "0.5rem"),
            attribute.style("align-items", "center"),
          ],
          [
            view_grid_input(
              value: model.draft.name,
              label: "Name:",
              on_input: UserUpdatedName,
            ),
            view_grid_input(
              value: model.draft.surname,
              label: "Surname:",
              on_input: UserUpdatedSurname,
            ),
          ],
        ),
      ],
    ),
    html.div([attribute.class("row")], [
      view_button(label: "Create", on_click: UserCreatedPerson, disabled: False),
      view_button(
        label: "Update",
        on_click: UserUpdatedPerson,
        disabled: no_selection,
      ),
      view_button(
        label: "Delete",
        on_click: UserDeletedPerson,
        disabled: no_selection,
      ),
    ]),
  ])
}

fn view_input(
  value value: String,
  label label: String,
  on_input handle_input: fn(String) -> Msg,
) -> Element(Msg) {
  html.label([], [
    html.text(label),
    html.input([attribute.value(value), event.on_input(handle_input)]),
  ])
}

fn view_grid_input(
  value value: String,
  label label: String,
  on_input handle_input: fn(String) -> Msg,
) -> Element(Msg) {
  html.label([attribute.style("display", "contents")], [
    html.text(label),
    html.input([attribute.value(value), event.on_input(handle_input)]),
  ])
}

fn view_button(
  label label: String,
  on_click handle_click: Msg,
  disabled disabled: Bool,
) -> Element(Msg) {
  html.button([event.on_click(handle_click), attribute.disabled(disabled)], [
    html.text(label),
  ])
}

fn view_person_options(model: Model) -> List(Element(Msg)) {
  visible_people(model)
  |> list.map(fn(entry) {
    let #(id, person) = entry
    let PersonId(value) = id

    html.option(
      [
        attribute.value(int.to_string(value)),
        attribute.selected(model.selected == Some(id)),
      ],
      person.surname <> ", " <> person.name,
    )
  })
}

fn person_id_decoder() -> Decoder(Msg) {
  use value <- decode.subfield(["target", "value"], decode.string)
  case int.parse(value) {
    Ok(id) -> decode.success(UserSelectedPerson(PersonId(id)))
    Error(_) -> decode.failure(UserSelectedPerson(PersonId(0)), "person id")
  }
}
