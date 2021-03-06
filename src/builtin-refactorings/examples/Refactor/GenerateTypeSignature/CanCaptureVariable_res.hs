{-# LANGUAGE ScopedTypeVariables #-}
module Refactor.GenerateTypeSignature.CanCaptureVariable where

import qualified Data.Map as Map

insertMany :: forall k v . (Ord k) => (v -> v -> v) -> [(k,v)] -> Map.Map k v -> Map.Map k v
insertMany accf vs m = foldr f1 m vs
  where f1 :: Ord k => (k, v) -> Map.Map k v -> Map.Map k v
        f1 (k,v) m = Map.insertWith accf k v m