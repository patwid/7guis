module Cells exposing (main)

import Browser
import Browser.Dom as Dom
import Cells.CellRef as CellRef exposing (CellRef)
import Cells.Sheet as Sheet exposing (CellError(..), Sheet, Value(..))
import Html exposing (Html)
import Html.Attributes as Attributes
import Html.Events as Events
import Json.Decode as Decode exposing (Decoder)
import Task


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        }



-- TYPES


type alias Model =
    { sheet : Sheet
    , editor : Maybe Editor
    }


type alias Editor =
    { ref : CellRef
    , text : String
    }


type Direction
    = Forward
    | Backward


{-| What happens to the editor's text when the editor closes.
-}
type Closing
    = Commit
    | Discard


type Msg
    = UserDoubleClickedCell CellRef
    | UserClickedCell
    | UserUpdatedFormula String
    | UserFinishedEditing
    | UserCancelledEditing
    | UserPressedTab Direction
      -- Carries the cell of the input that lost focus: the input of a cell that
      -- has already been left (e.g. via Tab) must not close its successor.
    | UserBlurredEditor CellRef
    | EditorFocused


init : () -> ( Model, Cmd Msg )
init _ =
    ( { sheet = Sheet.new, editor = Nothing }, Cmd.none )


editorId : String
editorId =
    "cell-editor"


focusEditor : Cmd Msg
focusEditor =
    Task.attempt (\_ -> EditorFocused) (Dom.focus editorId)



-- UPDATE


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        UserDoubleClickedCell ref ->
            ( model |> closeEditor Commit |> openEditor ref, focusEditor )

        UserClickedCell ->
            ( closeEditor Commit model, Cmd.none )

        UserUpdatedFormula text ->
            ( { model | editor = Maybe.map (\editor -> { editor | text = text }) model.editor }
            , Cmd.none
            )

        UserFinishedEditing ->
            ( closeEditor Commit model, Cmd.none )

        UserCancelledEditing ->
            ( closeEditor Discard model, Cmd.none )

        UserBlurredEditor ref ->
            case model.editor of
                Just editor ->
                    if editor.ref == ref then
                        ( closeEditor Commit model, Cmd.none )

                    else
                        ( model, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        UserPressedTab direction ->
            case model.editor of
                Just editor ->
                    let
                        target =
                            case direction of
                                Forward ->
                                    CellRef.next editor.ref

                                Backward ->
                                    CellRef.previous editor.ref
                    in
                    ( model |> closeEditor Commit |> openEditor target, focusEditor )

                Nothing ->
                    ( model, Cmd.none )

        -- Focusing only fails if the editor is gone, which needs no handling.
        EditorFocused ->
            ( model, Cmd.none )


openEditor : CellRef -> Model -> Model
openEditor ref model =
    { model | editor = Just { ref = ref, text = Sheet.raw model.sheet ref } }


closeEditor : Closing -> Model -> Model
closeEditor closing model =
    case ( model.editor, closing ) of
        ( Just { ref, text }, Commit ) ->
            { sheet = Sheet.set ref text model.sheet, editor = Nothing }

        ( Just _, Discard ) ->
            { model | editor = Nothing }

        ( Nothing, _ ) ->
            model



-- VIEW


view : Model -> Html Msg
view model =
    Html.div
        [ Attributes.style "width" "100%"
        , Attributes.style "height" "calc(100vh - 2rem)"
        , Attributes.style "overflow" "auto"
        , Attributes.style "font-family" "monospace"
        , Attributes.style "font-size" "13px"
        ]
        [ Html.table
            [ Attributes.style "border-collapse" "collapse"
            , Attributes.style "table-layout" "fixed"
            ]
            [ viewHeader
            , Html.tbody [] (List.map (viewRow model) CellRef.rows)
            ]
        ]


viewHeader : Html Msg
viewHeader =
    let
        corner =
            Html.th
                [ Attributes.style "border" "1px solid #ccc"
                , Attributes.style "background" "#e0e0e0"
                , Attributes.style "padding" "2px 4px"
                , Attributes.style "width" "30px"
                , Attributes.style "min-width" "30px"
                , Attributes.style "position" "sticky"
                , Attributes.style "top" "0"
                , Attributes.style "left" "0"
                , Attributes.style "z-index" "3"
                ]
                []

        viewColumnName name =
            Html.th
                [ Attributes.style "border" "1px solid #ccc"
                , Attributes.style "background" "#f0f0f0"
                , Attributes.style "padding" "2px 4px"
                , Attributes.style "width" "80px"
                , Attributes.style "min-width" "80px"
                , Attributes.style "position" "sticky"
                , Attributes.style "top" "0"
                , Attributes.style "z-index" "2"
                ]
                [ Html.text name ]
    in
    Html.thead []
        [ Html.tr [] (corner :: List.map viewColumnName CellRef.columnNames) ]


viewRow : Model -> CellRef.Row -> Html Msg
viewRow model row =
    Html.tr []
        (Html.td
            [ Attributes.style "border" "1px solid #ccc"
            , Attributes.style "background" "#f0f0f0"
            , Attributes.style "padding" "2px 4px"
            , Attributes.style "text-align" "center"
            , Attributes.style "position" "sticky"
            , Attributes.style "left" "0"
            , Attributes.style "z-index" "1"
            ]
            [ Html.text row.name ]
            :: List.map (viewCell model) row.cells
        )


viewCell : Model -> CellRef -> Html Msg
viewCell model ref =
    case model.editor of
        Just editor ->
            if editor.ref == ref then
                viewCellEditing ref editor.text

            else
                viewCellDisplay ref (Sheet.value model.sheet ref)

        Nothing ->
            viewCellDisplay ref (Sheet.value model.sheet ref)


viewCellEditing : CellRef -> String -> Html Msg
viewCellEditing ref text =
    Html.td
        [ Attributes.style "border" "1px solid #4a90d9"
        , Attributes.style "padding" "0"
        ]
        [ Html.input
            [ Attributes.id editorId
            , Attributes.value text
            , Attributes.style "width" "100%"
            , Attributes.style "height" "100%"
            , Attributes.style "border" "none"
            , Attributes.style "outline" "none"
            , Attributes.style "padding" "2px 4px"
            , Attributes.style "font-family" "monospace"
            , Attributes.style "font-size" "13px"
            , Attributes.style "box-sizing" "border-box"
            , Events.onInput UserUpdatedFormula
            , Events.onBlur (UserBlurredEditor ref)
            , Events.custom "keydown" editorKeyDecoder
            ]
            []
        ]


viewCellDisplay : CellRef -> Maybe Value -> Html Msg
viewCellDisplay ref value =
    let
        ( display, styles ) =
            formatValue value
    in
    Html.td
        ([ Attributes.style "border" "1px solid #ccc"
         , Attributes.style "padding" "2px 4px"
         , Attributes.style "overflow" "hidden"
         , Attributes.style "white-space" "nowrap"
         , Attributes.style "text-overflow" "ellipsis"
         , Attributes.style "cursor" "default"
         , Attributes.style "height" "20px"
         , Events.onDoubleClick (UserDoubleClickedCell ref)
         , Events.on "mousedown" (Decode.succeed UserClickedCell)
         ]
            ++ styles
        )
        [ Html.text display ]


formatValue : Maybe Value -> ( String, List (Html.Attribute Msg) )
formatValue value =
    let
        failed code =
            ( code, [ Attributes.style "color" "red" ] )
    in
    case value of
        Nothing ->
            ( "", [] )

        Just (Number n) ->
            ( formatNumber n, [ Attributes.style "text-align" "right" ] )

        Just (Text s) ->
            ( s, [] )

        Just (Failed CircularRef) ->
            failed "#CIRC"

        Just (Failed DivByZero) ->
            failed "#DIV/0"

        Just (Failed TypeError) ->
            failed "#TYPE"

        Just (Failed ParseError) ->
            failed "#ERR"


{-| Rounds to two decimals and drops a zero fraction, so values read `0.3` and
`3` rather than `0.30000000000000004` and `3.0`. Only the display is rounded;
dependent cells compute with the exact value.
-}
formatNumber : Float -> String
formatNumber n =
    let
        rounded =
            toFloat (round (n * 100)) / 100
    in
    if toFloat (round rounded) == rounded then
        String.fromInt (round rounded)

    else
        String.fromFloat rounded


editorKeyDecoder : Decoder { message : Msg, stopPropagation : Bool, preventDefault : Bool }
editorKeyDecoder =
    Decode.map2 Tuple.pair
        (Decode.field "key" Decode.string)
        (Decode.field "shiftKey" Decode.bool)
        |> Decode.andThen
            (\( key, shift ) ->
                case ( key, shift ) of
                    ( "Enter", _ ) ->
                        handle UserFinishedEditing

                    ( "Escape", _ ) ->
                        handle UserCancelledEditing

                    ( "Tab", True ) ->
                        handle (UserPressedTab Backward)

                    ( "Tab", False ) ->
                        handle (UserPressedTab Forward)

                    _ ->
                        Decode.fail "unhandled key"
            )


handle : Msg -> Decoder { message : Msg, stopPropagation : Bool, preventDefault : Bool }
handle msg =
    Decode.succeed { message = msg, stopPropagation = True, preventDefault = True }
