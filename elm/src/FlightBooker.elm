module FlightBooker exposing (main)

import Browser
import Html exposing (Html)
import Html.Attributes as Attributes
import Html.Events as Events
import Json.Decode as Decode exposing (Decoder)
import Time


main : Program Flags Model Msg
main =
    Browser.element
        { init = \flags -> ( init flags, Cmd.none )
        , update = \msg model -> ( update msg model, Cmd.none )
        , view = view
        , subscriptions = \_ -> Sub.none
        }


{-| The date fields hold the text exactly as typed; dates are parsed from it
on demand, so the user's input is never reformatted while typing.

`booked` is the booking last made, shown as a confirmation. Any edit clears
it, so it always matches the fields.

-}
type alias Model =
    { flight : Flight
    , start : String
    , return : String
    , booked : Maybe Booking
    }


type Flight
    = OneWay
    | Return


type alias Date =
    { year : Int
    , month : Int
    , day : Int
    }


{-| A booking that passed validation.
-}
type Booking
    = OneWayBooking Date
    | ReturnBooking Date Date


{-| The date fields a flight uses after checking, each with its date or why it
has none. The start date can only be unreadable; only the return date can
also be out of order.
-}
type Checked
    = CheckedOneWay (Maybe Date)
    | CheckedReturn (Maybe Date) (Result ReturnProblem Date)


type ReturnProblem
    = Unreadable
    | BeforeStart


{-| `now` is the current time in milliseconds since the epoch (`Date.now()`),
`zoneOffset` the user's offset from UTC in minutes
(`-new Date().getTimezoneOffset()`).
-}
type alias Flags =
    { now : Int
    , zoneOffset : Int
    }


{-| Starts with both dates set to today, the user's local date, which the page
reads from the clock, so that `init` needs no access to the current time.
-}
init : Flags -> Model
init { now, zoneOffset } =
    let
        today =
            formatDate (dateIn (Time.customZone zoneOffset []) (Time.millisToPosix now))
    in
    { flight = OneWay, start = today, return = today, booked = Nothing }


dateIn : Time.Zone -> Time.Posix -> Date
dateIn zone time =
    { year = Time.toYear zone time
    , month = monthToInt (Time.toMonth zone time)
    , day = Time.toDay zone time
    }


type Msg
    = UserSelectedFlight Flight
    | UserUpdatedStart String
    | UserUpdatedReturn String
    | UserClickedBook


update : Msg -> Model -> Model
update msg model =
    case msg of
        UserSelectedFlight flight ->
            { model | flight = flight, booked = Nothing }

        UserUpdatedStart start ->
            { model | start = start, booked = Nothing }

        UserUpdatedReturn return ->
            { model | return = return, booked = Nothing }

        UserClickedBook ->
            { model | booked = booking (check model) }


{-| Checks every field on its own, so all problems are reported, not just the
first.
-}
check : Model -> Checked
check model =
    let
        start =
            parseDate model.start
    in
    case model.flight of
        OneWay ->
            CheckedOneWay start

        Return ->
            CheckedReturn start (checkReturn start (parseDate model.return))


{-| A return date can only be out of order with a readable start date.
-}
checkReturn : Maybe Date -> Maybe Date -> Result ReturnProblem Date
checkReturn start return =
    case ( start, return ) of
        ( _, Nothing ) ->
            Err Unreadable

        ( Just startDate, Just returnDate ) ->
            if compareDates startDate returnDate == GT then
                Err BeforeStart

            else
                Ok returnDate

        ( Nothing, Just returnDate ) ->
            Ok returnDate


compareDates : Date -> Date -> Order
compareDates a b =
    compare ( a.year, a.month, a.day ) ( b.year, b.month, b.day )


{-| The booking the checked fields make, if every field used has a date.
-}
booking : Checked -> Maybe Booking
booking checked =
    case checked of
        CheckedOneWay (Just start) ->
            Just (OneWayBooking start)

        CheckedReturn (Just start) (Ok return) ->
            Just (ReturnBooking start return)

        CheckedOneWay Nothing ->
            Nothing

        CheckedReturn _ _ ->
            Nothing


view : Model -> Html Msg
view model =
    let
        checked =
            check model

        startProblem =
            case checked of
                CheckedOneWay Nothing ->
                    Just unreadableMessage

                CheckedReturn Nothing _ ->
                    Just unreadableMessage

                _ ->
                    Nothing

        returnProblem =
            case checked of
                CheckedReturn _ (Err Unreadable) ->
                    Just unreadableMessage

                CheckedReturn _ (Err BeforeStart) ->
                    Just "The return date is before the start date"

                _ ->
                    Nothing
    in
    Html.div [ Attributes.class "column" ]
        [ Html.select [ Events.on "input" flightDecoder ]
            (List.map (viewFlightOption model.flight) [ OneWay, Return ])
        , viewDateInput
            { value = model.start
            , problem = startProblem
            , disabled = False
            , onInput = UserUpdatedStart
            }
        , viewDateInput
            { value = model.return
            , problem = returnProblem
            , disabled = model.flight == OneWay
            , onInput = UserUpdatedReturn
            }
        , Html.button
            [ Attributes.disabled (booking checked == Nothing)
            , Events.onClick UserClickedBook
            ]
            [ Html.text "Book" ]
        , case model.booked of
            Just booked ->
                Html.p [] [ Html.text (formatBooking booked) ]

            Nothing ->
                Html.text ""
        ]


unreadableMessage : String
unreadableMessage =
    "Not a date in the form d.m.yyyy"


viewFlightOption : Flight -> Flight -> Html Msg
viewFlightOption selected flight =
    Html.option
        [ Attributes.value (formatFlight flight)
        , Attributes.selected (flight == selected)
        ]
        [ Html.text (formatFlight flight ++ " flight") ]


{-| An invalid field is highlighted and explains its problem on hover.
-}
viewDateInput :
    { value : String
    , problem : Maybe String
    , disabled : Bool
    , onInput : String -> Msg
    }
    -> Html Msg
viewDateInput { value, problem, disabled, onInput } =
    let
        problemAttributes =
            case problem of
                Just message ->
                    [ Attributes.style "background" "lightcoral"
                    , Attributes.title message
                    ]

                Nothing ->
                    []
    in
    Html.input
        ([ Attributes.value value
         , Attributes.disabled disabled
         , Events.onInput onInput
         ]
            ++ problemAttributes
        )
        []


flightDecoder : Decoder Msg
flightDecoder =
    Events.targetValue
        |> Decode.andThen
            (\value ->
                case flightFromString value of
                    Just flight ->
                        Decode.succeed (UserSelectedFlight flight)

                    Nothing ->
                        Decode.fail ("Unknown flight: " ++ value)
            )


{-| Parses dates in the form `d.m.yyyy`, accepting only days that exist.
-}
parseDate : String -> Maybe Date
parseDate value =
    case String.split "." value of
        [ day, month, year ] ->
            Maybe.map3 Date
                (parseDigits 4 4 year)
                (parseDigits 1 2 month)
                (parseDigits 1 2 day)
                |> Maybe.andThen validDate

        _ ->
            Nothing


{-| Parses a number written with between `min` and `max` digits.
-}
parseDigits : Int -> Int -> String -> Maybe Int
parseDigits min max text =
    let
        length =
            String.length text
    in
    if min <= length && length <= max && String.all Char.isDigit text then
        String.toInt text

    else
        Nothing


validDate : Date -> Maybe Date
validDate date =
    if 1 <= date.month && date.month <= 12 && 1 <= date.day && date.day <= daysInMonth date.year date.month then
        Just date

    else
        Nothing


daysInMonth : Int -> Int -> Int
daysInMonth year month =
    case month of
        2 ->
            if isLeapYear year then
                29

            else
                28

        4 ->
            30

        6 ->
            30

        9 ->
            30

        11 ->
            30

        _ ->
            31


isLeapYear : Int -> Bool
isLeapYear year =
    (modBy 4 year == 0 && modBy 100 year /= 0) || modBy 400 year == 0


formatBooking : Booking -> String
formatBooking booked =
    let
        details =
            case booked of
                OneWayBooking date ->
                    "one-way flight on " ++ formatDate date

                ReturnBooking start return ->
                    "return flight from " ++ formatDate start ++ " to " ++ formatDate return
    in
    "You have booked a " ++ details ++ "."


formatDate : Date -> String
formatDate { year, month, day } =
    String.padLeft 2 '0' (String.fromInt day)
        ++ "."
        ++ String.padLeft 2 '0' (String.fromInt month)
        ++ "."
        ++ String.fromInt year


formatFlight : Flight -> String
formatFlight flight =
    case flight of
        OneWay ->
            "one-way"

        Return ->
            "return"


flightFromString : String -> Maybe Flight
flightFromString text =
    case text of
        "one-way" ->
            Just OneWay

        "return" ->
            Just Return

        _ ->
            Nothing


monthToInt : Time.Month -> Int
monthToInt month =
    case month of
        Time.Jan ->
            1

        Time.Feb ->
            2

        Time.Mar ->
            3

        Time.Apr ->
            4

        Time.May ->
            5

        Time.Jun ->
            6

        Time.Jul ->
            7

        Time.Aug ->
            8

        Time.Sep ->
            9

        Time.Oct ->
            10

        Time.Nov ->
            11

        Time.Dec ->
            12
