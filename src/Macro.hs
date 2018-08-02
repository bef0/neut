module Macro
  ( macroExpand
  ) where

import           Control.Monad
import           Control.Monad.State

import           Control.Comonad.Cofree

import           Data
import           Data.Maybe             (fromMaybe)

import qualified Text.Show.Pretty       as Pr

type Subst = ([(String, Tree)], [(String, [Tree])])

type Pattern = Tree

sanityCheck :: (Pattern, Pattern) -> Either String ()
sanityCheck = undefined

-- "body+" のように、末尾が '+' で終わるようなシンボルを「1個以上の式の繰り返し」を
-- 表現するための記号として採用する。これはBNF記法からの類推である。
isRest :: String -> Bool
isRest s = last s == '+'

-- 予約語のリストと入力の木とパターンを受け取り、予約語の情報を使いながら木とパターンを
-- マッチさせていく。マッチに成功した時には、substitution, つまりシンボルと木への対応関係が返る。
macroMatch :: [String] -> Tree -> Tree -> Maybe Subst
macroMatch rs (i :< TreeAtom s1) (_ :< TreeAtom s2) =
  case (s1 `elem` rs, s2 `elem` rs) of
    (True, True)
      | s1 == s2 -> return ([], [])
    (False, False) -> return ([(s2, i :< TreeAtom s1)], [])
    _ -> Nothing
macroMatch rs t (_ :< TreeAtom s) =
  if s `elem` rs
    then Nothing
    else return ([(s, t)], [])
macroMatch rs (i :< TreeAtom s) (_ :< t) = Nothing
macroMatch rs (i :< TreeNode ts1) (_ :< TreeNode ts2) =
  case last ts2 of
    (_ :< TreeAtom sym)
      | isRest sym && length ts1 >= length ts2 -> do
        let (xs, rest) = splitAt (length ts2 - 1) ts1
        let ys = take (length ts2 - 1) ts2
        (ss, rests) <- unzip <$> zipWithM (macroMatch rs) xs ys
        return (join ss, (sym, rest) : join rests)
    _
      | length ts1 == length ts2 -> do
        (ss, rests) <- unzip <$> zipWithM (macroMatch rs) ts1 ts2
        return (join ss, join rests)
    _ -> Nothing

-- substitutionをtreeに対して作用させる。
applySubst :: Subst -> Tree -> Tree
applySubst (s1, _) (i :< TreeAtom s) = fromMaybe (i :< TreeAtom s) (lookup s s1)
applySubst sub@(_, s2) (i :< TreeNode ts) =
  case last ts of
    (j :< TreeAtom s)
      | isRest s && s `elem` map fst s2 -> do
        let tsButLast' = map (applySubst sub) (take (length ts - 1) ts)
        case lookup s s2 of
          Nothing   -> undefined
          Just rest -> j :< TreeNode (tsButLast' ++ rest)
    (j :< _) -> do
      let ts' = map (applySubst sub) ts
      j :< TreeNode ts

-- 関数fをリストの第1要素に対して作用させ、最初にJustが得られたときの要素と第2要素のペアを返す。
-- Justが得られなかったときにはNothingを返す。
try :: (a -> Maybe b) -> [(a, c)] -> Maybe (b, c)
try f [] = Nothing
try f ((p, q):as) =
  case f p of
    Nothing -> try f as
    Just x  -> Just (x, q)

macroExpand1 :: Tree -> WithEnv Tree
macroExpand1 t@(i :< _) = do
  env <- get
  let nenv = notationEnv env
  let renv = reservedEnv env
  case try (macroMatch renv t) nenv of
    Just (subst, _ :< template) -> do
      let t' = applySubst subst (i :< template)
      macroExpand t'
    Nothing -> return t

-- これをtermについてinductiveにやる必要がある。
-- macroの展開が起こったか否かをフラグで管理するべき？
macroExpand :: Tree -> WithEnv Tree
macroExpand = recurM macroExpand1
