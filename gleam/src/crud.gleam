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
    people: People,
    /// Never reused, so an id always denotes the same person.
    next_id: PersonId,
    /// The id of the person the Update and Delete buttons act on. It only
    /// ever names a person who exists and is visible under the current
    /// filter: Create, Update and Delete clear it, and so does a filter that
    /// hides it.
    selected: Option(PersonId),
    draft: Person,
    query: String,
  )
}

/// The people in creation order, which is also the order they are listed in.
type People =
  List(Entry)

/// A person together with the id it is known by.
type Entry {
  Entry(id: PersonId, person: Person)
}

/// Identifies a person independently of its position in the (filtered) list.
type PersonId {
  PersonId(Int)
}

type Person {
  Person(name: String, surname: String)
}

const empty_person = Person(name: "", surname: "")

fn init(_: flags) -> Model {
  Model(
    people: [],
    next_id: PersonId(0),
    selected: None,
    draft: empty_person,
    query: "",
  )
}

type Msg {
  UserClickedCreate
  UserClickedUpdate
  UserClickedDelete
  UserSelectedPerson(PersonId)
  UserUpdatedName(String)
  UserUpdatedSurname(String)
  UserUpdatedQuery(String)
}

fn update(model: Model, msg: Msg) -> Model {
  case msg {
    UserClickedCreate -> {
      let PersonId(id) = model.next_id

      Model(
        ..model,
        people: list.append(model.people, [
          Entry(id: model.next_id, person: model.draft),
        ]),
        next_id: PersonId(id + 1),
        selected: None,
        draft: empty_person,
      )
    }

    UserClickedUpdate ->
      change_selected(model, fn(people, id) {
        list.map(people, fn(entry) {
          case entry.id == id {
            True -> Entry(..entry, person: model.draft)
            False -> entry
          }
        })
      })

    UserClickedDelete ->
      change_selected(model, fn(people, id) {
        list.filter(people, fn(entry) { entry.id != id })
      })

    UserSelectedPerson(id) ->
      case find_entry(model.people, id) {
        Ok(entry) -> Model(..model, selected: Some(id), draft: entry.person)
        Error(_) -> model
      }

    UserUpdatedName(name) -> Model(..model, draft: Person(..model.draft, name:))

    UserUpdatedSurname(surname) ->
      Model(..model, draft: Person(..model.draft, surname:))

    UserUpdatedQuery(query) -> {
      let selection_hidden = case model.selected {
        Some(id) ->
          case find_entry(model.people, id) {
            Ok(entry) -> !matches(entry.person, query)
            Error(_) -> False
          }
        None -> False
      }

      case selection_hidden {
        // Deselect a person that is no longer visible with the new filter,
        // and drop the form contents that belonged to it.
        True ->
          Model(..model, selected: None, draft: empty_person, query: query)
        False -> Model(..model, query: query)
      }
    }
  }
}

/// Changes the people with the id of the selected person, then clears the
/// selection and the form. `selected` is the only record of which person the
/// buttons act on; without a selection, nothing happens.
fn change_selected(
  model: Model,
  change: fn(People, PersonId) -> People,
) -> Model {
  case model.selected {
    Some(id) ->
      Model(
        ..model,
        people: change(model.people, id),
        selected: None,
        draft: empty_person,
      )
    None -> model
  }
}

fn find_entry(people: People, id: PersonId) -> Result(Entry, Nil) {
  list.find(people, fn(entry) { entry.id == id })
}

fn matches(person: Person, query: String) -> Bool {
  string.starts_with(string.lowercase(person.surname), string.lowercase(query))
}

/// The people matching the current filter, in creation order.
fn visible_people(model: Model) -> People {
  list.filter(model.people, fn(entry) { matches(entry.person, model.query) })
}

fn view(model: Model) -> Element(Msg) {
  html.div([attribute.class("column")], [
    view_input(
      value: model.query,
      label: "Filter prefix:",
      label_attributes: [],
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
            view_input(
              value: model.draft.name,
              label: "Name:",
              label_attributes: grid_row,
              on_input: UserUpdatedName,
            ),
            view_input(
              value: model.draft.surname,
              label: "Surname:",
              label_attributes: grid_row,
              on_input: UserUpdatedSurname,
            ),
          ],
        ),
      ],
    ),
    html.div([attribute.class("row")], [
      view_button(label: "Create", on_click: UserClickedCreate, enabled: True),
      view_button(
        label: "Update",
        on_click: UserClickedUpdate,
        enabled: option.is_some(model.selected),
      ),
      view_button(
        label: "Delete",
        on_click: UserClickedDelete,
        enabled: option.is_some(model.selected),
      ),
    ]),
  ])
}

const grid_row = [#("display", "contents")]

fn view_input(
  value value: String,
  label label: String,
  label_attributes styles: List(#(String, String)),
  on_input handle_input: fn(String) -> Msg,
) -> Element(Msg) {
  html.label([attribute.styles(styles)], [
    html.text(label),
    html.input([attribute.value(value), event.on_input(handle_input)]),
  ])
}

fn view_button(
  label label: String,
  on_click msg: Msg,
  enabled enabled: Bool,
) -> Element(Msg) {
  html.button([attribute.disabled(!enabled), event.on_click(msg)], [
    html.text(label),
  ])
}

fn view_person_options(model: Model) -> List(Element(Msg)) {
  visible_people(model)
  |> list.map(fn(entry) {
    let Entry(id:, person:) = entry
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
