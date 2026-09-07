{-# OPTIONS --safe --without-K #-}
module Firmboot.Examples where

open import Firmboot.Prelude
open import Firmboot.Detector
open import Firmboot.Retention
open import Firmboot.Admission
open import Firmboot.Lifecycle
import EpistemicTypes.ReadConsistency as Read

atOne : Machine
atOne = sample initialMachine true
atTwo : Machine
atTwo = sample atOne true
atThree : Machine
atThree = sample atTwo true
atFour : Machine
atFour = sample atThree true

good : Proposal
good = proposeCurrent atThree v2

goodAccepted : Admission atThree good
goodAccepted = acceptanceSound atThree good refl

installed : Machine
installed = finish atThree good

activationChangesVersion : currentOwner (current installed) ≡ v2
activationChangesVersion = refl
activationKeepsReport : ongoing (currentCursor (current installed)) ≡ just (episode 1 true)
activationKeepsReport = refl
activationKeepsJournal : events (current installed) ≡ event 1 2 v1 ∷ []
activationKeepsJournal = refl
activationKeepsPosition : position (currentCursor (current installed)) ≡ 3
activationKeepsPosition = refl
activationTransfersSoleAuthority : authorities installed ≡ v2 ∷ []
activationTransfersSoleAuthority = refl

stale : Proposal
stale = good
staleRejected : ¬ (Admission atFour stale)
staleRejected = oldGenerationRejected atThree good (process (current atThree) true) refl
staleRejectionKeepsCurrent : finish atFour stale ≡ atFour
staleRejectionKeepsCurrent = rejectedUnchanged atFour stale staleRejected

badFlag : Proposal
badFlag = record good
  { proposedCursor = cursor 3 (just (episode 1 false))
  ; replacement = V2 (cursor 3 (just (episode 1 false))) (true ∷ true ∷ true ∷ [])
  }
badFlagRejected : ¬ (Admission atThree badFlag)
badFlagRejected = rejectionSound atThree badFlag refl

badWindow : Proposal
badWindow = record good
  { proposedWindow = false ∷ true ∷ true ∷ []
  ; replacement = V2 (cursor 3 (just (episode 1 true))) (false ∷ true ∷ true ∷ [])
  }
badWindowRejected : ¬ (Admission atThree badWindow)
badWindowRejected = rejectionSound atThree badWindow refl

badRepresentation : Proposal
badRepresentation = record good { replacement = V2 (cursor 2 (just (episode 1 true))) (true ∷ true ∷ true ∷ []) }
badRepresentationRejected : ¬ (Admission atThree badRepresentation)
badRepresentationRejected = rejectionSound atThree badRepresentation refl

shortHistoryRejected : ¬ (Admission atTwo (proposeCurrent atTwo v2))
shortHistoryRejected = rejectionSound atTwo (proposeCurrent atTwo v2) refl

noAuthority : Machine
noAuthority = machine (store atThree) []
noAuthorityRejected : ¬ (Admission noAuthority good)
noAuthorityRejected = rejectionSound noAuthority good refl

duplicatedAuthority : Machine
duplicatedAuthority = machine (store atThree) (v1 ∷ v1 ∷ [])
duplicatedAuthorityRejected : ¬ (Admission duplicatedAuthority good)
duplicatedAuthorityRejected = rejectionSound duplicatedAuthority good refl

-- The activation-boundary sample belongs to V1; the next sample belongs to V2.
handoverRun : Controller
handoverRun = run initialController
  (input true wait ∷ input true wait ∷ input true (switchNow v2) ∷ input true wait ∷ [])

exactHandoverFrames : map processedBy (frames (current (service handoverRun))) ≡ v2 ∷ v1 ∷ v1 ∷ v1 ∷ []
exactHandoverFrames = refl
noRepeatAfterHandover : events (current (service handoverRun)) ≡ event 1 2 v1 ∷ []
noRepeatAfterHandover = refl

-- Preparing does not pause processing, and cancellation preserves the state
-- produced by the cancellation tick. V1 still reports at its second sample.
cancelledRun : Controller
cancelledRun = run initialController
  (input true (prepare v2) ∷ input true wait ∷ input true cancel ∷ [])
cancelledKeepsSamples : recordedValues cancelledRun ≡ true ∷ true ∷ true ∷ []
cancelledKeepsSamples = refl
cancelledKeepsReport : events (current (service cancelledRun)) ≡ event 1 2 v1 ∷ []
cancelledKeepsReport = refl
cancelledKeepsAuthority : authorities (service cancelledRun) ≡ v1 ∷ []
cancelledKeepsAuthority = refl
cancelledClearsOnlyPending : pending cancelledRun ≡ nothing
cancelledClearsOnlyPending = refl

-- Preparation records the target only; the proposal is built from current
-- state at commit, even after further inputs have been processed.
preparedRun : Controller
preparedRun = run initialController
  (input true (prepare v2) ∷ input true wait ∷ input true commitPrepared ∷ [])
preparedUsesCurrent : position (currentCursor (current (service preparedRun))) ≡ 3
preparedUsesCurrent = refl
preparedActivates : currentOwner (current (service preparedRun)) ≡ v2
preparedActivates = refl

-- Return migration reconstructs V1's count from the current episode cursor.
returned : Machine
returned = finish installed (proposeCurrent installed v1)
returnReconstructsCount : detector (current returned) ≡ V1 (cursor 3 (just (episode 1 true))) 3
returnReconstructsCount = refl
returnKeepsJournal : events (current returned) ≡ event 1 2 v1 ∷ []
returnKeepsJournal = refl

-- Checked evidence is indexed by the exact current machine state.
currentRead : Read.ReadView (store atThree)
currentRead = Read.readCurrent (store atThree)
viewBasedAcceptance : isYes (checkUsingView atThree currentRead good) ≡ true
viewBasedAcceptance = refl
