{-# OPTIONS --safe --without-K #-}
module Firmboot.Retention where

open import Firmboot.Prelude
open import Firmboot.Detector
import EpistemicTypes.EchoBridge as E

-- A residue certificate bounds the window; MatchesSource separately ties it
-- to the actual boundary. The certificate alone is not history provenance.
detectorRetention : E.Retention Boundary Cursor (List Bool)
E.Retention.observe detectorRetention = currentCursor
E.Retention.retain detectorRetention b = recent (history b)
E.Retention.Cert detectorRetention w c = length w ≤ three
E.Retention.sound detectorRetention b = recentBound (history b)

targetState : Version -> Boundary -> Representation
targetState target b = build target (currentCursor b) (recent (history b))

migration : (target : Version) -> E.Migration detectorRetention (targetState target)
E.Migration.migrate (migration target) = build target
E.Migration.adequate (migration target) b = refl

-- A concrete insufficiency result: the cursor alone cannot reconstruct every
-- exact V2 window. Both examples are reachable by normal V1 sample processing.
replay : Boundary -> List Bool -> Boundary
replay b [] = b
replay b (x ∷ xs) = replay (process b x) xs

leftHistory : Boundary
leftHistory = replay initial (true ∷ false ∷ false ∷ [])
rightHistory : Boundary
rightHistory = replay initial (false ∷ false ∷ false ∷ [])

cursorOnly : E.Retention Boundary Cursor ⊤
E.Retention.observe cursorOnly = currentCursor
E.Retention.retain cursorOnly _ = tt
E.Retention.Cert cursorOnly _ _ = ⊤
E.Retention.sound cursorOnly _ = tt

sameCursor : currentCursor leftHistory ≡ currentCursor rightHistory
sameCursor = refl

falseWindowEquality : targetState v2 leftHistory ≡ targetState v2 rightHistory -> E.Impossible
falseWindowEquality ()

noExactV2FromCursorAlone : E.Migration cursorOnly (targetState v2) -> E.Impossible
noExactV2FromCursorAlone = E.collisionForbidsMigration cursorOnly (targetState v2)
  leftHistory rightHistory refl refl falseWindowEquality

-- Exact state reconstruction is stronger than future-observation equivalence.
-- This counterexample does not prove three samples are minimal for all
-- observationally equivalent implementations or for V2's detection decision.
