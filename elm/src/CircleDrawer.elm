port module CircleDrawer exposing (main)

import Browser
import Html exposing (Html)
import Html.Attributes as Attributes
import Html.Events as Events
import Json.Decode as Decode exposing (Decoder)
import Svg exposing (Svg)
import Svg.Attributes


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        }



-- TYPES


{-| `pointer` is where the mouse is over the canvas, if it is. It is kept while
the menu or dialog is open, which make the canvas inert, so that the hovered
circle is highlighted again as soon as they close.
-}
type alias Model =
    { history : History Circles
    , interaction : Interaction
    , pointer : Maybe Position
    }


{-| The circles in creation order, which is also the order they are drawn in
(later circles on top). Ids increase along the list.
-}
type alias Circles =
    List Entry


{-| A circle together with the id it is known by.
-}
type alias Entry =
    { id : CircleId
    , circle : Circle
    }


type CircleId
    = CircleId Int


type alias Circle =
    { center : Position
    , diameter : Int
    }


type alias Position =
    { x : Int
    , y : Int
    }


{-| What the user is currently doing. Each variant carries exactly the data
that is meaningful in that state, so e.g. an open dialog always refers to a
circle.

The entry is a snapshot of the circle the menu or dialog is for. It cannot go
stale: the history only changes while idle, or as the dialog closes.

`Adjusting` also carries the diameter being previewed: the circle in the
history keeps its diameter until the dialog is closed.

-}
type Interaction
    = Idle
    | MenuOpen Entry
    | Adjusting Entry Int


defaultDiameter : Int
defaultDiameter =
    60


minDiameter : Int
minDiameter =
    4


maxDiameter : Int
maxDiameter =
    200


menuId : String
menuId =
    "menu"


dialogId : String
dialogId =
    "dialog"


init : () -> ( Model, Cmd Msg )
init _ =
    ( { history = historyNew [], interaction = Idle, pointer = Nothing }
    , Cmd.none
    )



-- UPDATE


type Msg
    = UserClickedCanvas Position
    | UserRightClickedCanvas Position
    | UserMovedMouse Position
    | UserLeftCanvas
    | UserClickedAdjustDiameter
    | UserAdjustedDiameter Int
    | UserClosedMenu
    | UserClosedDialog
    | UserClickedUndo
    | UserClickedRedo


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    let
        updated =
            updateModel msg model
    in
    ( updated, syncDialogs model.interaction updated.interaction )


{-| Dispatches on the interaction first, so each state lists every message it
ignores: a new message has to be handled or explicitly ignored in each.
-}
updateModel : Msg -> Model -> Model
updateModel msg model =
    case model.interaction of
        Idle ->
            updateIdle msg model

        MenuOpen target ->
            updateMenuOpen target msg model

        Adjusting target diameter ->
            updateAdjusting target diameter msg model


updateIdle : Msg -> Model -> Model
updateIdle msg model =
    let
        circles =
            model.history.present
    in
    case msg of
        UserClickedCanvas position ->
            case circleAt circles position of
                Nothing ->
                    let
                        entry =
                            { id = nextId circles
                            , circle = { center = position, diameter = defaultDiameter }
                            }
                    in
                    { model | history = historyPush (circles ++ [ entry ]) model.history }

                Just _ ->
                    model

        UserRightClickedCanvas position ->
            case circleAt circles position of
                Just target ->
                    { model | interaction = MenuOpen target }

                Nothing ->
                    model

        UserMovedMouse position ->
            { model | pointer = Just position }

        UserLeftCanvas ->
            { model | pointer = Nothing }

        UserClickedUndo ->
            { model | history = historyUndo model.history }

        UserClickedRedo ->
            { model | history = historyRedo model.history }

        -- The menu and the dialog fire their close events after the model has
        -- already closed them; see `viewNativeDialog`.
        UserClosedMenu ->
            model

        UserClosedDialog ->
            model

        -- Only the menu and the dialog offer these.
        UserClickedAdjustDiameter ->
            model

        UserAdjustedDiameter _ ->
            model


updateMenuOpen : Entry -> Msg -> Model -> Model
updateMenuOpen target msg model =
    case msg of
        UserClickedAdjustDiameter ->
            { model | interaction = Adjusting target target.circle.diameter }

        UserClosedMenu ->
            { model | interaction = Idle }

        -- The menu is modal: the canvas and the undo/redo buttons are inert.
        UserClickedCanvas _ ->
            model

        UserRightClickedCanvas _ ->
            model

        UserMovedMouse _ ->
            model

        UserLeftCanvas ->
            model

        UserClickedUndo ->
            model

        UserClickedRedo ->
            model

        UserAdjustedDiameter _ ->
            model

        -- Only the dialog offers this.
        UserClosedDialog ->
            model


updateAdjusting : Entry -> Int -> Msg -> Model -> Model
updateAdjusting target diameter msg model =
    case msg of
        -- Only the preview changes while dragging the slider; the history is
        -- touched once, when the dialog is closed.
        UserAdjustedDiameter adjusted ->
            { model | interaction = Adjusting target (clamp minDiameter maxDiameter adjusted) }

        UserClosedDialog ->
            let
                history =
                    if target.circle.diameter == diameter then
                        model.history

                    else
                        historyPush
                            (setDiameter target.id diameter model.history.present)
                            model.history
            in
            { model | history = history, interaction = Idle }

        -- The dialog is modal: the canvas and the undo/redo buttons are inert.
        UserClickedCanvas _ ->
            model

        UserRightClickedCanvas _ ->
            model

        UserMovedMouse _ ->
            model

        UserLeftCanvas ->
            model

        UserClickedUndo ->
            model

        UserClickedRedo ->
            model

        UserClickedAdjustDiameter ->
            model

        -- The menu fires its close event after the model has already closed
        -- it; see `viewNativeDialog`.
        UserClosedMenu ->
            model


{-| The id for the next circle: one more than the newest. Derived from the
circles, so undoing a creation also frees its id.
-}
nextId : Circles -> CircleId
nextId circles =
    case List.reverse circles of
        { id } :: _ ->
            let
                (CircleId last) =
                    id
            in
            CircleId (last + 1)

        [] ->
            CircleId 0


setDiameter : CircleId -> Int -> Circles -> Circles
setDiameter id diameter =
    List.map
        (\entry ->
            if entry.id == id then
                let
                    circle =
                        entry.circle
                in
                { entry | circle = { circle | diameter = diameter } }

            else
                entry
        )


{-| The circle nearest to `position` among those containing it; of equally
near ones, the topmost.
-}
circleAt : Circles -> Position -> Maybe Entry
circleAt circles position =
    circles
        |> List.filter (\entry -> contains entry.circle position)
        |> List.foldl
            (\entry best ->
                case best of
                    Just current ->
                        if squareDistance entry.circle.center position > squareDistance current.circle.center position then
                            best

                        else
                            Just entry

                    Nothing ->
                        Just entry
            )
            Nothing


contains : Circle -> Position -> Bool
contains circle position =
    -- distance <= diameter / 2, kept in integers to stay exact for odd diameters
    4 * squareDistance circle.center position <= circle.diameter * circle.diameter


squareDistance : Position -> Position -> Int
squareDistance a b =
    let
        dx =
            b.x - a.x

        dy =
            b.y - a.y
    in
    dx * dx + dy * dy



-- HISTORY


{-| Undo/redo history of snapshots of some state `a`.
-}
type alias History a =
    { past : List a
    , present : a
    , future : List a
    }


historyNew : a -> History a
historyNew present =
    { past = [], present = present, future = [] }


{-| Records `present` as a new step, discarding any redoable steps.
-}
historyPush : a -> History a -> History a
historyPush present history =
    { past = history.present :: history.past, present = present, future = [] }


historyUndo : History a -> History a
historyUndo history =
    case history.past of
        [] ->
            history

        previous :: past ->
            { past = past, present = previous, future = history.present :: history.future }


historyRedo : History a -> History a
historyRedo history =
    case history.future of
        [] ->
            history

        next :: future ->
            { past = history.present :: history.past, present = next, future = future }


historyCanUndo : History a -> Bool
historyCanUndo history =
    not (List.isEmpty history.past)


historyCanRedo : History a -> Bool
historyCanRedo history =
    not (List.isEmpty history.future)



-- DIALOGS


{-| Opens (with `showModal`) or closes the native `<dialog>` with the given id;
see `CircleDrawer.ports.js`.
-}
port setDialogOpen : { id : String, open : Bool } -> Cmd msg


{-| The id of the dialog an interaction shows, if any.
-}
openDialog : Interaction -> Maybe String
openDialog interaction =
    case interaction of
        Idle ->
            Nothing

        MenuOpen _ ->
            Just menuId

        Adjusting _ _ ->
            Just dialogId


{-| Opens and closes the native dialogs to follow the interaction, so that
`update` never has to.
-}
syncDialogs : Interaction -> Interaction -> Cmd Msg
syncDialogs before after =
    if openDialog before == openDialog after then
        Cmd.none

    else
        Cmd.batch
            [ openDialog before
                |> Maybe.map (\id -> setDialogOpen { id = id, open = False })
                |> Maybe.withDefault Cmd.none
            , openDialog after
                |> Maybe.map (\id -> setDialogOpen { id = id, open = True })
                |> Maybe.withDefault Cmd.none
            ]



-- VIEW


view : Model -> Html Msg
view model =
    Html.div [ Attributes.class "column" ]
        [ Html.div [ Attributes.class "row" ]
            [ viewButton "Undo" UserClickedUndo (not (historyCanUndo model.history))
            , viewButton "Redo" UserClickedRedo (not (historyCanRedo model.history))
            ]
        , Svg.svg
            [ Attributes.style "outline" "1px solid"
            , Attributes.style "display" "block"
            , Svg.Attributes.width "500"
            , Svg.Attributes.height "500"
            , Events.on "mousemove" (Decode.map UserMovedMouse positionDecoder)
            , Events.onMouseLeave UserLeftCanvas
            , Events.on "click" (Decode.map UserClickedCanvas positionDecoder)
            , Events.preventDefaultOn "contextmenu"
                (Decode.map (\position -> ( UserRightClickedCanvas position, True )) positionDecoder)
            ]
            (viewCircles model)
        , viewMenu
        , viewDialog model
        ]


viewButton : String -> Msg -> Bool -> Html Msg
viewButton label msg disabled =
    Html.button [ Attributes.disabled disabled, Events.onClick msg ] [ Html.text label ]


viewMenu : Html Msg
viewMenu =
    viewNativeDialog menuId
        UserClosedMenu
        [ Html.div
            [ Events.onClick UserClickedAdjustDiameter
            , Attributes.style "cursor" "pointer"
            ]
            [ Html.text "Adjust diameter.." ]
        ]


viewDialog : Model -> Html Msg
viewDialog model =
    viewNativeDialog dialogId
        UserClosedDialog
        (case model.interaction of
            Adjusting target diameter ->
                let
                    center =
                        target.circle.center
                in
                [ Html.label []
                    [ Html.text
                        ("Adjust diameter of circle at ("
                            ++ String.fromInt center.x
                            ++ ", "
                            ++ String.fromInt center.y
                            ++ ")"
                        )
                    , Html.input
                        [ Attributes.type_ "range"
                        , Attributes.min (String.fromInt minDiameter)
                        , Attributes.max (String.fromInt maxDiameter)
                        , Attributes.value (String.fromInt diameter)
                        , Events.onInput (String.toInt >> Maybe.withDefault diameter >> UserAdjustedDiameter)
                        ]
                        []
                    ]
                ]

            Idle ->
                []

            MenuOpen _ ->
                []
        )


{-| A native `<dialog>`, which is always rendered; `syncDialogs` opens it as a
modal, which makes everything behind it inert. Closing it in any way, by the
model, by Escape or by clicking its backdrop, fires `onClose`.
-}
viewNativeDialog : String -> Msg -> List (Html Msg) -> Html Msg
viewNativeDialog id onClose content =
    Html.node "dialog"
        [ Attributes.id id
        , onBackdropClick id onClose
        , Events.on "close" (Decode.succeed onClose)
        ]
        content


viewCircles : Model -> List (Svg Msg)
viewCircles model =
    let
        highlighted =
            case model.interaction of
                Idle ->
                    model.pointer
                        |> Maybe.andThen (circleAt model.history.present)
                        |> Maybe.map .id

                MenuOpen target ->
                    Just target.id

                Adjusting target _ ->
                    Just target.id
    in
    displayedCircles model
        |> List.map (\{ id, circle } -> viewCircle circle (highlighted == Just id))


{-| The circles as shown: the one being adjusted has its preview diameter.
-}
displayedCircles : Model -> Circles
displayedCircles model =
    case model.interaction of
        Adjusting target diameter ->
            setDiameter target.id diameter model.history.present

        Idle ->
            model.history.present

        MenuOpen _ ->
            model.history.present


viewCircle : Circle -> Bool -> Svg Msg
viewCircle circle highlighted =
    Svg.circle
        [ Svg.Attributes.cx (String.fromInt circle.center.x)
        , Svg.Attributes.cy (String.fromInt circle.center.y)
        , Svg.Attributes.r (String.fromFloat (toFloat circle.diameter / 2))
        , Svg.Attributes.fill
            (if highlighted then
                "lightgray"

             else
                "transparent"
            )
        , Svg.Attributes.stroke "black"
        ]
        []



-- EVENT DECODERS


{-| Browsers may report fractional offsets; circles live on whole pixels.
-}
positionDecoder : Decoder Position
positionDecoder =
    Decode.map2 Position
        (Decode.field "offsetX" (Decode.map round Decode.float))
        (Decode.field "offsetY" (Decode.map round Decode.float))


{-| Fires `msg` only for clicks on the dialog element itself (its backdrop),
not for clicks on its content. The backdrop click itself does not close the
dialog; the model does, which then fires its close event.
-}
onBackdropClick : String -> Msg -> Html.Attribute Msg
onBackdropClick id msg =
    Events.on "click"
        (Decode.at [ "target", "id" ] Decode.string
            |> Decode.andThen
                (\target ->
                    if target == id then
                        Decode.succeed msg

                    else
                        Decode.fail "click inside the dialog"
                )
        )
