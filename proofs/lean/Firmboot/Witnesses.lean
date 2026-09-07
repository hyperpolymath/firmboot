import Firmboot.Continuity
import Firmboot.Timing

/-!
Non-vacuity and counterexample witnesses are kernel-reduced using `decide`.
They are examples in addition to (not replacements for) the general proofs.
-/
namespace Firmboot.Witnesses
open Continuity

/-- Every well-formed V1 state has a candidate accepted by the normalized guard. -/
theorem v1_migration_admitted (old : V1) (history : List Bool) (h : old.Valid)
    (frames : List Frame) (events : List Event) :
    let s : State := ⟨old.cursor, .v1, recent history, frames, events⟩
    let migrated := migrate12 old history
    let c : Candidate := ⟨.v2, migrated.cursor, migrated.window⟩
    compatible s c = true ∧ (activate s (some c)).owner = .v2 := by
  dsimp
  have hc : compatible ⟨old.cursor, .v1, recent history, frames, events⟩
      ⟨.v2, (migrate12 old history).cursor, (migrate12 old history).window⟩ = true := by
    simp [compatible, migrate12_identity old history h, migrate12_window]
  exact ⟨hc, accepted_installs_target _ _ hc⟩

/-- V1 has no local window; the normalized model retains the resident history. -/
theorem v2_migration_admitted (old : V2) (frames : List Frame) (events : List Event) :
    let s : State := ⟨old.cursor, .v2, old.window, frames, events⟩
    let c : Candidate := ⟨.v1, (migrate21 old).cursor, old.window⟩
    compatible s c = true ∧ (activate s (some c)).owner = .v1 := by
  dsimp
  have hc : compatible ⟨old.cursor, .v2, old.window, frames, events⟩
      ⟨.v1, (migrate21 old).cursor, old.window⟩ = true := by
    simp [compatible, migrate21_identity]
  exact ⟨hc, accepted_installs_target _ _ hc⟩

def threeHigh : State := run initial [(true, none), (true, none), (true, none)]

def toV2 : Candidate := ⟨.v2, threeHigh.cursor, threeHigh.window⟩

def changed : State := activate threeHigh (some toV2)

def toV1 : Candidate :=
  let s := process changed true
  ⟨.v1, s.cursor, s.window⟩

theorem real_bidirectional_handover :
    threeHigh.owner = .v1 ∧ changed.owner = .v2 ∧
    (tick changed (true, some toV1)).owner = .v1 ∧
    ids (tick changed (true, some toV1)) = [1] := by decide

theorem target_algorithm_changes :
    ids (run changed [(false, none), (true, none), (true, none), (false, none)]) = [1] ∧
    ids (run threeHigh [(false, none), (true, none), (true, none), (false, none)]) = [5, 1] := by
  decide

/-- Deliberately bypassing the guard and clearing ownership repeats a report. -/
def brokenReset : State :=
  { changed with cursor := { changed.cursor with reported := false } }

theorem unchecked_reset_duplicates :
    ids (process brokenReset true) = [1, 1] := by decide

theorem guard_rejects_reset :
    activate changed (some ⟨.v1, brokenReset.cursor, changed.window⟩) = changed := by decide

/-- Rewinding to the pre-preparation cursor would also rewind the next index. -/
def stale : Candidate := ⟨.v2, initial.cursor, []⟩

theorem guard_rejects_stale : activate threeHigh (some stale) = threeHigh := by decide

end Firmboot.Witnesses
