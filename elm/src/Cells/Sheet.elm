module Cells.Sheet exposing
    ( Sheet, new, set
    , raw, value, Value(..), CellError(..)
    )

{-| The spreadsheet model: cell contents, their evaluated values and the
dependencies between them.

@docs Sheet, new, set
@docs raw, value, Value, CellError

-}

import Cells.CellRef as CellRef exposing (CellRef, Key)
import Cells.Formula as Formula exposing (AggOp(..), Arg(..), BinOp(..), Expr(..))
import Dict exposing (Dict)
import Parser exposing ((|.))
import Set exposing (Set)


{-| What a non-blank cell, or a formula or a part of it, evaluates to. A blank
cell has no value; a formula reading it sees `0`, as in other spreadsheets.
-}
type Value
    = Number Float
    | Text String
      -- The cell could not be evaluated; shown as an error code.
    | Failed CellError


type CellError
    = ParseError
    | CircularRef
    | TypeError
    | DivByZero


{-| What the user entered into a non-blank cell, after parsing.
-}
type Content
    = -- A number, e.g. `42`.
      Constant Float
      -- Any other text, e.g. `hello`.
    | Label String
    | Formula Expr
    | Malformed


{-| A non-blank cell. Only `parseCell` builds one, so `content` is always the
parse of `raw` and `refs` the cells it reads.
-}
type alias Cell =
    { raw : String
    , content : Content
    , refs : Set Key
    }


{-| Invariants, maintained by `set`:

  - `values` has an entry for exactly the cells in `cells`, evaluated from
    their current content, so a blank cell has none;
  - `dependents` is the inverse of the cells' `refs` and holds no empty sets.

-}
type Sheet
    = Sheet
        { cells : Dict Key Cell
        , values : Dict Key Value
        , dependents : Dict Key (Set Key)
        }


new : Sheet
new =
    Sheet { cells = Dict.empty, values = Dict.empty, dependents = Dict.empty }


{-| The text the user entered into the cell; empty for a blank cell.
-}
raw : Sheet -> CellRef -> String
raw (Sheet sheet) ref =
    Dict.get (CellRef.key ref) sheet.cells
        |> Maybe.map .raw
        |> Maybe.withDefault ""


{-| The value of the cell; `Nothing` for a blank cell.
-}
value : Sheet -> CellRef -> Maybe Value
value (Sheet sheet) ref =
    Dict.get (CellRef.key ref) sheet.values


{-| Replaces the content of a cell and re-evaluates everything affected. A
blank `text` clears the cell.
-}
set : CellRef -> String -> Sheet -> Sheet
set ref text (Sheet sheet) =
    let
        at =
            CellRef.key ref

        oldRefs =
            dependencies sheet.cells at

        ( cells, newRefs ) =
            case parseCell text of
                Just cell ->
                    ( Dict.insert at cell sheet.cells, cell.refs )

                Nothing ->
                    ( Dict.remove at sheet.cells, Set.empty )
    in
    recalculate at
        { sheet
            | cells = cells
            , dependents = updateDependents at oldRefs newRefs sheet.dependents
        }


parseCell : String -> Maybe Cell
parseCell text =
    parseContent text
        |> Maybe.map
            (\content -> { raw = text, content = content, refs = contentRefs content })


parseContent : String -> Maybe Content
parseContent text =
    let
        trimmed =
            String.trim text
    in
    if String.isEmpty trimmed then
        Nothing

    else if String.startsWith "=" trimmed then
        case Formula.parse (String.dropLeft 1 trimmed) of
            Just expr ->
                Just (Formula expr)

            Nothing ->
                Just Malformed

    else
        case Parser.run (Formula.number |. Parser.end) trimmed of
            Ok n ->
                Just (Constant n)

            Err _ ->
                Just (Label trimmed)


contentRefs : Content -> Set Key
contentRefs content =
    case content of
        Formula expr ->
            Formula.refs expr
                |> List.map CellRef.key
                |> Set.fromList

        Constant _ ->
            Set.empty

        Label _ ->
            Set.empty

        Malformed ->
            Set.empty



-- DEPENDENCY GRAPH


{-| The cells `at` reads.
-}
dependencies : Dict Key Cell -> Key -> Set Key
dependencies cells at =
    Dict.get at cells
        |> Maybe.map .refs
        |> Maybe.withDefault Set.empty


{-| Moves `at` from the dependents of `oldRefs` to those of `newRefs`.
-}
updateDependents : Key -> Set Key -> Set Key -> Dict Key (Set Key) -> Dict Key (Set Key)
updateDependents at oldRefs newRefs dependents =
    let
        withoutOld =
            Set.foldl (\dep -> removeNeighbour dep at) dependents oldRefs
    in
    Set.foldl (\dep -> addNeighbour dep at) withoutOld newRefs


neighbours : Dict Key (Set Key) -> Key -> Set Key
neighbours graph at =
    Dict.get at graph |> Maybe.withDefault Set.empty


addNeighbour : Key -> Key -> Dict Key (Set Key) -> Dict Key (Set Key)
addNeighbour at neighbour graph =
    Dict.insert at (Set.insert neighbour (neighbours graph at)) graph


removeNeighbour : Key -> Key -> Dict Key (Set Key) -> Dict Key (Set Key)
removeNeighbour at neighbour graph =
    let
        remaining =
            Set.remove neighbour (neighbours graph at)
    in
    if Set.isEmpty remaining then
        Dict.remove at graph

    else
        Dict.insert at remaining graph


{-| Re-evaluates `changed` and every cell that (transitively) depends on it.
Cells on a reference cycle evaluate to `CircularRef`; cells depending on them
pick that error up through normal evaluation.
-}
recalculate :
    Key
    ->
        { cells : Dict Key Cell
        , values : Dict Key Value
        , dependents : Dict Key (Set Key)
        }
    -> Sheet
recalculate changed sheet =
    let
        affected =
            collectDependents sheet.dependents changed (Set.singleton changed)

        evaluateComponent component values =
            if isCycle sheet.cells component then
                List.foldl (\at -> Dict.insert at (Failed CircularRef)) values component

            else
                List.foldl
                    (\at acc ->
                        case Dict.get at sheet.cells of
                            Just cell ->
                                Dict.insert at (evaluate acc cell.content) acc

                            Nothing ->
                                Dict.remove at acc
                    )
                    values
                    component
    in
    Sheet
        { sheet
            | values =
                List.foldl evaluateComponent sheet.values (stronglyConnected sheet.cells affected)
        }


collectDependents : Dict Key (Set Key) -> Key -> Set Key -> Set Key
collectDependents dependents at visited =
    Set.foldl
        (\dep acc ->
            if Set.member dep acc then
                acc

            else
                collectDependents dependents dep (Set.insert dep acc)
        )
        visited
        (neighbours dependents at)


{-| Whether a strongly connected component is a cycle: it has several cells,
or one that reads itself.
-}
isCycle : Dict Key Cell -> List Key -> Bool
isCycle cells component =
    case component of
        [ at ] ->
            Set.member at (dependencies cells at)

        _ ->
            True


{-| The state of the search in `stronglyConnected`. `index` is the order in
which cells were reached, `lowLink` the lowest index reachable from a cell
through cells still on the stack.
-}
type alias Search =
    { nextIndex : Int
    , index : Dict Key Int
    , lowLink : Dict Key Int
    , stack : List Key
    , onStack : Set Key
    , components : List (List Key)
    }


{-| The strongly connected components of the cells in `keys`, following the
cells they read and ignoring cells outside `keys`. Each component comes after
the components it reads, so evaluating them in order sees every dependency up
to date.

The affected cells can be passed as `keys` without missing a cycle: every
cell on a cycle through an affected cell depends on it, so is affected too.

Tarjan's algorithm, which finds all components in one depth-first search.

-}
stronglyConnected : Dict Key Cell -> Set Key -> List (List Key)
stronglyConnected cells keys =
    let
        start =
            { nextIndex = 0
            , index = Dict.empty
            , lowLink = Dict.empty
            , stack = []
            , onStack = Set.empty
            , components = []
            }
    in
    Set.foldl
        (\at search ->
            if Dict.member at search.index then
                search

            else
                strongConnect cells keys at search
        )
        start
        keys
        |> .components
        |> List.reverse


strongConnect : Dict Key Cell -> Set Key -> Key -> Search -> Search
strongConnect cells keys at search =
    let
        index =
            search.nextIndex

        visited =
            Set.foldl
                (\dep acc ->
                    if not (Set.member dep keys) then
                        acc

                    else
                        case Dict.get dep acc.index of
                            Nothing ->
                                let
                                    searched =
                                        strongConnect cells keys dep acc
                                in
                                lowerLink at (lowLink searched dep) searched

                            Just depIndex ->
                                if Set.member dep acc.onStack then
                                    lowerLink at depIndex acc

                                else
                                    acc
                )
                { search
                    | nextIndex = index + 1
                    , index = Dict.insert at index search.index
                    , lowLink = Dict.insert at index search.lowLink
                    , stack = at :: search.stack
                    , onStack = Set.insert at search.onStack
                }
                (dependencies cells at)
    in
    if lowLink visited at == index then
        let
            ( component, stack ) =
                popComponent at visited.stack []
        in
        { visited
            | stack = stack
            , onStack = List.foldl Set.remove visited.onStack component
            , components = component :: visited.components
        }

    else
        visited


{-| Only read for cells the search has reached, which all have a low link.
-}
lowLink : Search -> Key -> Int
lowLink search at =
    Dict.get at search.lowLink |> Maybe.withDefault -1


lowerLink : Key -> Int -> Search -> Search
lowerLink at candidate search =
    { search | lowLink = Dict.insert at (min (lowLink search at) candidate) search.lowLink }


{-| Pops the stack down to and including `root`, which closes a component.
-}
popComponent : Key -> List Key -> List Key -> ( List Key, List Key )
popComponent root stack component =
    case stack of
        [] ->
            ( component, [] )

        at :: rest ->
            if at == root then
                ( at :: component, rest )

            else
                popComponent root rest (at :: component)



-- EVALUATION


evaluate : Dict Key Value -> Content -> Value
evaluate values content =
    case content of
        Constant n ->
            Number n

        Label s ->
            Text s

        Formula expr ->
            evaluateExpr values expr

        Malformed ->
            Failed ParseError


evaluateExpr : Dict Key Value -> Expr -> Value
evaluateExpr values expr =
    case expr of
        Literal n ->
            Number n

        Ref ref ->
            read values ref

        Binary op left right ->
            applyBinary op (evaluateExpr values left) (evaluateExpr values right)

        Aggregate op args ->
            args
                |> List.concatMap
                    (\arg ->
                        case arg of
                            Single single ->
                                [ evaluateExpr values single ]

                            Range from to ->
                                List.map (read values) (CellRef.range from to)
                    )
                |> applyAggregate op


{-| The value of a cell as a formula reads it: a blank cell counts as `0`.
-}
read : Dict Key Value -> CellRef -> Value
read values ref =
    Dict.get (CellRef.key ref) values |> Maybe.withDefault (Number 0)


applyBinary : BinOp -> Value -> Value -> Value
applyBinary op left right =
    Result.map2 Tuple.pair (coerceNumber left) (coerceNumber right)
        |> Result.andThen
            (\( a, b ) ->
                case op of
                    Add ->
                        Ok (a + b)

                    Sub ->
                        Ok (a - b)

                    Mul ->
                        Ok (a * b)

                    Div ->
                        if b == 0 then
                            Err DivByZero

                        else
                            Ok (a / b)

                    Mod ->
                        if b == 0 then
                            Err DivByZero

                        else
                            -- Takes the sign of the divisor, like `modBy`.
                            Ok (a - b * toFloat (floor (a / b)))
            )
        |> fromResult


applyAggregate : AggOp -> List Value -> Value
applyAggregate op operands =
    List.foldr (\operand acc -> Result.map2 (::) (coerceNumber operand) acc) (Ok []) operands
        |> Result.map
            (case op of
                Sum ->
                    List.sum

                Prod ->
                    List.product
            )
        |> fromResult


coerceNumber : Value -> Result CellError Float
coerceNumber operand =
    case operand of
        Number n ->
            Ok n

        Text _ ->
            Err TypeError

        Failed e ->
            Err e


fromResult : Result CellError Float -> Value
fromResult result =
    case result of
        Ok n ->
            Number n

        Err e ->
            Failed e
