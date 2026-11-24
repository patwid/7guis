module Cells.CellRef exposing
    ( CellRef, new, parser, fromString
    , Key, key
    , Row, rows, columnNames, numCols, numRows
    , next, previous, range
    )

{-| A coordinate inside the sheet.

@docs CellRef, new, parser, fromString
@docs Key, key
@docs Row, rows, columnNames, numCols, numRows
@docs next, previous, range

-}

import Parser exposing ((|.), (|=), Parser)


numCols : Int
numCols =
    26


numRows : Int
numRows =
    100


{-| Opaque, so every `CellRef` is guaranteed to lie within the sheet: the only
ways to get one are `new`, `parser`, and functions that stay in range.
-}
type CellRef
    = CellRef Int Int


new : Int -> Int -> Maybe CellRef
new col row =
    if col >= 0 && col < numCols && row >= 0 && row < numRows then
        Just (CellRef col row)

    else
        Nothing


{-| Identifies a cell as a `comparable`, so cells can be kept in a `Dict` or a
`Set`. Only `key` makes one.
-}
type alias Key =
    ( Int, Int )


key : CellRef -> Key
key (CellRef col row) =
    ( col, row )


{-| A row of the sheet: its name, as shown in the row header, and its cells,
left to right.
-}
type alias Row =
    { name : String
    , cells : List CellRef
    }


{-| Every row of the sheet, top to bottom.
-}
rows : List Row
rows =
    List.range 0 (numRows - 1)
        |> List.map
            (\row ->
                { name = String.fromInt row
                , cells = List.map (\col -> CellRef col row) columns
                }
            )


{-| The name of every column, left to right, as shown in the column header.
-}
columnNames : List String
columnNames =
    List.map columnLetter columns


columns : List Int
columns =
    List.range 0 (numCols - 1)


{-| The next cell in row-major order, wrapping around at the end.
-}
next : CellRef -> CellRef
next ref =
    step 1 ref


{-| The previous cell in row-major order, wrapping around at the start.
-}
previous : CellRef -> CellRef
previous ref =
    step (-1) ref


step : Int -> CellRef -> CellRef
step delta (CellRef col row) =
    let
        moved =
            modBy (numCols * numRows) (row * numCols + col + delta)
    in
    CellRef (modBy numCols moved) (moved // numCols)


{-| All cells in the rectangle spanned by the two corners (inclusive).
-}
range : CellRef -> CellRef -> List CellRef
range (CellRef fromCol fromRow) (CellRef toCol toRow) =
    List.range (min fromCol toCol) (max fromCol toCol)
        |> List.concatMap
            (\col ->
                List.range (min fromRow toRow) (max fromRow toRow)
                    |> List.map (CellRef col)
            )


{-| The column name, `A` to `Z`.
-}
columnLetter : Int -> String
columnLetter col =
    String.fromChar (Char.fromCode (Char.toCode 'A' + col))


{-| Parses a reference such as `B12`.
-}
parser : Parser CellRef
parser =
    Parser.succeed Tuple.pair
        |= Parser.getChompedString (Parser.chompIf Char.isUpper)
        |= Parser.getChompedString
            (Parser.chompIf Char.isDigit |. Parser.chompWhile Char.isDigit)
        |> Parser.andThen
            (\( letter, digits ) ->
                case Maybe.andThen (fromParts letter) (String.toInt digits) of
                    Just ref ->
                        Parser.succeed ref

                    Nothing ->
                        Parser.problem ("No such cell: " ++ letter ++ digits)
            )


fromParts : String -> Int -> Maybe CellRef
fromParts letter row =
    case String.toList letter of
        [ char ] ->
            new (Char.toCode char - Char.toCode 'A') row

        _ ->
            Nothing


{-| Parses a whole string as a reference such as `B12`.
-}
fromString : String -> Maybe CellRef
fromString text =
    Parser.run (parser |. Parser.end) text
        |> Result.toMaybe
