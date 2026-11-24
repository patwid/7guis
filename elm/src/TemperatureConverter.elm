module TemperatureConverter exposing (main)

import Browser
import Html exposing (Html)
import Html.Attributes as Attributes
import Html.Events as Events


main : Program () Model Msg
main =
    Browser.sandbox { init = init, update = update, view = view }


{-| Only the field the user last typed into holds their text, exactly as typed,
so it is never reformatted while typing. The other field is derived from
`lastValid`, so the two can never disagree.

`lastValid` is the last temperature entered, in degrees Celsius. It is kept
while the input does not parse, as the specification requires: when the user
enters a non-numerical string into one field, the other is not updated.

-}
type alias Model =
    { source : Scale
    , input : String
    , lastValid : Maybe Float
    }


type Scale
    = Celsius
    | Fahrenheit


init : Model
init =
    { source = Celsius, input = "", lastValid = Nothing }


type Msg
    = UserUpdatedTemperature Scale String


update : Msg -> Model -> Model
update msg model =
    case msg of
        UserUpdatedTemperature scale text ->
            { source = scale
            , input = text
            , lastValid =
                case parse text of
                    Just degrees ->
                        Just (toCelsius scale degrees)

                    Nothing ->
                        model.lastValid
            }


{-| The number of degrees in a field's text; `Nothing` for blank or invalid
text.
-}
parse : String -> Maybe Float
parse text =
    parseNumber (String.trim text)


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


toCelsius : Scale -> Float -> Float
toCelsius scale degrees =
    case scale of
        Celsius ->
            degrees

        Fahrenheit ->
            (degrees - 32) * (5 / 9)


fromCelsius : Scale -> Float -> Float
fromCelsius scale celsius =
    case scale of
        Celsius ->
            celsius

        Fahrenheit ->
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
            [ viewTemperatureInput model Celsius
            , [ Html.text " = " ]
            , viewTemperatureInput model Fahrenheit
            ]
        )


viewTemperatureInput : Model -> Scale -> List (Html Msg)
viewTemperatureInput model scale =
    let
        ( value, invalid ) =
            if scale == model.source then
                ( model.input
                , String.trim model.input /= "" && parse model.input == Nothing
                )

            else
                ( model.lastValid
                    |> Maybe.map (fromCelsius scale >> formatNumber)
                    |> Maybe.withDefault ""
                , False
                )

        invalidStyles =
            if invalid then
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
         , Events.onInput (UserUpdatedTemperature scale)
         ]
            ++ invalidStyles
        )
        []
    , Html.text (" " ++ scaleName scale)
    ]


scaleName : Scale -> String
scaleName scale =
    case scale of
        Celsius ->
            "Celsius"

        Fahrenheit ->
            "Fahrenheit"
