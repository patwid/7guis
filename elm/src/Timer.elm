module Timer exposing (main)

import Browser
import Html exposing (Html)
import Html.Attributes as Attributes
import Html.Events as Events
import Task
import Time


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }


{-| Times are in milliseconds; `elapsed` never exceeds `duration`.

`measuredUntil` is the instant `elapsed` is measured up to; the next tick adds
the time that really passed since, so late or throttled ticks (e.g. in a
background tab) lose no time. It is `Nothing` until the clock has been read.

-}
type alias Model =
    { elapsed : Int
    , duration : Int
    , measuredUntil : Maybe Time.Posix
    }


{-| How often the display is refreshed; it does not affect the measured time.
-}
tickMs : Float
tickMs =
    100


{-| The resolution of the duration slider.
-}
stepMs : Int
stepMs =
    100


maxDurationMs : Int
maxDurationMs =
    30000


{-| Starts measuring as soon as the clock has been read, so that `init` needs
no access to the current time.
-}
init : () -> ( Model, Cmd Msg )
init _ =
    ( { elapsed = 0, duration = 15000, measuredUntil = Nothing }
    , readClock
    )


{-| Resets the timer to the current time.
-}
readClock : Cmd Msg
readClock =
    Task.perform TimerReset Time.now


type Msg
    = TimerTicked Time.Posix
    | TimerReset Time.Posix
    | UserUpdatedDuration Int
    | UserClickedReset


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        -- Ticks keep moving `measuredUntil` even once the duration is reached,
        -- so a longer duration resumes from that moment rather than catching up.
        TimerTicked now ->
            case model.measuredUntil of
                Just measuredUntil ->
                    let
                        -- A tick stamped before a reset can still arrive after
                        -- it; time must not run backwards then.
                        until =
                            latest measuredUntil now

                        elapsed =
                            model.elapsed + timeBetween measuredUntil until
                    in
                    ( { model
                        | elapsed = min elapsed model.duration
                        , measuredUntil = Just until
                      }
                    , Cmd.none
                    )

                -- Nothing is measured before the clock has been read.
                Nothing ->
                    ( model, Cmd.none )

        TimerReset at ->
            ( { model | elapsed = 0, measuredUntil = Just at }, Cmd.none )

        UserUpdatedDuration duration ->
            let
                clamped =
                    clamp 0 maxDurationMs duration
            in
            ( { model | elapsed = min model.elapsed clamped, duration = clamped }
            , Cmd.none
            )

        UserClickedReset ->
            ( model, readClock )


timeBetween : Time.Posix -> Time.Posix -> Int
timeBetween earlier later =
    Time.posixToMillis later - Time.posixToMillis earlier


latest : Time.Posix -> Time.Posix -> Time.Posix
latest a b =
    if Time.posixToMillis a < Time.posixToMillis b then
        b

    else
        a


subscriptions : Model -> Sub Msg
subscriptions _ =
    Time.every tickMs TimerTicked


view : Model -> Html Msg
view model =
    Html.div [ Attributes.class "column" ]
        [ Html.label []
            [ Html.text "Elapsed Time:"
            , Html.progress
                [ Attributes.style "width" "15em"
                , Attributes.max (String.fromInt model.duration)
                , Attributes.value (String.fromInt model.elapsed)
                ]
                []
            ]
        , Html.text (formatTime model.elapsed)
        , Html.label []
            [ Html.text "Duration:"
            , Html.input
                [ Attributes.type_ "range"
                , Attributes.min "0"
                , Attributes.max (String.fromInt maxDurationMs)
                , Attributes.step (String.fromInt stepMs)
                , Attributes.value (String.fromInt model.duration)
                , Events.onInput (String.toInt >> Maybe.withDefault model.duration >> UserUpdatedDuration)
                ]
                []
            ]
        , Html.button [ Events.onClick UserClickedReset ] [ Html.text "Reset" ]
        ]


{-| Formats as seconds with one decimal, e.g. "12.3s".
-}
formatTime : Int -> String
formatTime ms =
    String.fromInt (ms // 1000) ++ "." ++ String.fromInt (modBy 1000 ms // 100) ++ "s"
