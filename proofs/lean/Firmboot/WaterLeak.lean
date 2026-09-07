import Firmboot.Continuity

/-!
A resident warning/acknowledgement ledger around the reduced detector semantics.
Source and operator identifiers are opaque natural-number labels, not credentials.
Only the detector component is updateable. Raw measurements and acknowledgement
receipts stay resident. This is a model, not a refinement proof for Elixir or a
physical leak-detection theorem. Every list denotes a finite in-memory journal.
-/
namespace Firmboot.WaterLeak

structure Key where
  source : Nat
  episode : Nat
  deriving DecidableEq, Repr

structure Reading where
  seq : Nat
  inletMl : Nat
  outletMl : Nat
  deriving DecidableEq, Repr

structure Receipt where
  key : Key
  operator : Nat
  afterSeq : Nat
  deriving DecidableEq, Repr

structure State where
  source : Nat
  detector : Continuity.State
  readings : List Reading
  receipts : List Receipt
  deriving DecidableEq, Repr

def outstanding (s : State) (key : Key) : Bool :=
  decide (key.source = s.source ∧ key.episode ∈ Continuity.ids s.detector) &&
    !s.receipts.any (fun r => r.key == key)

def handover (s : State) (candidate : Option Continuity.Candidate) : State :=
  { s with detector := Continuity.activate s.detector candidate }

def acknowledge (s : State) (key : Key) (operator : Nat) : State :=
  if outstanding s key then
    { s with receipts := ⟨key, operator, s.detector.cursor.position⟩ :: s.receipts }
  else s

/-- Volumes cover the same interval; this chosen threshold has no physical calibration. -/
def sample (s : State) (threshold : Nat) (reading : Reading) : State :=
  if 0 < threshold ∧ reading.seq = s.detector.cursor.position + 1 then
    { s with
      detector := Continuity.process s.detector
        (decide (reading.outletMl + threshold ≤ reading.inletMl))
      readings := reading :: s.readings }
  else s

@[simp] theorem handover_readings (s : State) (c : Option Continuity.Candidate) :
    (handover s c).readings = s.readings := rfl

@[simp] theorem handover_receipts (s : State) (c : Option Continuity.Candidate) :
    (handover s c).receipts = s.receipts := rfl

@[simp] theorem handover_reports (s : State) (c : Option Continuity.Candidate) :
    (handover s c).detector.events = s.detector.events :=
  Continuity.activate_events s.detector c

@[simp] theorem handover_outstanding (s : State) (c : Option Continuity.Candidate) (key : Key) :
    outstanding (handover s c) key = outstanding s key := by
  simp [outstanding, handover, Continuity.ids]

theorem acknowledgement_discharges (s : State) (key : Key) (operator : Nat) :
    outstanding (acknowledge s key operator) key = false := by
  unfold acknowledge
  split
  · simp [outstanding]
  · rename_i h
    simpa using h

theorem acknowledgement_idempotent (s : State) (key : Key) (operator other : Nat) :
    acknowledge (acknowledge s key operator) key other = acknowledge s key operator := by
  rw [acknowledge, acknowledgement_discharges]
  rfl

theorem wrong_source_unchanged (s : State) (key : Key) (operator : Nat)
    (h : key.source ≠ s.source) : acknowledge s key operator = s := by
  simp [acknowledge, outstanding, h]

theorem unknown_warning_unchanged (s : State) (key : Key) (operator : Nat)
    (h : key.episode ∉ Continuity.ids s.detector) : acknowledge s key operator = s := by
  simp [acknowledge, outstanding, h]

theorem acknowledge_preserves_readings (s : State) (key : Key) (operator : Nat) :
    (acknowledge s key operator).readings = s.readings := by
  simp [acknowledge] <;> split <;> rfl

theorem sample_preserves_receipts (s : State) (threshold : Nat) (reading : Reading) :
    (sample s threshold reading).receipts = s.receipts := by
  simp [sample] <;> split <;> rfl

theorem sample_records_exact_reading (s : State) (threshold : Nat) (reading : Reading)
    (positive : 0 < threshold) (next : reading.seq = s.detector.cursor.position + 1) :
    (sample s threshold reading).readings = reading :: s.readings := by
  simp [sample, positive, next]

theorem wrong_sequence_unchanged (s : State) (threshold : Nat) (reading : Reading)
    (h : reading.seq ≠ s.detector.cursor.position + 1) : sample s threshold reading = s := by
  simp [sample, h]

/-- Sampling cannot discharge a previously outstanding warning, even after its
signal clears. Only the acknowledgement operation can add a receipt. -/
theorem sample_preserves_outstanding (s : State) (threshold : Nat) (reading : Reading)
    (key : Key) (h : outstanding s key = true) :
    outstanding (sample s threshold reading) key = true := by
  unfold sample
  split
  · obtain ⟨added, journal⟩ := Continuity.process_preserves_journal s.detector
      (decide (reading.outletMl + threshold ≤ reading.inletMl))
    simp only [outstanding, Bool.and_eq_true, decide_eq_true_eq] at h ⊢
    refine ⟨⟨h.1.1, ?_⟩, h.2⟩
    simp only [Continuity.ids, journal, List.map_append, List.mem_append]
    exact Or.inr h.1.2
  · exact h

/-- Acknowledgement and detector activation commute at the SAME observation boundary.
They are not claimed to commute across a sample that can create a new warning. -/
theorem acknowledge_handover_commute (s : State) (c : Option Continuity.Candidate)
    (key : Key) (operator : Nat) :
    acknowledge (handover s c) key operator = handover (acknowledge s key operator) c := by
  simp only [acknowledge, handover_outstanding]
  split <;> simp [handover]

def warned : State :=
  ⟨7, [false, false, true, true, true, true].foldl Continuity.process Continuity.initial,
    [⟨6, 1000, 850⟩, ⟨5, 1000, 850⟩, ⟨4, 1000, 850⟩,
      ⟨3, 1000, 850⟩, ⟨2, 1000, 1000⟩, ⟨1, 1000, 1000⟩], []⟩

def upgrade : Continuity.Candidate :=
  ⟨.v2, warned.detector.cursor, warned.detector.window⟩

theorem active_warning_survives :
    (handover warned (some upgrade)).detector.owner = .v2 ∧
      outstanding (handover warned (some upgrade)) ⟨7, 3⟩ = true := by decide

theorem clear_signal_keeps_obligation :
    outstanding (sample (handover warned (some upgrade)) 100 ⟨7, 1000, 1000⟩) ⟨7, 3⟩ = true := by
  decide

end Firmboot.WaterLeak
