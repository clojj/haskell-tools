{-# LANGUAGE TypeFamilies #-}

module TypeEqualityContextSynonyms where

import Definitions

{-@ GADTs @-}

f :: EqRel a b => a -> b  {-* TypeFamilies + GADTs, TypeFamilies + GADTs *-}
f = id

g :: TrfAB a b  {-* TypeFamilies + GADTs, TypeFamilies + GADTs *-}
g = id
