module Counter exposing (main)

import Browser
import Html exposing (Html)
import Html.Attributes as Attributes
import Html.Events as Events


main : Program () Model Msg
main =
    Browser.sandbox { init = init, update = update, view = view }


type alias Model =
    Int


init : Model
init =
    0


type Msg
    = UserIncrementedCount


update : Msg -> Model -> Model
update msg model =
    case msg of
        UserIncrementedCount ->
            model + 1


view : Model -> Html Msg
view model =
    let
        count =
            String.fromInt model
    in
    Html.div [ Attributes.class "row" ]
        [ Html.input
            [ Attributes.type_ "number"
            , Attributes.style "width" "5em"
            , Attributes.value count
            , Attributes.readonly True
            ]
            []
        , Html.button [ Events.onClick UserIncrementedCount ] [ Html.text "Count" ]
        ]
