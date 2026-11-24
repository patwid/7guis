module Cells.CellRefTest exposing (suite)

import Cells.CellRef as CellRef exposing (CellRef)
import Expect
import Test exposing (Test, describe, test)


ref : String -> CellRef
ref text =
    case CellRef.fromString text of
        Just parsed ->
            parsed

        Nothing ->
            Debug.todo ("not a cell: " ++ text)


suite : Test
suite =
    describe "Cells.CellRef"
        [ test "new rejects out of range" <|
            \_ ->
                [ CellRef.new (-1) 0
                , CellRef.new 0 (-1)
                , CellRef.new CellRef.numCols 0
                , CellRef.new 0 CellRef.numRows
                ]
                    |> Expect.equal [ Nothing, Nothing, Nothing, Nothing ]
        , test "parses" <|
            \_ ->
                [ CellRef.fromString "A0", CellRef.fromString "Z99", CellRef.fromString "B2" ]
                    |> Expect.equal [ CellRef.new 0 0, CellRef.new 25 99, CellRef.new 1 2 ]
        , test "rejects invalid references" <|
            \_ ->
                [ "a1", "A", "A100", "1A", "", "B2+" ]
                    |> List.map CellRef.fromString
                    |> Expect.equal [ Nothing, Nothing, Nothing, Nothing, Nothing, Nothing ]
        , test "next wraps around" <|
            \_ ->
                [ CellRef.next (ref "Z0"), CellRef.next (ref "Z99") ]
                    |> Expect.equal [ ref "A1", ref "A0" ]
        , test "previous wraps around" <|
            \_ ->
                [ CellRef.previous (ref "A1"), CellRef.previous (ref "A0") ]
                    |> Expect.equal [ ref "Z0", ref "Z99" ]
        , test "range is independent of the corners' order" <|
            \_ ->
                [ CellRef.range (ref "A0") (ref "B1"), CellRef.range (ref "B1") (ref "A0") ]
                    |> Expect.equal
                        [ [ ref "A0", ref "A1", ref "B0", ref "B1" ]
                        , [ ref "A0", ref "A1", ref "B0", ref "B1" ]
                        ]
        , test "rows" <|
            \_ ->
                let
                    rows =
                        CellRef.rows

                    first =
                        List.head rows

                    last =
                        List.head (List.reverse rows)
                in
                Expect.all
                    [ \_ -> Expect.equal CellRef.numRows (List.length rows)
                    , \_ -> Expect.equal (Just "0") (Maybe.map .name first)
                    , \_ -> Expect.equal (Just [ ref "A0", ref "B0" ]) (Maybe.map (.cells >> List.take 2) first)
                    , \_ -> Expect.equal (Just CellRef.numCols) (Maybe.map (.cells >> List.length) first)
                    , \_ -> Expect.equal (Just "99") (Maybe.map .name last)
                    , \_ -> Expect.equal (Just (ref "Z99")) (Maybe.andThen (.cells >> List.reverse >> List.head) last)
                    ]
                    ()
        , test "column names" <|
            \_ ->
                let
                    names =
                        CellRef.columnNames
                in
                Expect.all
                    [ \_ -> Expect.equal CellRef.numCols (List.length names)
                    , \_ -> Expect.equal (Just "A") (List.head names)
                    , \_ -> Expect.equal (Just "Z") (List.head (List.reverse names))
                    ]
                    ()
        ]
