import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre
import lustre/attribute.{type Attribute}
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
    selected: Option(PersonId),
    draft: Person,
    query: String,
  )
}

/// The people in creation order, which is also the order they are listed in.
/// Ids increase along the list.
type People =
  List(#(PersonId, Person))

/// Identifies a person independently of its position in the (filtered) list.
type PersonId {
  PersonId(Int)
}

type Person {
  Person(name: String, surname: String)
}

const empty_person = Person(name: "", surname: "")

fn init(_: flags) -> Model {
  Model(people: [], selected: None, draft: empty_person, query: "")
}

type Msg {
  UserClickedCreate
  UserClickedUpdate(PersonId)
  UserClickedDelete(PersonId)
  UserSelectedPerson(PersonId)
  UserUpdatedName(String)
  UserUpdatedSurname(String)
  UserUpdatedQuery(String)
}

fn update(model: Model, msg: Msg) -> Model {
  case msg {
    UserClickedCreate ->
      Model(
        ..model,
        people: list.append(model.people, [
          #(next_id(model.people), model.draft),
        ]),
        selected: None,
        draft: empty_person,
      )

    UserClickedUpdate(id) ->
      Model(
        ..model,
        people: list.map(model.people, fn(entry) {
          case entry.0 == id {
            True -> #(id, model.draft)
            False -> entry
          }
        }),
        selected: None,
        draft: empty_person,
      )

    UserClickedDelete(id) ->
      Model(
        ..model,
        people: list.filter(model.people, fn(entry) { entry.0 != id }),
        selected: None,
        draft: empty_person,
      )

    UserSelectedPerson(id) ->
      case list.key_find(model.people, id) {
        Ok(person) -> Model(..model, selected: Some(id), draft: person)
        Error(_) -> model
      }

    UserUpdatedName(name) -> Model(..model, draft: Person(..model.draft, name:))

    UserUpdatedSurname(surname) ->
      Model(..model, draft: Person(..model.draft, surname:))

    UserUpdatedQuery(query) -> {
      let selection_hidden = case model.selected {
        Some(id) ->
          case list.key_find(model.people, id) {
            Ok(person) -> !matches(person, query)
            Error(_) -> True
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

/// The id for the next person: one more than the newest.
fn next_id(people: People) -> PersonId {
  case list.last(people) {
    Ok(#(PersonId(last), _)) -> PersonId(last + 1)
    Error(_) -> PersonId(0)
  }
}

fn matches(person: Person, query: String) -> Bool {
  string.starts_with(string.lowercase(person.surname), string.lowercase(query))
}

/// The people matching the current filter, in creation order.
fn visible_people(model: Model) -> People {
  list.filter(model.people, fn(entry) { matches(entry.1, model.query) })
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
      view_button(label: "Create", on_click: Some(UserClickedCreate)),
      // Update and delete only exist for a selected person.
      view_button(
        label: "Update",
        on_click: option.map(model.selected, UserClickedUpdate),
      ),
      view_button(
        label: "Delete",
        on_click: option.map(model.selected, UserClickedDelete),
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

/// A button that is disabled when there is nothing for it to send.
fn view_button(
  label label: String,
  on_click on_click: Option(Msg),
) -> Element(Msg) {
  let attributes: List(Attribute(Msg)) = case on_click {
    Some(msg) -> [event.on_click(msg)]
    None -> [attribute.disabled(True)]
  }

  html.button(attributes, [html.text(label)])
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
