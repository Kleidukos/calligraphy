import Test.Tasty

import qualified Test.LexTree as LexTree
import qualified Test.Mermaid as Mermaid

main :: IO ()
main = defaultMain tests
  where
    tests =
      testGroup
        "Calligraphy Tests"
        [ LexTree.spec
        , Mermaid.spec
        ]
