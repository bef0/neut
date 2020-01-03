module Clarify.Utility where

import Control.Monad.State

import Data.Basic
import Data.Code
import Data.Env

-- toAffineApp ML x e ~>
--   bind f := e in
--   let (aff, rel) := f in
--   aff @ x
toAffineApp :: Meta -> Identifier -> CodePlus -> WithEnv CodePlus
toAffineApp m x t = do
  (expVarName, expVar) <- newDataUpsilonWith "exp"
  (affVarName, affVar) <- newDataUpsilonWith "aff"
  (relVarName, _) <- newDataUpsilonWith "rel"
  retImmType <- returnCartesianImmediate
  return
    ( m
    , CodeUpElim
        expVarName
        t
        ( emptyMeta
        , CodeSigmaElim
            [(affVarName, retImmType), (relVarName, retImmType)]
            expVar
            (m, CodePiElimDownElim affVar [toDataUpsilon (x, m)])))

-- toRelevantApp ML x e ~>
--   bind f := e in
--   let (aff, rel) := f in
--   rel @ x
toRelevantApp :: Meta -> Identifier -> CodePlus -> WithEnv CodePlus
toRelevantApp m x t = do
  (expVarName, expVar) <- newDataUpsilonWith "rel-app-exp"
  (affVarName, _) <- newDataUpsilonWith "rel-app-aff"
  (relVarName, relVar) <- newDataUpsilonWith "rel-app-rel"
  retImmType <- returnCartesianImmediate
  return
    ( m
    , CodeUpElim
        expVarName
        t
        ( m
        , CodeSigmaElim
            [(affVarName, retImmType), (relVarName, retImmType)]
            expVar
            (m, CodePiElimDownElim relVar [toDataUpsilon (x, m)])))

bindLet :: [(Identifier, CodePlus)] -> CodePlus -> CodePlus
bindLet [] cont = cont
bindLet ((x, e):xes) cont = do
  let cont' = bindLet xes cont
  (fst cont', CodeUpElim x e cont')

returnUpsilon :: Identifier -> CodePlus
returnUpsilon x = (emptyMeta, CodeUpIntro (emptyMeta, DataUpsilon x))

returnCartesianImmediate :: WithEnv CodePlus
returnCartesianImmediate = do
  v <- cartesianImmediate emptyMeta
  return (emptyMeta, CodeUpIntro v)

returnCartesianUniv :: WithEnv CodePlus
returnCartesianUniv = do
  v <- cartesianUniv emptyMeta
  return (emptyMeta, CodeUpIntro v)

cartesianImmediate :: Meta -> WithEnv DataPlus
cartesianImmediate m = do
  aff <- affineImmediate m
  rel <- relevantImmediate m
  return (m, DataSigmaIntro [aff, rel])

affineImmediate :: Meta -> WithEnv DataPlus
affineImmediate m = do
  cenv <- gets codeEnv
  let thetaName = "affine-immediate"
  let theta = (m, DataTheta thetaName)
  case lookup thetaName cenv of
    Just _ -> return theta
    Nothing -> do
      immVarName <- newNameWith "arg"
      insCodeEnv
        thetaName
        [immVarName]
        (emptyMeta, CodeUpIntro (emptyMeta, DataSigmaIntro []))
      return theta

relevantImmediate :: Meta -> WithEnv DataPlus
relevantImmediate m = do
  cenv <- gets codeEnv
  let thetaName = "relevant-immediate"
  let theta = (m, DataTheta thetaName)
  case lookup thetaName cenv of
    Just _ -> return theta
    Nothing -> do
      (immVarName, immVar) <- newDataUpsilonWith "arg"
      insCodeEnv
        thetaName
        [immVarName]
        (emptyMeta, CodeUpIntro (emptyMeta, DataSigmaIntro [immVar, immVar]))
      return theta

cartesianUniv :: Meta -> WithEnv DataPlus
cartesianUniv m = do
  aff <- affineUniv m
  rel <- relevantUniv m
  return (m, DataSigmaIntro [aff, rel])

-- \x -> let (_, _) := x in unit
affineUniv :: Meta -> WithEnv DataPlus
affineUniv m = do
  cenv <- gets codeEnv
  let thetaName = "affine-univ"
  let theta = (m, DataTheta thetaName)
  case lookup thetaName cenv of
    Just _ -> return theta
    Nothing -> do
      (univVarName, univVar) <- newDataUpsilonWith "univ"
      affVarName <- newNameWith "aff-univ"
      relVarName <- newNameWith "rel-univ"
      retImmType <- returnCartesianImmediate
      insCodeEnv
        thetaName
        [univVarName]
        -- let (a, b) := x in return ()
        ( emptyMeta
        , CodeSigmaElim
            [(affVarName, retImmType), (relVarName, retImmType)]
            univVar
            (emptyMeta, CodeUpIntro (emptyMeta, DataSigmaIntro [])))
      return theta

relevantUniv :: Meta -> WithEnv DataPlus
relevantUniv m = do
  cenv <- gets codeEnv
  let thetaName = "relevant-univ"
  let theta = (m, DataTheta thetaName)
  case lookup thetaName cenv of
    Just _ -> return theta
    Nothing -> do
      (univVarName, univVar) <- newDataUpsilonWith "univ"
      (affVarName, affVar) <- newDataUpsilonWith "aff-univ"
      (relVarName, relVar) <- newDataUpsilonWith "rel-univ"
      retImmType <- returnCartesianImmediate
      insCodeEnv
        thetaName
        [univVarName]
        -- let (a, b) := x in return ((a, b), (a, b))
        ( emptyMeta
        , CodeSigmaElim
            [(affVarName, retImmType), (relVarName, retImmType)]
            univVar
            ( emptyMeta
            , CodeUpIntro
                ( emptyMeta
                , DataSigmaIntro
                    [ (emptyMeta, DataSigmaIntro [affVar, relVar])
                    , (emptyMeta, DataSigmaIntro [affVar, relVar])
                    ])))
      return theta

renameData :: DataPlus -> WithEnv DataPlus
renameData (m, DataTheta x) = return (m, DataTheta x)
renameData (m, DataUpsilon x) = do
  x' <- lookupNameEnv x
  return (m, DataUpsilon x')
renameData (m, DataSigmaIntro ds) = do
  ds' <- mapM renameData ds
  return (m, DataSigmaIntro ds')
renameData (m, DataIntS size x) = return (m, DataIntS size x)
renameData (m, DataIntU size x) = return (m, DataIntU size x)
renameData (m, DataFloat16 x) = return (m, DataFloat16 x)
renameData (m, DataFloat32 x) = return (m, DataFloat32 x)
renameData (m, DataFloat64 x) = return (m, DataFloat64 x)
renameData (m, DataEnumIntro x) = return (m, DataEnumIntro x)
renameData (m, DataArrayIntro kind les) = do
  les' <-
    forM les $ \(l, body) -> do
      body' <- renameData body
      return (l, body')
  return (m, DataArrayIntro kind les')

renameCode :: CodePlus -> WithEnv CodePlus
renameCode (m, CodeTheta x) = return (m, CodeTheta x)
renameCode (m, CodePiElimDownElim v vs) = do
  v' <- renameData v
  vs' <- mapM renameData vs
  return (m, CodePiElimDownElim v' vs')
renameCode (m, CodeSigmaElim xts d e) = do
  d' <- renameData d
  (xts', e') <- renameBinderWithBody xts e
  return (m, CodeSigmaElim xts' d' e')
renameCode (m, CodeUpIntro d) = do
  d' <- renameData d
  return (m, CodeUpIntro d')
renameCode (m, CodeUpElim x e1 e2) = do
  e1' <- renameCode e1
  local $ do
    x' <- newNameWith x
    e2' <- renameCode e2
    return (m, CodeUpElim x' e1' e2')
renameCode (m, CodeEnumElim d les) = do
  d' <- renameData d
  les' <- renameCaseList les
  return (m, CodeEnumElim d' les')
renameCode (m, CodeArrayElim k d1 d2) = do
  d1' <- renameData d1
  d2' <- renameData d2
  return (m, CodeArrayElim k d1' d2')

renameBinderWithBody ::
     [(Identifier, CodePlus)]
  -> CodePlus
  -> WithEnv ([(Identifier, CodePlus)], CodePlus)
renameBinderWithBody [] e = do
  e' <- renameCode e
  return ([], e')
renameBinderWithBody ((x, t):xts) e = do
  t' <- renameCode t
  local $ do
    x' <- newNameWith x
    (xts', e') <- renameBinderWithBody xts e
    return ((x', t') : xts', e')

renameCaseList :: [(Case, CodePlus)] -> WithEnv [(Case, CodePlus)]
renameCaseList les =
  forM les $ \(l, body) ->
    local $ do
      body' <- renameCode body
      return (l, body')

local :: WithEnv a -> WithEnv a
local comp = do
  env <- get
  x <- comp
  modify (\e -> env {count = count e})
  return x

insCodeEnv :: Identifier -> [Identifier] -> CodePlus -> WithEnv ()
insCodeEnv name args e = do
  args' <- mapM newNameWith args
  e' <- renameCode e
  -- Since LLVM doesn't allow variable shadowing, we must explicitly
  -- rename variables here.
  modify (\env -> env {codeEnv = (name, (args', e')) : codeEnv env})
