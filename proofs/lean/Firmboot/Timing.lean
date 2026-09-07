import Std

namespace Firmboot.Timing

/-- Assigned costs, not measured worst-case execution times. -/
structure Budget where
  capture : Nat
  current : Nat
  target : Nat
  prepare : Nat
  commit : Nat
  deadline : Nat
  period : Nat
  deriving DecidableEq, Repr

def Admitted (b : Budget) : Prop :=
  b.capture + b.current + max b.prepare b.commit ≤ b.deadline ∧
  b.capture + b.target ≤ b.deadline ∧ b.deadline ≤ b.period

inductive Phase where
  | idle | preparing | committing
  deriving DecidableEq, Repr

def overhead (b : Budget) : Phase → Nat
  | .idle => 0
  | .preparing => b.prepare
  | .committing => b.commit

theorem transition_deadline (b : Budget) (h : Admitted b) (phase : Phase) :
    b.capture + b.current + overhead b phase ≤ b.deadline := by
  rcases h with ⟨ht, _, _⟩
  cases phase <;> simp only [overhead] <;> omega

theorem target_deadline (b : Budget) (h : Admitted b) :
    b.capture + b.target ≤ b.deadline := h.2.1

/-- The assigned completion precedes the next arrival, for every input index. -/
theorem completion_before_next_arrival (b : Budget) (h : Admitted b)
    (phase : Phase) (index : Nat) :
    index * b.period + (b.capture + b.current + overhead b phase) ≤
      (index + 1) * b.period := by
  have ht := transition_deadline b h phase
  have hp := h.2.2
  rw [Nat.add_mul]
  simp only [Nat.one_mul]
  omega

theorem decision_delay (b : Budget) (h : Admitted b) (phase : Phase) (arrival : Nat) :
    (arrival + (b.capture + b.current + overhead b phase)) - arrival ≤ b.deadline := by
  simpa using transition_deadline b h phase

/-- A positive pause longer than the deadline cannot deliver a decision on time,
even if capture continues and an unlimited FIFO prevents observation loss. -/
theorem pause_exceeds_deadline (arrival pause work deadline : Nat) (h : deadline < pause) :
    deadline < (arrival + pause + work) - arrival := by omega

/-- Concrete counterexample: individually admitted phases cannot be combined. -/
theorem overlapping_phases_can_miss :
    let b : Budget := ⟨1, 2, 3, 2, 2, 5, 10⟩
    Admitted b ∧ b.deadline < b.capture + b.current + b.prepare + b.commit := by
  dsimp [Admitted]
  decide

end Firmboot.Timing
