module Cells.SheetTest exposing (suite)

import Cells.CellRef as CellRef exposing (CellRef)
import Cells.Sheet as Sheet exposing (CellError(..), Sheet, Value(..))
import Expect
import Test exposing (Test, describe, test)


ref : String -> CellRef
ref text =
    case CellRef.fromString text of
        Just parsed ->
            parsed

        Nothing ->
            Debug.todo ("not a cell: " ++ text)


with : List ( String, String ) -> Sheet -> Sheet
with cells sheet =
    List.foldl (\( at, raw ) -> Sheet.set (ref at) raw) sheet cells


set : String -> String -> Sheet -> Sheet
set at raw =
    Sheet.set (ref at) raw


{-| Checks the values of the given cells.
-}
expectValues : List ( String, Maybe Value ) -> Sheet -> Expect.Expectation
expectValues expected sheet =
    List.map (\( at, _ ) -> ( at, Sheet.value sheet (ref at) )) expected
        |> Expect.equal expected


suite : Test
suite =
    describe "Cells.Sheet"
        [ test "plain contents" <|
            \_ ->
                Sheet.new
                    |> with [ ( "A0", "42" ), ( "A1", "hello" ), ( "A2", "1.5" ), ( "A3", "1e3" ) ]
                    |> expectValues
                        [ ( "A0", Just (Number 42) )
                        , ( "A1", Just (Text "hello") )
                        , ( "A2", Just (Number 1.5) )
                        , ( "A3", Just (Text "1e3") )
                        , ( "A4", Nothing )
                        ]
        , test "raw is kept verbatim" <|
            \_ ->
                let
                    sheet =
                        Sheet.new |> with [ ( "A0", " =add(1,2) " ) ]
                in
                [ Sheet.raw sheet (ref "A0"), Sheet.raw sheet (ref "A1") ]
                    |> Expect.equal [ " =add(1,2) ", "" ]
        , test "arithmetic" <|
            \_ ->
                Sheet.new
                    |> with
                        [ ( "A0", "=add(1,2)" )
                        , ( "A1", "=sub(5,2)" )
                        , ( "A2", "=mul(3,4)" )
                        , ( "A3", "=div(9,2)" )
                        , ( "A4", "=mod(7,4)" )
                        , ( "A5", "=mod(-7,4)" )
                        ]
                    |> expectValues
                        [ ( "A0", Just (Number 3) )
                        , ( "A1", Just (Number 3) )
                        , ( "A2", Just (Number 12) )
                        , ( "A3", Just (Number 4.5) )
                        , ( "A4", Just (Number 3) )
                        , ( "A5", Just (Number 1) )
                        ]
        , test "aggregates over ranges" <|
            \_ ->
                Sheet.new
                    |> with
                        [ ( "A0", "1" )
                        , ( "A1", "2" )
                        , ( "A2", "3" )
                        , ( "B0", "=sum(A0:A2)" )
                        , ( "B1", "=prod(A0:A2, 2)" )
                        ]
                    |> expectValues
                        [ ( "B0", Just (Number 6) )
                        , ( "B1", Just (Number 12) )
                        ]
        , test "empty cells count as zero" <|
            \_ ->
                Sheet.new
                    |> with [ ( "A0", "=add(B0, 1)" ) ]
                    |> expectValues [ ( "A0", Just (Number 1) ) ]
        , test "errors" <|
            \_ ->
                Sheet.new
                    |> with
                        [ ( "A0", "=div(1,0)" )
                        , ( "A1", "=mod(1,0)" )
                        , ( "A2", "text" )
                        , ( "A3", "=add(A2, 1)" )
                        , ( "A4", "=add(1" )
                        , ( "A5", "=add(1,2,3)" )
                        ]
                    |> expectValues
                        [ ( "A0", Just (Failed DivByZero) )
                        , ( "A1", Just (Failed DivByZero) )
                        , ( "A3", Just (Failed TypeError) )
                        , ( "A4", Just (Failed ParseError) )
                        , ( "A5", Just (Failed ParseError) )
                        ]
        , test "errors propagate" <|
            \_ ->
                Sheet.new
                    |> with [ ( "A0", "=div(1,0)" ), ( "A1", "=add(A0, 1)" ) ]
                    |> expectValues [ ( "A1", Just (Failed DivByZero) ) ]
        , test "dependents update transitively" <|
            \_ ->
                let
                    sheet =
                        Sheet.new
                            |> with [ ( "A0", "1" ), ( "A1", "=add(A0,1)" ), ( "A2", "=mul(A1,10)" ) ]
                in
                Expect.all
                    [ expectValues [ ( "A2", Just (Number 20) ) ]
                    , set "A0" "4"
                        >> expectValues [ ( "A1", Just (Number 5) ), ( "A2", Just (Number 50) ) ]
                    ]
                    sheet
        , test "dependents update when defined later" <|
            \_ ->
                Sheet.new
                    |> with [ ( "A1", "=add(A0,1)" ), ( "A0", "7" ) ]
                    |> expectValues [ ( "A1", Just (Number 8) ) ]
        , test "dependents update across ranges" <|
            \_ ->
                Sheet.new
                    |> with [ ( "B0", "=sum(A0:A2)" ), ( "A1", "5" ) ]
                    |> expectValues [ ( "B0", Just (Number 5) ) ]
        , test "changing a formula drops old dependencies" <|
            \_ ->
                let
                    sheet =
                        Sheet.new
                            |> with [ ( "A0", "1" ), ( "B0", "2" ), ( "C0", "=add(A0,1)" ) ]
                            |> set "C0" "=add(B0,1)"
                in
                Expect.all
                    [ expectValues [ ( "C0", Just (Number 3) ) ]

                    -- C0 no longer reads A0, so changing A0 must not touch it.
                    , set "A0" "100" >> expectValues [ ( "C0", Just (Number 3) ) ]
                    , set "B0" "10" >> expectValues [ ( "C0", Just (Number 11) ) ]
                    ]
                    sheet
        , test "clearing a cell" <|
            \_ ->
                let
                    sheet =
                        Sheet.new
                            |> with [ ( "A0", "5" ), ( "A1", "=add(A0,1)" ) ]
                            |> set "A0" "  "
                in
                Expect.all
                    [ \_ -> Expect.equal "" (Sheet.raw sheet (ref "A0"))
                    , expectValues [ ( "A0", Nothing ), ( "A1", Just (Number 1) ) ]
                    ]
                    sheet
        , test "a formula reading a blank cell sees zero" <|
            \_ ->
                Sheet.new
                    |> with [ ( "A0", "=B0" ) ]
                    |> expectValues [ ( "A0", Just (Number 0) ) ]
        , test "a self reference is circular" <|
            \_ ->
                Sheet.new
                    |> with [ ( "A0", "=add(A0,1)" ) ]
                    |> expectValues [ ( "A0", Just (Failed CircularRef) ) ]
        , test "cycles are detected" <|
            \_ ->
                Sheet.new
                    |> with [ ( "A0", "=add(A1,1)" ), ( "A1", "=add(A2,1)" ), ( "A2", "=A0" ) ]
                    |> expectValues
                        [ ( "A0", Just (Failed CircularRef) )
                        , ( "A1", Just (Failed CircularRef) )
                        , ( "A2", Just (Failed CircularRef) )
                        ]
        , test "dependents of a cycle see the error" <|
            \_ ->
                Sheet.new
                    |> with [ ( "A0", "=A1" ), ( "A1", "=A0" ), ( "B0", "=add(A0,1)" ) ]
                    |> expectValues [ ( "B0", Just (Failed CircularRef) ) ]
        , test "breaking a cycle recovers" <|
            \_ ->
                let
                    sheet =
                        Sheet.new |> with [ ( "A0", "=A1" ), ( "A1", "=A0" ) ]
                in
                Expect.all
                    [ expectValues [ ( "A0", Just (Failed CircularRef) ) ]
                    , set "A1" "3"
                        >> expectValues [ ( "A0", Just (Number 3) ), ( "A1", Just (Number 3) ) ]
                    ]
                    sheet
        ]
