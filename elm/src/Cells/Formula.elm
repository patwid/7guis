module Cells.Formula exposing
    ( Expr(..), Arg(..), BinOp(..), AggOp(..)
    , parse, refs, number
    )

{-| The expression language of cell formulas (the part after `=`).

@docs Expr, Arg, BinOp, AggOp
@docs parse, refs, number

-}

import Cells.CellRef as CellRef exposing (CellRef)
import Parser exposing ((|.), (|=), Parser)


type Expr
    = Literal Float
    | Ref CellRef
      -- A function of exactly two operands.
    | Binary BinOp Expr Expr
      -- A function folding any number of arguments, including ranges.
    | Aggregate AggOp (List Arg)


{-| An argument of an aggregate. Ranges are only meaningful here, so they are
not an `Expr`.
-}
type Arg
    = Single Expr
    | Range CellRef CellRef


type BinOp
    = Add
    | Sub
    | Mul
    | Div
    | Mod


type AggOp
    = Sum
    | Prod


{-| All cells the expression reads; a cell read more than once is listed more
than once.
-}
refs : Expr -> List CellRef
refs expr =
    case expr of
        Literal _ ->
            []

        Ref ref ->
            [ ref ]

        Binary _ left right ->
            refs left ++ refs right

        Aggregate _ args ->
            List.concatMap
                (\arg ->
                    case arg of
                        Single single ->
                            refs single

                        Range from to ->
                            CellRef.range from to
                )
                args



-- PARSER


{-| Parses a whole formula; trailing input is an error.
-}
parse : String -> Maybe Expr
parse input =
    Parser.run (Parser.succeed identity |. Parser.spaces |= expression |. Parser.spaces |. Parser.end) input
        |> Result.toMaybe


expression : Parser Expr
expression =
    Parser.oneOf
        [ Parser.map Literal number
        , call
        , Parser.map Ref CellRef.parser
        ]


{-| An integer or decimal number, e.g. `42`, `-1.5`. Stricter than
`String.toFloat`, which also reads e.g. `1e3` and `Infinity`.
-}
number : Parser Float
number =
    Parser.getChompedString
        (Parser.succeed ()
            |. Parser.oneOf [ Parser.chompIf ((==) '-'), Parser.succeed () ]
            |. Parser.chompIf Char.isDigit
            |. Parser.chompWhile Char.isDigit
            |. Parser.oneOf
                [ Parser.chompIf ((==) '.')
                    |. Parser.chompIf Char.isDigit
                    |. Parser.chompWhile Char.isDigit
                , Parser.succeed ()
                ]
        )
        |> Parser.andThen
            (\text ->
                case String.toFloat text of
                    Just n ->
                        Parser.succeed n

                    Nothing ->
                        Parser.problem ("Not a number: " ++ text)
            )


{-| What a function name stands for, before its arguments are checked.
-}
type Function
    = Operator BinOp
    | Reducer AggOp


functionFromName : String -> Maybe Function
functionFromName name =
    case name of
        "add" ->
            Just (Operator Add)

        "sub" ->
            Just (Operator Sub)

        "mul" ->
            Just (Operator Mul)

        "div" ->
            Just (Operator Div)

        "mod" ->
            Just (Operator Mod)

        "sum" ->
            Just (Reducer Sum)

        "prod" ->
            Just (Reducer Prod)

        _ ->
            Nothing


call : Parser Expr
call =
    Parser.succeed Tuple.pair
        |= functionName
        |. Parser.spaces
        |= Parser.sequence
            { start = "("
            , separator = ","
            , end = ")"
            , spaces = Parser.spaces
            , item = Parser.lazy (\_ -> argument)
            , trailing = Parser.Forbidden
            }
        |> Parser.andThen
            (\( function, args ) ->
                case buildCall function args of
                    Just built ->
                        Parser.succeed built

                    Nothing ->
                        Parser.problem "Wrong arguments"
            )


functionName : Parser Function
functionName =
    Parser.getChompedString
        (Parser.chompIf Char.isLower |. Parser.chompWhile Char.isLower)
        |> Parser.andThen
            (\name ->
                case functionFromName name of
                    Just function ->
                        Parser.succeed function

                    Nothing ->
                        Parser.problem ("Unknown function: " ++ name)
            )


{-| Checks the arguments against what the function accepts, so that a call
with the wrong arity or a range operand never becomes an `Expr`.
-}
buildCall : Function -> List Arg -> Maybe Expr
buildCall function args =
    case ( function, args ) of
        ( Operator op, [ Single left, Single right ] ) ->
            Just (Binary op left right)

        ( Operator _, _ ) ->
            Nothing

        ( Reducer op, _ ) ->
            Just (Aggregate op args)


argument : Parser Arg
argument =
    Parser.oneOf
        [ CellRef.parser
            |> Parser.andThen
                (\from ->
                    Parser.oneOf
                        [ Parser.succeed (Range from)
                            |. Parser.backtrackable Parser.spaces
                            |. Parser.symbol ":"
                            |. Parser.spaces
                            |= CellRef.parser
                        , Parser.succeed (Single (Ref from))
                        ]
                )
        , Parser.map Single expression
        ]
