module Data.LLVM where

import Numeric.Half

import qualified Data.Text as T

import Data.Basic

data LLVMData
  = LLVMDataLocal Identifier
  | LLVMDataGlobal T.Text
  | LLVMDataInt Integer
  | LLVMDataFloat16 Half
  | LLVMDataFloat32 Float
  | LLVMDataFloat64 Double
  | LLVMDataNull
  deriving (Show)

data LLVM
  = LLVMReturn LLVMData -- UpIntro
  | LLVMLet Identifier LLVMOp LLVM -- UpElim
  | LLVMCont LLVMOp LLVM -- LLVMLet that discards the result of LLVMOp
  | LLVMSwitch (LLVMData, LowType) LLVM [(Int, LLVM)] -- EnumElim
  | LLVMBranch LLVMData LLVM LLVM
  | LLVMCall LLVMData [LLVMData]
  | LLVMUnreachable -- for empty case analysis
  deriving (Show)

data LLVMOp
  = LLVMOpCall LLVMData [LLVMData]
  | LLVMOpGetElementPtr
      (LLVMData, LowType) -- (base pointer, the type of base pointer)
      [(LLVMData, LowType)] -- [(index, the-typee-of-index)]
  | LLVMOpBitcast
      LLVMData
      LowType -- cast from
      LowType -- cast to
  | LLVMOpIntToPointer LLVMData LowType LowType
  | LLVMOpPointerToInt LLVMData LowType LowType
  | LLVMOpLoad LLVMData LowType
  | LLVMOpStore LowType LLVMData LLVMData
  | LLVMOpAlloc LLVMData SizeInfo
  | LLVMOpFree LLVMData SizeInfo Int -- (var, size-of-var, name-of-free)   (name-of-free is only for optimization)
  | LLVMOpUnaryOp UnaryOp LLVMData
  | LLVMOpBinaryOp BinaryOp LLVMData LLVMData
  | LLVMOpSysCall
      Integer -- syscall number
      [LLVMData] -- arguments
  deriving (Show)

-- (elem-type, num of elems)
-- to be used to eliminate free-then-malloc-with-the-same-size.
type SizeInfo = (LowType, Int)

type SubstLLVM = [(Int, LLVMData)]

-- reduceLLVM :: LLVM -> LLVM
-- reduceLLVM (LLVMReturn d) = LLVMReturn d
-- reduceLLVM (LLVMLet x (LLVMOpBitcast d from to) cont)
--   | from == to = reduceLLVM $ substLLVM [(asInt x, d)] cont
-- reduceLLVM (LLVMLet x op cont) = do
--   let cont' = reduceLLVM cont
--   LLVMLet x op cont'
-- reduceLLVM (LLVMCont op cont) = do
--   let cont' = reduceLLVM cont
--   LLVMCont op cont'
-- reduceLLVM (LLVMSwitch (d, t) defaultBranch les) = do
--   let (ls, es) = unzip les
--   let defaultBranch' = reduceLLVM defaultBranch
--   let es' = map reduceLLVM es
--   LLVMSwitch (d, t) defaultBranch' (zip ls es')
-- reduceLLVM (LLVMBranch d onTrue onFalse) = do
--   let onTrue' = reduceLLVM onTrue
--   let onFalse' = reduceLLVM onFalse
--   LLVMBranch d onTrue' onFalse'
-- reduceLLVM (LLVMCall d ds) = do
--   LLVMCall d ds
-- reduceLLVM LLVMUnreachable = LLVMUnreachable
substLLVMData :: SubstLLVM -> LLVMData -> LLVMData
substLLVMData sub (LLVMDataLocal x) =
  case lookup (asInt x) sub of
    Just d -> d
    Nothing -> LLVMDataLocal x
substLLVMData _ d = d

substLLVM :: SubstLLVM -> LLVM -> LLVM
substLLVM sub (LLVMReturn d) = LLVMReturn $ substLLVMData sub d
substLLVM sub (LLVMLet x op cont) = do
  let op' = substLLVMOp sub op
  let sub' = filter (\(y, _) -> y /= asInt x) sub
  let cont' = substLLVM sub' cont
  LLVMLet x op' cont'
substLLVM sub (LLVMCont op cont) = do
  let op' = substLLVMOp sub op
  let cont' = substLLVM sub cont
  LLVMCont op' cont'
substLLVM sub (LLVMSwitch (d, t) defaultBranch les) = do
  let (ls, es) = unzip les
  let d' = substLLVMData sub d
  let defaultBranch' = substLLVM sub defaultBranch
  let es' = map (substLLVM sub) es
  LLVMSwitch (d', t) defaultBranch' (zip ls es')
substLLVM sub (LLVMBranch d onTrue onFalse) = do
  let d' = substLLVMData sub d
  let onTrue' = substLLVM sub onTrue
  let onFalse' = substLLVM sub onFalse
  LLVMBranch d' onTrue' onFalse'
substLLVM sub (LLVMCall d ds) = do
  let d' = substLLVMData sub d
  let ds' = map (substLLVMData sub) ds
  LLVMCall d' ds'
substLLVM _ LLVMUnreachable = LLVMUnreachable

substLLVMOp :: SubstLLVM -> LLVMOp -> LLVMOp
substLLVMOp sub (LLVMOpCall d ds) = do
  let d' = substLLVMData sub d
  let ds' = map (substLLVMData sub) ds
  LLVMOpCall d' ds'
substLLVMOp sub (LLVMOpGetElementPtr (d, t) dts) = do
  let d' = substLLVMData sub d
  let (ds, ts) = unzip dts
  let ds' = map (substLLVMData sub) ds
  LLVMOpGetElementPtr (d', t) (zip ds' ts)
substLLVMOp sub (LLVMOpBitcast d t1 t2) = do
  let d' = substLLVMData sub d
  LLVMOpBitcast d' t1 t2
substLLVMOp sub (LLVMOpIntToPointer d t1 t2) = do
  let d' = substLLVMData sub d
  LLVMOpIntToPointer d' t1 t2
substLLVMOp sub (LLVMOpPointerToInt d t1 t2) = do
  let d' = substLLVMData sub d
  LLVMOpPointerToInt d' t1 t2
substLLVMOp sub (LLVMOpLoad d t) = do
  let d' = substLLVMData sub d
  LLVMOpLoad d' t
substLLVMOp sub (LLVMOpStore t d1 d2) = do
  let d1' = substLLVMData sub d1
  let d2' = substLLVMData sub d2
  LLVMOpStore t d1' d2'
substLLVMOp sub (LLVMOpAlloc d sizeInfo) = do
  let d' = substLLVMData sub d
  LLVMOpAlloc d' sizeInfo
substLLVMOp sub (LLVMOpFree d sizeInfo i) = do
  let d' = substLLVMData sub d
  LLVMOpFree d' sizeInfo i
substLLVMOp sub (LLVMOpUnaryOp op d) = do
  let d' = substLLVMData sub d
  LLVMOpUnaryOp op d'
substLLVMOp sub (LLVMOpBinaryOp op d1 d2) = do
  let d1' = substLLVMData sub d1
  let d2' = substLLVMData sub d2
  LLVMOpBinaryOp op d1' d2'
substLLVMOp sub (LLVMOpSysCall i ds) = do
  let ds' = map (substLLVMData sub) ds
  LLVMOpSysCall i ds'
