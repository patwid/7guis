module Cells.FormulaTest exposing (suite)

import Cells.CellRef as CellRef exposing (CellRef)
import Cells.Formula as Formula exposing (AggOp(..), Arg(..), BinOp(..), Expr(..))
import Expect
import Test exposing (Test, describe, test)


ref : Int -> Int -> CellRef
ref col row =
    case CellRef.new col row of
        Just new ->
            new

        Nothing ->
            Debug.todo "cell out of range"


suite : Test
suite =
    describe "Cells.Formula"
        [ test "parses literals" <|
            \_ ->
                [ Formula.parse "1", Formula.parse "-2.5", Formula.parse "  3  " ]
                    |> Expect.equal [ Just (Literal 1), Just (Literal -2.5), Just (Literal 3) ]
        , test "parses references" <|
            \_ ->
                Formula.parse "B2"
                    |> Expect.equal (Just (Ref (ref 1 2)))
        , test "parses binary calls" <|
            \_ ->
                [ Formula.parse "add(1, A0)", Formula.parse "div(add(1,2),3)", Formula.parse "sub ( 1 , 2 )" ]
                    |> Expect.equal
                        [ Just (Binary Add (Literal 1) (Ref (ref 0 0)))
                        , Just (Binary Div (Binary Add (Literal 1) (Literal 2)) (Literal 3))
                        , Just (Binary Sub (Literal 1) (Literal 2))
                        ]
        , test "parses aggregates" <|
            \_ ->
                [ Formula.parse "sum(A0:B1, 3)", Formula.parse "prod()" ]
                    |> Expect.equal
                        [ Just (Aggregate Sum [ Range (ref 0 0) (ref 1 1), Single (Literal 3) ])
                        , Just (Aggregate Prod [])
                        ]
        , test "rejects wrong arity" <|
            \_ ->
                [ "add(1)", "add(1,2,3)", "add()" ]
                    |> List.map Formula.parse
                    |> Expect.equal [ Nothing, Nothing, Nothing ]
        , test "rejects ranges as binary operands" <|
            \_ ->
                Formula.parse "add(A0:A3, 1)"
                    |> Expect.equal Nothing
        , test "rejects malformed input" <|
            \_ ->
                [ "", "foo(1)", "add(1,2", "1 2", "A100", "1e3", "1.", "sum(1,)" ]
                    |> List.map Formula.parse
                    |> Expect.equal [ Nothing, Nothing, Nothing, Nothing, Nothing, Nothing, Nothing, Nothing ]
        , test "refs" <|
            \_ ->
                Formula.parse "add(A0, sum(B0:B1))"
                    |> Maybe.map Formula.refs
                    |> Expect.equal (Just [ ref 0 0, ref 1 0, ref 1 1 ])
        ]
