{-# OPTIONS --safe --without-K #-}
module Firmboot.Lifecycle where

open import Firmboot.Prelude
open import Firmboot.Detector
open import Firmboot.Admission
import EpistemicTypes.ReadConsistency as Read

-- The protected service projection includes the cursor/report flag and full
-- observation/event history. Version and concrete detector representation may
-- change. Preservation applies at the current post-sample boundary.
record Protected : Set where
  constructor protected
  field
    protectedCursor : Cursor
    protectedHistory : List Bool
    protectedFrames : List Frame
    protectedEvents : List Event
open Protected public

observeService : Boundary -> Protected
observeService b = protected (currentCursor b) (history b) (frames b) (events b)

installedBoundary : Machine -> Proposal -> Boundary
installedBoundary m p = boundary (replacement p) (history (current m))
  (frames (current m)) (events (current m))

-- Installation requires admission, including exactly one old authority. The
-- result contains exactly one authority for the target. This is operational
-- resource accounting, not a claim that Agda itself has linear variables.
install : (m : Machine) (p : Proposal) -> Admission m p -> Machine
install m p a = machine (Read.write (store m) (installedBoundary m p)) (target p ∷ [])

installProtected : (m : Machine) (p : Proposal) (a : Admission m p) ->
  observeService (current (install m p a)) ≡ observeService (current m)
installProtected m p a = cong
  (λ c -> protected c (history (current m)) (frames (current m)) (events (current m)))
  (admittedCursor a)

installOwned : (m : Machine) (p : Proposal) (a : Admission m p) -> WellOwned (install m p a)
installOwned m p a = sym (cong (λ v -> v ∷ []) (admittedOwner a))

installTarget : (m : Machine) (p : Proposal) (a : Admission m p) ->
  currentOwner (current (install m p a)) ≡ target p
installTarget m p a = admittedOwner a

finish : Machine -> Proposal -> Machine
finish m p with check m p
... | yes a = install m p a
... | no _ = m

finishProtected : (m : Machine) (p : Proposal) ->
  observeService (current (finish m p)) ≡ observeService (current m)
finishProtected m p with check m p
... | yes a = installProtected m p a
... | no _ = refl

finishOwned : (m : Machine) (p : Proposal) -> WellOwned m -> WellOwned (finish m p)
finishOwned m p owned with check m p
... | yes a = installOwned m p a
... | no _ = owned

rejectedUnchanged : (m : Machine) (p : Proposal) -> ¬ (Admission m p) -> finish m p ≡ m
rejectedUnchanged m p refute with check m p
... | yes a with refute a
...   | ()
rejectedUnchanged m p refute | no _ = refl

-- Any predicate on the protected projection is preserved by finish. The
-- theorem requires the predicate to hold before activation; it does not
-- invent an initial journal-consistency or sensor-correctness invariant.
finishPreservesInvariant : (I : Protected -> Set) (m : Machine) (p : Proposal) ->
  I (observeService (current m)) -> I (observeService (current (finish m p)))
finishPreservesInvariant I m p proof = subst I (sym (finishProtected m p)) proof

record Controller : Set where
  constructor controller
  field
    service : Machine
    pending : Maybe Version
open Controller public

initialController : Controller
initialController = controller initialMachine nothing

-- Preparation owns only its target slot. It holds no copy of the output
-- authority. These phases model control state, not arbitrary worker effects.
data Action : Set where
  wait : Action
  prepare : Version -> Action
  cancel : Action
  commitPrepared : Action
  switchNow : Version -> Action
  offer : Proposal -> Action

atBoundary : Controller -> Action -> Controller
atBoundary c wait = c
atBoundary (controller m nothing) (prepare v) = controller m (just v)
atBoundary (controller m (just old)) (prepare v) = controller m (just old)
atBoundary (controller m pending) cancel = controller m nothing
atBoundary (controller m nothing) commitPrepared = controller m nothing
atBoundary (controller m (just v)) commitPrepared = controller (finish m (proposeCurrent m v)) nothing
atBoundary (controller m pending) (switchNow v) = controller (finish m (proposeCurrent m v)) nothing
atBoundary (controller m pending) (offer p) = controller (finish m p) nothing

boundaryProtected : (c : Controller) (a : Action) ->
  observeService (current (service (atBoundary c a))) ≡ observeService (current (service c))
boundaryProtected c wait = refl
boundaryProtected (controller m nothing) (prepare v) = refl
boundaryProtected (controller m (just old)) (prepare v) = refl
boundaryProtected (controller m p) cancel = refl
boundaryProtected (controller m nothing) commitPrepared = refl
boundaryProtected (controller m (just v)) commitPrepared = finishProtected m (proposeCurrent m v)
boundaryProtected (controller m p) (switchNow v) = finishProtected m (proposeCurrent m v)
boundaryProtected (controller m p) (offer proposed) = finishProtected m proposed

boundaryOwned : (c : Controller) (a : Action) ->
  WellOwned (service c) -> WellOwned (service (atBoundary c a))
boundaryOwned c wait proof = proof
boundaryOwned (controller m nothing) (prepare v) proof = proof
boundaryOwned (controller m (just old)) (prepare v) proof = proof
boundaryOwned (controller m p) cancel proof = proof
boundaryOwned (controller m nothing) commitPrepared proof = proof
boundaryOwned (controller m (just v)) commitPrepared proof = finishOwned m (proposeCurrent m v) proof
boundaryOwned (controller m p) (switchNow v) proof = finishOwned m (proposeCurrent m v) proof
boundaryOwned (controller m p) (offer proposed) proof = finishOwned m proposed proof

-- One input is processed before every boundary action. Sampling retains the
-- authority list and processOwner proves that its owner has not changed.
sample : Machine -> Bool -> Machine
sample m input = machine (Read.write (store m) (process (current m) input)) (authorities m)

sampleOwned : (m : Machine) (input : Bool) -> WellOwned m -> WellOwned (sample m input)
sampleOwned m input proof = trans proof (sym (cong (λ v -> v ∷ []) (processOwner (current m) input)))

tick : Controller -> Bool -> Action -> Controller
tick (controller m p) input action = atBoundary (controller (sample m input) p) action

tickProtected : (c : Controller) (input : Bool) (action : Action) ->
  observeService (current (service (tick c input action))) ≡
  observeService (process (current (service c)) input)
tickProtected (controller m p) input action = boundaryProtected (controller (sample m input) p) action

tickOwned : (c : Controller) (input : Bool) (action : Action) ->
  WellOwned (service c) -> WellOwned (service (tick c input action))
tickOwned (controller m p) input action proof = boundaryOwned (controller (sample m input) p)
  action (sampleOwned m input proof)

tickFrames : (c : Controller) (input : Bool) (action : Action) ->
  frames (current (service (tick c input action))) ≡
  frame (suc (position (currentCursor (current (service c))))) input
    (currentOwner (current (service c))) ∷ frames (current (service c))
tickFrames c input action = cong protectedFrames (tickProtected c input action)

tickPosition : (c : Controller) (input : Bool) (action : Action) ->
  position (currentCursor (current (service (tick c input action)))) ≡
  suc (position (currentCursor (current (service c))))
tickPosition c input action = trans
  (cong (λ p -> position (protectedCursor p)) (tickProtected c input action))
  (processPosition (current (service c)) input)

record Input : Set where
  constructor input
  field
    bit : Bool
    action : Action
open Input public

run : Controller -> List Input -> Controller
run c [] = c
run c (input bit action ∷ rest) = run (tick c bit action) rest

runOwned : (c : Controller) (inputs : List Input) -> WellOwned (service c) ->
  WellOwned (service (run c inputs))
runOwned c [] proof = proof
runOwned c (input bit action ∷ rest) proof = runOwned (tick c bit action) rest (tickOwned c bit action proof)

singleAuthorityForEveryRun : (inputs : List Input) -> WellOwned (service (run initialController inputs))
singleAuthorityForEveryRun inputs = runOwned initialController inputs refl

runPosition : (c : Controller) (inputs : List Input) ->
  position (currentCursor (current (service (run c inputs)))) ≡
  length inputs + position (currentCursor (current (service c)))
runPosition c [] = refl
runPosition c (input bit action ∷ rest) = trans
  (runPosition (tick c bit action) rest)
  (trans (cong (λ n -> length rest + n) (tickPosition c bit action)) (plusSuc (length rest) _))
  where
    plusSuc : (m n : Nat) -> m + suc n ≡ suc (m + n)
    plusSuc zero n = refl
    plusSuc (suc m) n = cong suc (plusSuc m n)

-- An exact trace law for arbitrary finite executions: observations are added
-- once per input, with no change to earlier frame values by any update action.
recordedValues : Controller -> List Bool
recordedValues c = map value (frames (current (service c)))

accumulate : List Bool -> List Input -> List Bool
accumulate old [] = old
accumulate old (input bit action ∷ rest) = accumulate (bit ∷ old) rest

runValues : (c : Controller) (inputs : List Input) ->
  recordedValues (run c inputs) ≡ accumulate (recordedValues c) inputs
runValues c [] = refl
runValues c (input bit action ∷ rest) = trans (runValues (tick c bit action) rest)
  (cong (λ vs -> accumulate vs rest) (cong (map value) (tickFrames c bit action)))

recordedIndices : Controller -> List Nat
recordedIndices c = map sequence (frames (current (service c)))

accumulateIndices : Nat -> List Nat -> List Input -> List Nat
accumulateIndices pos old [] = old
accumulateIndices pos old (input bit action ∷ rest) =
  accumulateIndices (suc pos) (suc pos ∷ old) rest

runIndices : (c : Controller) (inputs : List Input) ->
  recordedIndices (run c inputs) ≡
  accumulateIndices (position (currentCursor (current (service c)))) (recordedIndices c) inputs
runIndices c [] = refl
runIndices c (input bit action ∷ rest) = trans (runIndices (tick c bit action) rest)
  (cong₂ (λ pos indices -> accumulateIndices pos indices rest)
    (tickPosition c bit action) (cong (map sequence) (tickFrames c bit action)))

-- Newest-first journal storage: an earlier committed journal is an unchanged
-- suffix of the later journal. Inputs may append events; updates may not edit,
-- remove, or append to the post-sample committed journal.
JournalExtends : Boundary -> Boundary -> Set
JournalExtends before after = Σ (List Event) (λ added -> events after ≡ added ++ events before)

recordEventExtends : (new : Maybe Event) (old : List Event) ->
  Σ (List Event) (λ added -> recordEvent new old ≡ added ++ old)
recordEventExtends nothing old = [] , refl
recordEventExtends (just e) old = (e ∷ []) , refl

processJournal : (b : Boundary) (sampleBit : Bool) -> JournalExtends b (process b sampleBit)
processJournal b sampleBit = recordEventExtends
  (newEvent (decideSample (currentOwner b) (currentCursor b)
    (recent (history b ++ (sampleBit ∷ []))) sampleBit)) (events b)

tickJournal : (c : Controller) (sampleBit : Bool) (action : Action) ->
  JournalExtends (current (service c)) (current (service (tick c sampleBit action)))
tickJournal c sampleBit action with processJournal (current (service c)) sampleBit
... | added , eq = added , trans (cong protectedEvents (tickProtected c sampleBit action)) eq

composeJournal : {a b c : Boundary} -> JournalExtends a b -> JournalExtends b c -> JournalExtends a c
composeJournal {a} (first , eq₁) (second , eq₂) = (second ++ first) ,
  trans eq₂ (trans (cong (λ tail -> second ++ tail) eq₁) (sym (appendAssoc second first (events a))))

runJournal : (c : Controller) (inputs : List Input) ->
  JournalExtends (current (service c)) (current (service (run c inputs)))
runJournal c [] = [] , refl
runJournal c (input bit action ∷ rest) = composeJournal
  {a = current (service c)}
  {b = current (service (tick c bit action))}
  {c = current (service (run (tick c bit action) rest))}
  (tickJournal c bit action) (runJournal (tick c bit action) rest)

oneAuthorityCount : (inputs : List Input) -> length (authorities (service (run initialController inputs))) ≡ 1
oneAuthorityCount inputs = cong length (singleAuthorityForEveryRun inputs)
