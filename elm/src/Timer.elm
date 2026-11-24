module Timer exposing (main)

import Browser
import Browser.Events
import Html exposing (Html)
import Html.Attributes as Attributes
import Html.Events as Events


main : Program () Model Msg
main =
    Browser.element
        { init = \_ -> ( init, Cmd.none )
        , update = \msg model -> ( update msg model, Cmd.none )
        , view = view
        , subscriptions = subscriptions
        }


{-| Times are in milliseconds; `elapsed` never exceeds `duration`.

Whether the timer is running is not stored: it runs exactly while
`elapsed < duration`. So lowering the duration below the elapsed time stops
it, raising it again resumes it, and a reset restarts it.

-}
type alias Model =
    { elapsed : Float
    , duration : Float
    }


{-| The resolution of the duration slider.
-}
stepMs : Int
stepMs =
    100


maxDurationMs : Float
maxDurationMs =
    30000


init : Model
init =
    { elapsed = 0, duration = 15000 }


isRunning : Model -> Bool
isRunning model =
    model.elapsed < model.duration


type Msg
    = TimerTicked Float
    | UserUpdatedDuration Float
    | UserClickedReset


update : Msg -> Model -> Model
update msg model =
    case msg of
        TimerTicked delta ->
            { model | elapsed = min model.duration (model.elapsed + delta) }

        UserUpdatedDuration duration ->
            let
                clamped =
                    clamp 0 maxDurationMs duration
            in
            { elapsed = min model.elapsed clamped, duration = clamped }

        UserClickedReset ->
            { model | elapsed = 0 }


{-| Animation frame deltas are measured between real timestamps, so a
background tab, which gets no frames, catches up on its first frame back.
-}
subscriptions : Model -> Sub Msg
subscriptions model =
    if isRunning model then
        Browser.Events.onAnimationFrameDelta TimerTicked

    else
        Sub.none


view : Model -> Html Msg
view model =
    Html.div [ Attributes.class "column" ]
        [ Html.label []
            [ Html.text "Elapsed Time:"
            , Html.progress
                [ Attributes.style "width" "15em"
                , Attributes.max (String.fromFloat model.duration)
                , Attributes.value (String.fromFloat model.elapsed)
                ]
                []
            ]
        , Html.text (formatTime model.elapsed)
        , Html.label []
            [ Html.text "Duration:"
            , Html.input
                [ Attributes.type_ "range"
                , Attributes.min "0"
                , Attributes.max (String.fromFloat maxDurationMs)
                , Attributes.step (String.fromInt stepMs)
                , Attributes.value (String.fromFloat model.duration)
                , Events.onInput (String.toFloat >> Maybe.withDefault model.duration >> UserUpdatedDuration)
                ]
                []
            ]
        , Html.button [ Events.onClick UserClickedReset ] [ Html.text "Reset" ]
        ]


{-| Formats as seconds with one decimal, e.g. "12.3s".
-}
formatTime : Float -> String
formatTime ms =
    let
        tenths =
            floor (ms / 100)
    in
    String.fromInt (tenths // 10) ++ "." ++ String.fromInt (modBy 10 tenths) ++ "s"
