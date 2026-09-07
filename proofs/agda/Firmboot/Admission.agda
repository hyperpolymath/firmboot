{-# OPTIONS --safe --without-K #-}
module Firmboot.Admission where

open import Firmboot.Prelude
open import Firmboot.Detector
open import Firmboot.Retention
import EpistemicTypes.ReadConsistency as Read
import EpistemicTypes.EchoBridge as E

record Machine : Set where
  constructor machine
  field
    store : Read.Store Boundary
    authorities : List Version
open Machine public

current : Machine -> Boundary
current m = Read.contents (store m)

WellOwned : Machine -> Set
WellOwned m = authorities m ≡ currentOwner (current m) ∷ []

initialMachine : Machine
initialMachine = machine (Read.initial initial) (v1 ∷ [])

record Proposal : Set where
  constructor proposal
  field
    generation : Nat
    target : Version
    proposedCursor : Cursor
    proposedWindow : List Bool
    replacement : Representation
open Proposal public

proposeCurrent : Machine -> Version -> Proposal
proposeCurrent m target = proposal (Read.version (store m)) target
  (currentCursor (current m)) (recent (history (current m)))
  (targetState target (current m))

-- Each conjunct has an executable decision below. This relation records the
-- conservative activation policy for these known representations. It adds
-- explicit generation/authority/residue evidence to the runtime's format
-- relation. V2 needs three samples even when a particular behaviour needs less.
record AdmissionAt (epoch : Nat) (b : Boundary) (caps : List Version)
  (p : Proposal) : Set where
  constructor admitted
  field
    currentGeneration : generation p ≡ epoch
    soleAuthority : caps ≡ currentOwner b ∷ []
    changesVersion : ¬ (target p ≡ currentOwner b)
    currentCursorMatches : proposedCursor p ≡ currentCursor b
    currentWindowMatches : proposedWindow p ≡ recent (history b)
    enoughHistory : requiredHistory (target p) ≤ length (history b)
    correctRepresentation : replacement p ≡ build (target p) (proposedCursor p) (proposedWindow p)
open AdmissionAt public

Admission : Machine -> Proposal -> Set
Admission m p = AdmissionAt (Read.version (store m)) (current m) (authorities m) p

checkAt : (epoch : Nat) (b : Boundary) (caps : List Version) (p : Proposal) ->
  Dec (AdmissionAt epoch b caps p)
checkAt epoch b caps p with natEq (generation p) epoch
... | no bad = no (λ a -> bad (currentGeneration a))
... | yes stamp with listEq versionEq caps (currentOwner b ∷ [])
...   | no bad = no (λ a -> bad (soleAuthority a))
...   | yes authority with versionEq (target p) (currentOwner b)
...     | yes same = no (λ a -> changesVersion a same)
...     | no different with cursorEq (proposedCursor p) (currentCursor b)
...       | no bad = no (λ a -> bad (currentCursorMatches a))
...       | yes cursorOK with listEq boolEq (proposedWindow p) (recent (history b))
...         | no bad = no (λ a -> bad (currentWindowMatches a))
...         | yes windowOK with ≤? (requiredHistory (target p)) (length (history b))
...           | no bad = no (λ a -> bad (enoughHistory a))
...           | yes historyOK with representationEq (replacement p)
  (build (target p) (proposedCursor p) (proposedWindow p))
...             | no bad = no (λ a -> bad (correctRepresentation a))
...             | yes representationOK = yes
  (admitted stamp authority different cursorOK windowOK historyOK representationOK)

-- The supplied read must be coherent with this store, not a free label. A
-- historical view cannot be silently used here as a view of a later write.
checkUsingView : (m : Machine) -> Read.ReadView (store m) -> (p : Proposal) -> Dec (Admission m p)
checkUsingView m (Read.readView b matches) p with matches
... | refl = checkAt (Read.version (store m)) b (authorities m) p

check : (m : Machine) (p : Proposal) -> Dec (Admission m p)
check m p = checkUsingView m (Read.readCurrent (store m)) p

-- Positive and negative results both carry evidence of their exact meaning.
acceptanceSound : (m : Machine) (p : Proposal) -> isYes (check m p) ≡ true -> Admission m p
acceptanceSound m p with check m p
... | yes a = λ _ -> a
... | no _ = λ ()

rejectionSound : (m : Machine) (p : Proposal) -> isYes (check m p) ≡ false -> ¬ (Admission m p)
rejectionSound m p with check m p
... | yes _ = λ ()
... | no reason = λ _ -> reason

admittedEcho : {m : Machine} {p : Proposal} -> Admission m p ->
  E.Echo detectorRetention (proposedCursor p)
admittedEcho {m} {p} a = E.echo (proposedWindow p)
  (subst (λ w -> length w ≤ three) (sym (currentWindowMatches a)) (recentBound (history (current m))))

admittedSourceMatches : {m : Machine} {p : Proposal} (a : Admission m p) ->
  E.MatchesSource detectorRetention (current m) (admittedEcho a)
admittedSourceMatches a = E.matchesSource
  (sym (currentCursorMatches a)) (sym (currentWindowMatches a))

admittedMigration : {m : Machine} {p : Proposal} -> Admission m p ->
  replacement p ≡ targetState (target p) (current m)
admittedMigration {m} {p} a = trans (correctRepresentation a)
  (E.migrateMatching (migration (target p)) (current m) (admittedEcho a) (admittedSourceMatches a))

admittedCursor : {m : Machine} {p : Proposal} -> Admission m p ->
  viewCursor (replacement p) ≡ currentCursor (current m)
admittedCursor {m} {p} a = trans (cong viewCursor (admittedMigration a))
  (buildCursor (target p) (currentCursor (current m)) (recent (history (current m))))

admittedOwner : {m : Machine} {p : Proposal} -> Admission m p -> owner (replacement p) ≡ target p
admittedOwner {m} {p} a = trans (cong owner (admittedMigration a))
  (buildOwner (target p) (currentCursor (current m)) (recent (history (current m))))

-- No old stamped proposal can be admitted after even one store write.
readImpossible : Read.⊥ -> ⊥
readImpossible ()

oldGenerationRejected : (m : Machine) (p : Proposal) (next : Boundary) ->
  generation p ≡ Read.version (store m) ->
  ¬ (Admission (machine (Read.write (store m) next) (authorities m)) p)
oldGenerationRejected m p next stamp a =
  readImpossible (Read.<-irrefl
    (subst (λ n -> Read._<_ (Read.version (store m)) n)
      (sym (trans (sym stamp) (currentGeneration a)))
      (Read.s≤s Read.≤-refl)))
