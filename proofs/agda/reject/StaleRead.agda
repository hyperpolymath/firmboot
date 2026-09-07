{-# OPTIONS --safe --without-K #-}
module StaleRead where

open import Firmboot.Prelude
open import Firmboot.Detector
open import Firmboot.Retention
open import Firmboot.Admission
open import Firmboot.Lifecycle
open import Firmboot.Examples
import EpistemicTypes.ReadConsistency as Read

-- Deliberately false. The verifier requires a type mismatch at this claim.
falseClaim : Read.ReadView (store atFour)
falseClaim = currentRead
