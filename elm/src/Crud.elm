module Crud exposing (main)

import Browser
import Html exposing (Html)
import Html.Attributes as Attributes
import Html.Events as Events
import Json.Decode as Decode exposing (Decoder)


main : Program () Model Msg
main =
    Browser.sandbox { init = init, update = update, view = view }


{-| `nextId` is never reused, so an id always denotes the same person.

`selected` is the id of the person the Update and Delete buttons act on. It
only ever names a person who exists and is visible under the current filter:
Create, Update and Delete clear it, and so does a filter that hides it.

-}
type alias Model =
    { people : People
    , nextId : PersonId
    , selected : Maybe PersonId
    , draft : Person
    , query : String
    }


{-| The people in creation order, which is also the order they are listed in.
-}
type alias People =
    List Entry


{-| A person together with the id it is known by.
-}
type alias Entry =
    { id : PersonId
    , person : Person
    }


{-| Identifies a person independently of its position in the (filtered) list.
-}
type PersonId
    = PersonId Int


type alias Person =
    { name : String
    , surname : String
    }


emptyPerson : Person
emptyPerson =
    { name = "", surname = "" }


init : Model
init =
    { people = []
    , nextId = PersonId 0
    , selected = Nothing
    , draft = emptyPerson
    , query = ""
    }


type Msg
    = UserClickedCreate
    | UserClickedUpdate
    | UserClickedDelete
    | UserSelectedPerson PersonId
    | UserUpdatedName String
    | UserUpdatedSurname String
    | UserUpdatedQuery String


update : Msg -> Model -> Model
update msg model =
    case msg of
        UserClickedCreate ->
            let
                (PersonId id) =
                    model.nextId
            in
            { model
                | people = model.people ++ [ { id = model.nextId, person = model.draft } ]
                , nextId = PersonId (id + 1)
                , selected = Nothing
                , draft = emptyPerson
            }

        UserClickedUpdate ->
            changeSelected model
                (\id ->
                    List.map
                        (\entry ->
                            if entry.id == id then
                                { entry | person = model.draft }

                            else
                                entry
                        )
                )

        UserClickedDelete ->
            changeSelected model (\id -> List.filter (\entry -> entry.id /= id))

        UserSelectedPerson id ->
            case findEntry model.people id of
                Just entry ->
                    { model | selected = Just id, draft = entry.person }

                Nothing ->
                    model

        UserUpdatedName name ->
            let
                draft =
                    model.draft
            in
            { model | draft = { draft | name = name } }

        UserUpdatedSurname surname ->
            let
                draft =
                    model.draft
            in
            { model | draft = { draft | surname = surname } }

        UserUpdatedQuery query ->
            let
                selectionHidden =
                    case model.selected |> Maybe.andThen (findEntry model.people) of
                        Just entry ->
                            not (matches query entry.person)

                        Nothing ->
                            False
            in
            if selectionHidden then
                -- Deselect a person that is no longer visible with the new
                -- filter, and drop the form contents that belonged to it.
                { model | selected = Nothing, draft = emptyPerson, query = query }

            else
                { model | query = query }


{-| Changes the people with the id of the selected person, then clears the
selection and the form. `selected` is the only record of which person the
buttons act on; without a selection, nothing happens.
-}
changeSelected : Model -> (PersonId -> People -> People) -> Model
changeSelected model change =
    case model.selected of
        Just id ->
            { model
                | people = change id model.people
                , selected = Nothing
                , draft = emptyPerson
            }

        Nothing ->
            model


findEntry : People -> PersonId -> Maybe Entry
findEntry people id =
    List.filter (\entry -> entry.id == id) people
        |> List.head


matches : String -> Person -> Bool
matches query person =
    String.startsWith (String.toLower query) (String.toLower person.surname)


{-| The people matching the current filter, in creation order.
-}
visiblePeople : Model -> People
visiblePeople model =
    List.filter (\entry -> matches model.query entry.person) model.people


view : Model -> Html Msg
view model =
    let
        hasSelection =
            model.selected /= Nothing
    in
    Html.div [ Attributes.class "column" ]
        [ viewInput
            { value = model.query
            , label = "Filter prefix:"
            , labelAttributes = []
            , onInput = UserUpdatedQuery
            }
        , Html.div
            [ Attributes.class "row"
            , Attributes.style "align-items" "flex-start"
            ]
            [ Html.select
                [ Attributes.style "width" "15em"
                , Attributes.id "person"
                , Attributes.size 5
                , Events.on "input" personIdDecoder
                ]
                (viewPersonOptions model)
            , Html.div
                [ Attributes.style "display" "grid"
                , Attributes.style "grid-template-columns" "auto 1fr"
                , Attributes.style "gap" "0.5rem"
                , Attributes.style "align-items" "center"
                ]
                [ viewInput
                    { value = model.draft.name
                    , label = "Name:"
                    , labelAttributes = gridRow
                    , onInput = UserUpdatedName
                    }
                , viewInput
                    { value = model.draft.surname
                    , label = "Surname:"
                    , labelAttributes = gridRow
                    , onInput = UserUpdatedSurname
                    }
                ]
            ]
        , Html.div [ Attributes.class "row" ]
            [ viewButton { label = "Create", onClick = UserClickedCreate, enabled = True }
            , viewButton { label = "Update", onClick = UserClickedUpdate, enabled = hasSelection }
            , viewButton { label = "Delete", onClick = UserClickedDelete, enabled = hasSelection }
            ]
        ]


gridRow : List (Html.Attribute msg)
gridRow =
    [ Attributes.style "display" "contents" ]


viewInput :
    { value : String
    , label : String
    , labelAttributes : List (Html.Attribute Msg)
    , onInput : String -> Msg
    }
    -> Html Msg
viewInput { value, label, labelAttributes, onInput } =
    Html.label labelAttributes
        [ Html.text label
        , Html.input [ Attributes.value value, Events.onInput onInput ] []
        ]


viewButton : { label : String, onClick : Msg, enabled : Bool } -> Html Msg
viewButton { label, onClick, enabled } =
    Html.button [ Attributes.disabled (not enabled), Events.onClick onClick ]
        [ Html.text label ]


viewPersonOptions : Model -> List (Html Msg)
viewPersonOptions model =
    visiblePeople model
        |> List.map
            (\{ id, person } ->
                let
                    (PersonId value) =
                        id
                in
                Html.option
                    [ Attributes.value (String.fromInt value)
                    , Attributes.selected (model.selected == Just id)
                    ]
                    [ Html.text (person.surname ++ ", " ++ person.name) ]
            )


personIdDecoder : Decoder Msg
personIdDecoder =
    Events.targetValue
        |> Decode.andThen
            (\value ->
                case String.toInt value of
                    Just id ->
                        Decode.succeed (UserSelectedPerson (PersonId id))

                    Nothing ->
                        Decode.fail ("Not a person id: " ++ value)
            )
