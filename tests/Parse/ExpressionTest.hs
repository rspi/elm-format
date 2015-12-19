module Parse.ExpressionTest where

import Elm.Utils ((|>))

import Test.HUnit (Assertion, assertEqual)
import Test.Framework
import Test.Framework.Providers.HUnit
import qualified Data.Text.Lazy as LazyText

import Parse.Expression
import Parse.Helpers (IParser, iParse)
import AST.V0_15
import AST.Expression
import AST.Literal
import qualified AST.Pattern as P
import AST.Variable
import Reporting.Annotation hiding (map, at)
import Reporting.Region
import Text.Parsec.Char (string)

import Parse.TestHelpers


pending = at 0 0 0 0 $ Unit []


example name input expected =
    testCase name $
        assertParse expr input expected


commentedIntExpr (a,b,c,d) preComment postComment i =
    Commented [BlockComment [preComment]] [BlockComment [postComment]] $ at a b c d  $ Literal $ IntNum i

commentedIntExpr' (a,b,c,d) preComment i =
    Commented [BlockComment [preComment]] [] $ at a b c d  $ Literal $ IntNum i


commentedIntExpr'' (a,b,c,d) preComment i =
    (,) [BlockComment [preComment]] $ at a b c d  $ Literal $ IntNum i


intExpr (a,b,c,d) i = at a b c d $ Literal $ IntNum i

intExpr' (a,b,c,d) i =
    Commented [] [] $ at a b c d  $ Literal $ IntNum i

intExpr'' (a,b,c,d) i =
    (,) [] $ at a b c d  $ Literal $ IntNum i


tests :: Test
tests =
    testGroup "Parse.Expression"
    [ testGroup "Unit"
        [ example "" "()" $ at 1 1 1 3 $ Unit []
        , example "whitespace" "( )" $ at 1 1 1 4 $ Unit []
        , example "comments" "({-A-})" $ at 1 1 1 8 $ Unit [BlockComment ["A"]]
        , example "newlines" "(\n )" $ at 1 1 2 3 $ Unit []
        , mustBeIndented expr "(\n )"
        ]

    , testGroup "Literal"
        [ example "" "1" $ at 1 1 1 2 (Literal (IntNum 1))

        , testGroup "Boolean"
            [ example "True" "True" $ at 1 1 1 5 $ Literal $ Boolean True
            , example "False" "False" $ at 1 1 1 6 $ Literal $ Boolean False
            ]
        ]

    , testGroup "variable"
        [ example "lowercase" "foo" $ at 1 1 1 4 $ Var $ VarRef "foo"
        , example "uppercase" "Bar" $ at 1 1 1 4 $ Var $ VarRef "Bar"
        , example "qualified" "Bar.Baz.foo" $ at 1 1 1 12 $ Var $ VarRef "Bar.Baz.foo"

        , testGroup "symbolic operator"
            [ example "" "(+)" $ at 1 1 1 4 $ Var $ OpRef "+"
            , example "whitespace" "( + )" $ at 1 1 1 6 $ Var $ OpRef "+"
            -- TODO: parse comments
            , example "comments" "({-A-}+{-B-})" $ at 1 1 1 14 (Var (OpRef "+"))
            , testCase "does not allow newlines" $
                assertFailure expr "(\n + \n)"
            ]
        ]

    , testGroup "function application"
        [ example "" "f 7 8" $ at 1 1 1 6 $ App (at 1 1 1 2 $ Var $ VarRef "f") [intExpr'' (1,3,1,4) 7, intExpr'' (1,5,1,6) 8] False
        , example "argument starts with minus" "f -9 -x" $ at 1 1 1 8 $ App (at 1 1 1 2 $ Var $ VarRef "f") [intExpr'' (1,3,1,5) (-9), (,) [] $ at 1 6 1 8 $ Unary Negative $ at 1 7 1 8 $ Var $ VarRef "x"] False
        , example "comments" "f{-A-}7{-B-}8" $ at 1 1 1 14 $ App (at 1 1 1 2 $ Var $ VarRef "f") [commentedIntExpr'' (1,7,1,8) "A" 7, commentedIntExpr'' (1,13,1,14) "B" 8] False
        , example "newlines" "f\n 7\n 8" $ at 1 1 3 3 $ App (at 1 1 1 2 $ Var $ VarRef "f") [intExpr'' (2,2,2,3) 7, intExpr'' (3,2,3,3) 8] True
        , example "newlines and comments" "f\n {-A-}7\n {-B-}8" $ at 1 1 3 8 $ App (at 1 1 1 2 $ Var $ VarRef "f") [commentedIntExpr'' (2,7,2,8) "A" 7, commentedIntExpr'' (3,7,3,8) "B" 8] True
        , mustBeIndented expr "f\n 7\n 8"
        ]

    , testGroup "unary operators"
        [ testGroup "negative"
            [ example "" "-True" $ at 1 1 1 6 $ Unary Negative $ at 1 2 1 6 $ Literal $ Boolean True
            , testCase "must not have whitespace" $
                assertFailure expr "- True"
            , testCase "must not have comment" $
                assertFailure expr "-{- -}True"
            , testCase "does not apply to '-'" $
                assertFailure expr "--True"
            , testCase "does not apply to '.'" $
                assertFailure expr "-.foo"
            ]
        ]

    , testGroup "binary operators"
        [ example "" "7+8<<>>9" $ at 1 1 1 9 $ Binops (intExpr (1,1,1,2) 7) [([], OpRef "+", [], intExpr (1,3,1,4) 8), ([], OpRef "<<>>", [], intExpr (1,8,1,9) 9)] False
        , example "minus with no whitespace" "9-1" $ at 1 1 1 4 $ Binops (intExpr (1,1,1,2) 9) [([], OpRef "-", [], intExpr (1,3,1,4) 1)] False
        , example "backticks" "7`plus`8`shift`9" $ at 1 1 1 17 $ Binops (intExpr (1,1,1,2) 7) [([], VarRef "plus", [], intExpr (1,8,1,9) 8), ([], VarRef "shift", [], intExpr (1,16,1,17) 9)] False
        , example "whitespace" "7 + 8 <<>> 9" $ at 1 1 1 13 $ Binops (intExpr (1,1,1,2) 7) [([], OpRef "+", [], intExpr (1,5,1,6) 8), ([], OpRef "<<>>", [], intExpr (1,12,1,13) 9)] False
        , example "comments" "7{-A-}+{-B-}8{-C-}<<>>{-D-}9" $ at 1 1 1 29 $ Binops (intExpr (1,1,1,2) 7) [([BlockComment ["A"]], OpRef "+", [BlockComment ["B"]], intExpr (1,13,1,14) 8), ([BlockComment ["C"]], OpRef "<<>>", [BlockComment ["D"]], intExpr (1,28,1,29) 9)] False
        , example "newlines" "7\n +\n 8\n <<>>\n 9" $ at 1 1 5 3 $ Binops (intExpr (1,1,1,2) 7) [([], OpRef "+", [], intExpr (3,2,3,3) 8), ([], OpRef "<<>>", [], intExpr (5,2,5,3) 9)] True
        , mustBeIndented expr "7\n +\n 8\n <<>>\n 9"
        ]

    , testGroup "parentheses"
        [ example "" "(1)" $ at 1 1 1 4 $ Parens $ intExpr' (1,2,1,3) 1
        , example "whitespace" "( 1 )" $ at 1 1 1 6 $ Parens $ intExpr' (1,3,1,4) 1
        , example "comments" "({-A-}1{-B-})" $ at 1 1 1 14 $ Parens $ commentedIntExpr (1,7,1,8) "A" "B" 1
        , example "newlines" "(\n 1\n )" $ at 1 1 3 3 $ Parens $ intExpr' (2,2,2,3) 1
        , mustBeIndented expr "(\n 1\n )"
        ]

    , testGroup "List"
        [ example "" "[1,2,3]" $ at 1 1 1 8 $ ExplicitList [intExpr' (1,2,1,3) 1, intExpr' (1,4,1,5) 2, intExpr' (1,6,1,7) 3] False
        , example "single element" "[1]" $ at 1 1 1 4 $ ExplicitList [intExpr' (1,2,1,3) 1] False
        , example "empty" "[]" $ at 1 1 1 3 $ ExplicitList [] False
        , example "whitespace" "[ 1 , 2 , 3 ]" $ at 1 1 1 14 $ ExplicitList [intExpr' (1,3,1,4) 1, intExpr' (1,7,1,8) 2, intExpr' (1,11,1,12) 3] False
        , example "comments" "[{-A-}1{-B-},{-C-}2{-D-},{-E-}3{-F-}]" $ at 1 1 1 38 $ ExplicitList [commentedIntExpr (1,7,1,8) "A" "B" 1, commentedIntExpr (1,19,1,20) "C" "D" 2, commentedIntExpr (1,31,1,32) "E" "F" 3] False
        , example "newlines" "[\n 1\n ,\n 2\n ,\n 3\n ]" $ at 1 1 7 3 $ ExplicitList [intExpr' (2,2,2,3) 1, intExpr' (4,2,4,3) 2, intExpr' (6,2,6,3) 3] True
        , mustBeIndented expr "[\n 1\n ,\n 2\n ,\n 3\n ]"
        ]

    , testGroup "Range"
        [ example "" "[7..9]" $ at 1 1 1 7 $ Range (intExpr' (1,2,1,3) 7) (intExpr' (1,5,1,6) 9) False
        , example "whitespace" "[ 7 .. 9 ]" $ at 1 1 1 11 $ Range (intExpr' (1,3,1,4) 7) (intExpr' (1,8,1,9) 9) False
        , example "comments" "[{-A-}7{-B-}..{-C-}9{-D-}]" $ at 1 1 1 27 $ Range (commentedIntExpr (1,7,1,8) "A" "B" 7) (commentedIntExpr (1,20,1,21) "C" "D" 9) False
        , example "newlines" "[\n 7\n ..\n 9\n ]" $ at 1 1 5 3 $ Range (intExpr' (2,2,2,3) 7) (intExpr' (4,2,4,3) 9) True
        , mustBeIndented expr "[\n 7\n ..\n 9\n ]"
        ]

    , testGroup "Tuple"
        [ example "" "(1,2)" $ at 1 1 1 6 $ Tuple [intExpr' (1,2,1,3) 1, intExpr' (1,4,1,5) 2] False
        , example "whitespace" "( 1 , 2 )" $ at 1 1 1 10 $ Tuple [intExpr' (1,3,1,4) 1, intExpr' (1,7,1,8) 2] False
        , example "comments" "({-A-}1{-B-},{-C-}2{-D-})" $ at 1 1 1 26 $ Tuple [commentedIntExpr (1,7,1,8) "A" "B" 1, commentedIntExpr (1,19,1,20) "C" "D" 2] False
        , example "newlines" "(\n 1\n ,\n 2\n )" $ at 1 1 5 3 $ Tuple [intExpr' (2,2,2,3) 1, intExpr' (4,2,4,3) 2] True
        , mustBeIndented expr "(\n 1\n ,\n 2\n )"
        ]

    , testGroup "tuple constructor"
        [ example "" "(,,)" $ at 1 1 1 5 $ TupleFunction 3
        , example "whitespace" "( , ,)" $ at 1 1 1 7 $ TupleFunction 3
        -- TODO: parse comments
        , example "comments" "({-A-},{-B-},)" $ at 1 1 1 15 (TupleFunction 3)
        , example "newlines" "(\n ,\n ,)" $ at 1 1 3 4 $ TupleFunction 3
        , mustBeIndented expr "(\n ,\n ,)"
        , testCase "does not allow trailing inner whitespace" $
            assertFailure expr "(,, )"
        ]

    , testGroup "Record"
        [ testGroup "empty"
            [ example "" "{}" $ at 1 1 1 3 $ EmptyRecord []
            , example "whitespace" "{ }" $ at 1 1 1 4 $ EmptyRecord []
            , example "comments" "{{-A-}}" $ at 1 1 1 8 $ EmptyRecord [BlockComment ["A"]]
            ]

        , example "" "{x=7,y=8}" $ at 1 1 1 10 $ Record [([], "x", [], intExpr' (1,4,1,5) 7, False), ([], "y", [], intExpr' (1,8,1,9) 8, False)] False
        , example "single field" "{x=7}" $ at 1 1 1 6 $ Record [([], "x", [], intExpr' (1,4,1,5) 7, False)] False
        , example "whitespace" "{ x = 7 , y = 8 }" $ at 1 1 1 18 $ Record [([], "x", [], intExpr' (1,7,1,8) 7, False), ([], "y", [], intExpr' (1,15,1,16) 8, False)] False
        , example "comments" "{{-A-}x{-B-}={-C-}7{-D-},{-E-}y{-F-}={-G-}8{-H-}}" $ at 1 1 1 50 $ Record [([BlockComment ["A"]], "x", [BlockComment ["B"]], commentedIntExpr (1,19,1,20) "C" "D" 7, False), ([BlockComment ["E"]], "y", [BlockComment ["F"]], commentedIntExpr (1,43,1,44) "G" "H" 8, False)] False
        , example "single field with comments" "{{-A-}x{-B-}={-C-}7{-D-}}" $ at 1 1 1 26 $ Record [([BlockComment ["A"]], "x", [BlockComment ["B"]], commentedIntExpr (1,19,1,20) "C" "D" 7, False)] False
        , example "newlines" "{\n x\n =\n 7\n ,\n y\n =\n 8\n }" $ at 1 1 9 3 $ Record [([], "x", [], intExpr' (4,2,4,3) 7, True), ([], "y", [], intExpr' (8,2,8,3) 8, True)] True
        , mustBeIndented expr "{\n x\n =\n 7\n ,\n y\n =\n 8\n }"
        ]

    , testGroup "Record update"
        [ example "" "{a|x=7,y=8}" $ at 1 1 1 12 $ RecordUpdate (Commented [] [] $ at 1 2 1 3 $ Var $ VarRef "a") [([], "x", [], intExpr' (1,6,1,7) 7, False), ([], "y", [], intExpr' (1,10,1,11) 8, False)] False
        , example "single field" "{a|x=7}" $ at 1 1 1 8 $ RecordUpdate (Commented [] [] $ at 1 2 1 3 $ Var $ VarRef "a") [([], "x", [], intExpr' (1,6,1,7) 7, False)] False
        , example "whitespace" "{ a | x = 7 , y = 8 }" $ at 1 1 1 22 $ RecordUpdate (Commented [] [] $ at 1 3 1 4 $ Var $ VarRef "a") [([], "x", [], intExpr' (1,11,1,12) 7, False), ([], "y", [], intExpr' (1,19,1,20) 8, False)] False
        , example "comments" "{{-A-}a{-B-}|{-C-}x{-D-}={-E-}7{-F-},{-G-}y{-H-}={-I-}8{-J-}}" $ at 1 1 1 62 $ RecordUpdate (Commented [BlockComment ["A"]] [BlockComment ["B"]] $ at 1 7 1 8 $ Var $ VarRef "a") [([BlockComment ["C"]], "x", [BlockComment ["D"]], commentedIntExpr (1,31,1,32) "E" "F" 7, False), ([BlockComment ["G"]], "y", [BlockComment ["H"]], commentedIntExpr (1,55,1,56) "I" "J" 8, False)] False
        , example "newlines" "{\n a\n |\n x\n =\n 7\n ,\n y\n =\n 8\n }" $ at 1 1 11 3 $ RecordUpdate (Commented [] [] $ at 2 2 2 3 $ Var $ VarRef "a") [([], "x", [], intExpr' (6,2,6,3) 7, True), ([], "y", [], intExpr' (10,2,10,3) 8, True)] True
        , mustBeIndented expr "{\n a\n |\n x\n =\n 7\n ,\n y\n =\n 8\n }"
        , testCase "only allows simple base" $
            assertFailure expr "{9|x=7}"
        , testCase "only allows simple base" $
            assertFailure expr "{{}|x=7}"
        , testCase "must have fields" $
            assertFailure expr "{a|}"
        ]

    , testGroup "record access"
        [ example "" "x.f1" $ at 1 1 1 5 (Access (at 1 1 1 2 (Var (VarRef "x"))) "f1")
        , example "nested" "x.f1.f2" $ at 1 1 1 8 (Access (at 1 1 1 5 (Access (at 1 1 1 2 (Var (VarRef "x"))) "f1")) "f2")
        , testCase "does not allow symbolic field names" $
            assertFailure expr "x.+"
        , testCase "does not allow symbolic field names" $
            assertFailure expr "x.(+)"
        ]

    , testGroup "record access fuction"
        [ example "" ".f1" $ at 1 1 1 4 $ AccessFunction "f1"
        ]

    , testCase "labmda" $
        assertParse expr "\\x y->9" $ at 1 1 1 8 $ Lambda [([], at 1 2 1 3 $ P.Var $ VarRef "x"), ([], at 1 4 1 5 $ P.Var $ VarRef "y")] [] (intExpr (1,7,1,8) 9) False
    , testCase "labmda (single parameter)" $
        assertParse expr "\\x->9" $ at 1 1 1 6 $ Lambda [([], at 1 2 1 3 $ P.Var $ VarRef "x")] [] (intExpr (1,5,1,6) 9) False
    , testCase "labmda (whitespace)" $
        assertParse expr "\\ x y -> 9" $ at 1 1 1 11 $ Lambda [([], at 1 3 1 4 $ P.Var $ VarRef "x"), ([], at 1 5 1 6 $ P.Var $ VarRef "y")] [] (intExpr (1,10,1,11) 9) False
    , testCase "labmda (comments)" $
        assertParse expr "\\{-A-}x{-B-}y{-C-}->{-D-}9" $ at 1 1 1 27 $ Lambda [([BlockComment ["A"]], at 1 7 1 8 $ P.Var $ VarRef "x"), ([BlockComment ["B"]], at 1 13 1 14 $ P.Var $ VarRef "y")] [BlockComment ["C"], BlockComment ["D"]] (intExpr (1,26,1,27) 9) False
    , testCase "labmda (newlines)" $
        assertParse expr "\\\n x\n y\n ->\n 9" $ at 1 1 5 3 $ Lambda [([], at 2 2 2 3 $ P.Var $ VarRef "x"), ([], at 3 2 3 3 $ P.Var $ VarRef "y")] [] (intExpr (5,2,5,3) 9) True
    , testGroup "lambda (must be indented)"
        [ testCase "(1)" $ assertFailure expr "\\\nx\n y\n ->\n 9"
        , testCase "(2)" $ assertFailure expr "\\\n x\ny\n ->\n 9"
        , testCase "(3)" $ assertFailure expr "\\\n x\n y\n->\n 9"
        , testCase "(4)" $ assertFailure expr "\\\n x\n y\n ->\n9"
        ]
    , testCase "lambda (arrow must not contain whitespace)" $
        assertFailure expr "\\x y - > 9"

    , testCase "case" $
        assertParse expr "case 9 of\n 1->10\n _->20" $ at 1 1 3 7 $ Case (intExpr (1,6,1,7) 9, False) [([], at 2 2 2 3 $ P.Literal $ IntNum 1, [], intExpr (2,5,2,7) 10), ([], at 3 2 3 3 $ P.Anything, [], intExpr (3,5,3,7) 20)]
    , testCase "case (no newline after 'of')" $
        assertParse expr "case 9 of 1->10\n          _->20" $ at 1 1 2 16 $ Case (intExpr (1,6,1,7) 9, False) [([], at 1 11 1 12 $ P.Literal $ IntNum 1, [], intExpr (1,14,1,16) 10), ([], at 2 11 2 12 $ P.Anything, [], intExpr (2,14,2,16) 20)]
    , testCase "case (whitespace)" $
        assertParse expr "case 9 of\n 1 -> 10\n _ -> 20" $ at 1 1 3 9 $ Case (intExpr (1,6,1,7) 9, False) [([], at 2 2 2 3 $ P.Literal $ IntNum 1, [], intExpr (2,7,2,9) 10), ([], at 3 2 3 3 $ P.Anything, [], intExpr (3,7,3,9) 20)]
    , testCase "case (comments)" $
        assertParse expr "case{-A-}9{-B-}of{-C-}\n{-D-}1{-E-}->{-F-}10{-G-}\n{-H-}_{-I-}->{-J-}20" $ at 1 1 3 21 $ Case (intExpr (1,10,1,11) 9, False) [([BlockComment ["C"], BlockComment ["D"]], at 2 6 2 7 $ P.Literal $ IntNum 1, [BlockComment ["F"]], intExpr (2,19,2,21) 10), ([BlockComment ["G"], BlockComment ["H"]], at 3 6 3 7 $ P.Anything, [BlockComment ["J"]], intExpr (3,19,3,21) 20)] -- TODO: handle comments A, B, E, I, and don't allow K
    , testCase "case (newlines)" $
        assertParse expr "case\n 9\n of\n 1\n ->\n 10\n _\n ->\n 20" $ at 1 1 9 4 $ Case (intExpr (2,2,2,3) 9, True) [([], at 4 2 4 3 $ P.Literal $ IntNum 1, [], intExpr (6,2,6,4) 10), ([], at 7 2 7 3 $ P.Anything, [], intExpr (9,2,9,4) 20)]
    , testCase "case (should not fail with trailing whitespace)" $
        assertParse (expr >> string "\nX") "case 9 of\n 1->10\n _->20\nX" $ "\nX"
    , testGroup "case (clauses must start at the same column)"
        [ testCase "(1)" $ assertFailure expr "case 9 of\n 1->10\n_->20"
        , testCase "(2)" $ assertFailure expr "case 9 of\n 1->10\n  _->20"
        , testCase "(3)" $ assertFailure expr "case 9 of\n  1->10\n _->20"
        ]
    , testGroup "case (must be indented)"
        [ testCase "(1)" $ assertFailure expr "case\n9\n of\n 1\n ->\n 10\n _\n ->\n 20"
        , testCase "(2)" $ assertFailure expr "case\n 9\nof\n 1\n ->\n 10\n _\n ->\n 20"
        , testCase "(3)" $ assertFailure expr "case\n 9\n of\n1\n ->\n 10\n _\n ->\n 20"
        , testCase "(4)" $ assertFailure expr "case\n 9\n of\n 1\n->\n 10\n _\n ->\n 20"
        , testCase "(5)" $ assertFailure expr "case\n 9\n of\n 1\n ->\n10\n _\n ->\n 20"
        , testCase "(6)" $ assertFailure expr "case\n 9\n of\n 1\n ->\n 10\n_\n ->\n 20"
        , testCase "(7)" $ assertFailure expr "case\n 9\n of\n 1\n ->\n 10\n _\n->\n 20"
        , testCase "(8)" $ assertFailure expr "case\n 9\n of\n 1\n ->\n 10\n _\n ->\n20"
        ]

    , testGroup "definition"
        [ testCase "" $ assertParse definition "x=1" $ at 1 1 1 4 $ Definition (at 1 1 1 2 $ P.Var $ VarRef "x") [] [] (intExpr (1,3,1,4) 1) False
        , testCase "comments" $ assertParse definition "x{-A-}={-B-}1" $ at 1 1 1 14 $ Definition (at 1 1 1 2 $ P.Var $ VarRef "x") [] [BlockComment ["A"], BlockComment ["B"]] (intExpr (1,13,1,14) 1) False
        , testCase "line comments" $ assertParse definition "x\n--Y\n =\n    --X\n    1" $ at 1 1 5 6 $ Definition (at 1 1 1 2 $ P.Var $ VarRef "x") [] [LineComment "Y", LineComment "X"] (intExpr (5,5,5,6) 1) True

        ]
    ]
