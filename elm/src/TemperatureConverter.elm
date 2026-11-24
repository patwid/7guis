module TemperatureConverter exposing (main)

import Browser
import Html exposing (Html)
import Html.Attributes as Attributes
import Html.Events as Events


main : Program () Model Msg
main =
    Browser.sandbox { init = init, update = update, view = view }


{-| The text of both fields, exactly as shown. Numbers are parsed from it on
demand, so the user's input is never reformatted while typing.
-}
type alias Model =
    { celsius : String
    , fahrenheit : String
    }


{-| The text of a field, parsed into a number of degrees.
-}
type Input
    = Empty
    | Valid Float
    | Invalid


init : Model
init =
    { celsius = "", fahrenheit = "" }


type Msg
    = UserUpdatedCelsius String
    | UserUpdatedFahrenheit String


update : Msg -> Model -> Model
update msg model =
    -- The specification requires: When the user enters a non-numerical
    -- string into TC the value in TF is not updated and vice versa.
    case msg of
        UserUpdatedCelsius text ->
            case parse text of
                Valid celsius ->
                    { celsius = text, fahrenheit = formatNumber (toFahrenheit celsius) }

                Empty ->
                    { model | celsius = text }

                Invalid ->
                    { model | celsius = text }

        UserUpdatedFahrenheit text ->
            case parse text of
                Valid fahrenheit ->
                    { celsius = formatNumber (toCelsius fahrenheit), fahrenheit = text }

                Empty ->
                    { model | fahrenheit = text }

                Invalid ->
                    { model | fahrenheit = text }


parse : String -> Input
parse text =
    case String.trim text of
        "" ->
            Empty

        trimmed ->
            case parseNumber trimmed of
                Just value ->
                    Valid value

                Nothing ->
                    Invalid


{-| Accepts whole numbers as well as decimals, e.g. `-3`, `1.5`. Stricter than
`String.toFloat`, which also reads e.g. `1e3` and `Infinity`.
-}
parseNumber : String -> Maybe Float
parseNumber text =
    let
        digits =
            if String.startsWith "-" text then
                String.dropLeft 1 text

            else
                text
    in
    case String.split "." digits of
        [ whole ] ->
            if isDigits whole then
                String.toFloat text

            else
                Nothing

        [ whole, fraction ] ->
            if isDigits whole && isDigits fraction then
                String.toFloat text

            else
                Nothing

        _ ->
            Nothing


isDigits : String -> Bool
isDigits text =
    not (String.isEmpty text) && String.all Char.isDigit text


toCelsius : Float -> Float
toCelsius fahrenheit =
    (fahrenheit - 32) * (5 / 9)


toFahrenheit : Float -> Float
toFahrenheit celsius =
    celsius * (9 / 5) + 32


{-| Rounds to two decimals and drops a zero fraction, so conversions read
`98.6` and `212` rather than `98.60000000000001` and `212.0`.
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


view : Model -> Html Msg
view model =
    Html.div [ Attributes.class "row" ]
        (List.concat
            [ viewTemperatureInput
                { value = model.celsius
                , label = "Celsius"
                , onInput = UserUpdatedCelsius
                }
            , [ Html.text " = " ]
            , viewTemperatureInput
                { value = model.fahrenheit
                , label = "Fahrenheit"
                , onInput = UserUpdatedFahrenheit
                }
            ]
        )


isInvalid : String -> Bool
isInvalid text =
    parse text == Invalid


viewTemperatureInput :
    { value : String
    , label : String
    , onInput : String -> Msg
    }
    -> List (Html Msg)
viewTemperatureInput { value, label, onInput } =
    let
        invalidStyles =
            if isInvalid value then
                [ Attributes.style "outline" "none"
                , Attributes.style "border" "2px solid red"
                , Attributes.style "border-radius" "0.2em"
                ]

            else
                []
    in
    [ Html.input
        ([ Attributes.style "width" "6em"
         , Attributes.value value
         , Events.onInput onInput
         ]
            ++ invalidStyles
        )
        []
    , Html.text (" " ++ label)
    ]
