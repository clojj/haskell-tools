{-# LANGUAGE LambdaCase #-}
module Language.Haskell.Tools.Refactor.OrganizeImports where

import SrcLoc
import Name hiding (Name)
import GHC (Ghc, GhcMonad, lookupGlobalName, TyThing(..), moduleNameString, moduleName)
import qualified GHC
import TyCon
import ConLike
import DataCon
import Outputable (ppr, showSDocUnsafe)

import Control.Reference hiding (element)
import Control.Monad
import Control.Monad.IO.Class
import Data.Function hiding ((&))
import Data.String
import Data.Maybe
import Data.Data
import Data.List
import Data.Generics.Uniplate.Data
import Language.Haskell.Tools.AST
import Language.Haskell.Tools.AST.FromGHC
import Language.Haskell.Tools.AnnTrf.SourceTemplate
import Language.Haskell.Tools.AnnTrf.SourceTemplateHelpers
import Language.Haskell.Tools.PrettyPrint
import Language.Haskell.Tools.Refactor.DebugGhcAST
import Language.Haskell.Tools.AST.Gen
import Debug.Trace

type STWithNames = NodeInfo SemanticInfo SourceTemplate

organizeImports :: Ann Module STWithNames -> Ghc (Ann Module STWithNames)
organizeImports mod
  = element&modImports&annListElems !~ narrowImports usedNames . sortImports $ mod
  where usedNames :: [GHC.Name]
        usedNames = catMaybes $ map (^? (annotation&semanticInfo&nameInfo)) 
                              $ (universeBi (mod ^. element&modHead) ++ universeBi (mod ^. element&modDecl) :: [Ann Name STWithNames])
        
sortImports :: [Ann ImportDecl STWithNames] -> [Ann ImportDecl STWithNames]
sortImports = sortBy (ordByOccurrence `on` (^. element&importModule&element))

narrowImports :: [GHC.Name] -> [Ann ImportDecl STWithNames] -> Ghc [Ann ImportDecl STWithNames]
narrowImports usedNames imps = foldM (narrowOneImport usedNames) imps imps 
  where narrowOneImport :: [GHC.Name] -> [Ann ImportDecl STWithNames] -> Ann ImportDecl STWithNames -> Ghc [Ann ImportDecl STWithNames]
        narrowOneImport names all one =
          (\case Just x -> map (\e -> if e == one then x else e) all
                 Nothing -> delete one all) <$> narrowImport names (map semantics all) one 
        
narrowImport :: [GHC.Name] -> [SemanticInfo] -> Ann ImportDecl STWithNames 
                           -> Ghc (Maybe (Ann ImportDecl STWithNames))
narrowImport usedNames otherModules imp
  | importIsExact (imp ^. element) 
  = Just <$> (element&importSpec&annJust&element&importSpecList !~ narrowImportSpecs usedNames $ imp)
  | otherwise 
  = if null actuallyImported
      then if length (otherModules ^? traversal&importedModule&filtered (== importedMod) :: [GHC.Module]) > 1 
              then pure Nothing
              else Just <$> (element&importSpec !- toJust (mkImportSpecList []) $ imp)
      else pure (Just imp)
  where actuallyImported = fromJust (imp ^? annotation&semanticInfo&importedNames) `intersect` usedNames
        Just importedMod = imp ^? annotation&semanticInfo&importedModule
    
narrowImportSpecs :: [GHC.Name] -> AnnList IESpec STWithNames -> Ghc (AnnList IESpec STWithNames)
narrowImportSpecs usedNames 
  = (annList&element !~ narrowSpecSubspec usedNames) 
       >=> return . filterList isNeededSpec
  where narrowSpecSubspec :: [GHC.Name] -> IESpec STWithNames -> Ghc (IESpec STWithNames)
        narrowSpecSubspec usedNames spec 
          = do let Just specName = spec ^? ieName&annotation&semanticInfo&nameInfo
               Just tt <- GHC.lookupName specName
               let subspecsInScope = case tt of ATyCon tc | not (isClassTyCon tc) 
                                                  -> map getName (tyConDataCons tc) `intersect` usedNames
                                                _ -> usedNames
               ieSubspec&annJust !- narrowImportSubspecs subspecsInScope $ spec
  
        isNeededSpec :: Ann IESpec STWithNames -> Bool
        isNeededSpec ie = 
          -- if the name is used, it is needed
          (ie ^? element&ieName&annotation&semanticInfo&nameInfo) `elem` map Just usedNames
          -- if the name is not used, but some of its constructors are used, it is needed
            || ((ie ^? element&ieSubspec&annJust&element&essList&annList) /= [])
            || (case ie ^? element&ieSubspec&annJust&element of Just SubSpecAll -> True; _ -> False)     
  
narrowImportSubspecs :: [GHC.Name] -> Ann SubSpec STWithNames -> Ann SubSpec STWithNames
narrowImportSubspecs [] (Ann _ SubSpecAll) = mkSubList []
narrowImportSubspecs _ ss@(Ann _ SubSpecAll) = ss
narrowImportSubspecs usedNames ss@(Ann _ (SubSpecList _)) 
  = element&essList .- filterList (\n -> (n ^? annotation&semanticInfo&nameInfo) `elem` map Just usedNames) $ ss