import Firmboot.Migration

/-!
A reduced execution semantics: one synchronous capture/detection step followed
by an optional guarded handover. It records exact input values and version
provenance. Preparation and deferral are represented by `none` at a boundary;
their scheduler and progress are not formalized here.

The cursor is a normalized view of either detector representation. V1's count
is reconstructed from position and episode start; V2 uses a recent input window.
Correspondence of the complete Elixir execution to this semantics remains an
obligation, not an assumption disguised as an axiom.
-/
namespace Firmboot.Continuity

structure Frame where
  seq : Nat
  value : Bool
  owner : Version
  deriving DecidableEq, Repr

structure Event where
  episode : Nat
  detectedAt : Nat
  owner : Version
  deriving DecidableEq, Repr

structure State where
  cursor : Cursor
  owner : Version
  window : List Bool
  frames : List Frame
  events : List Event
  deriving DecidableEq, Repr

def initial : State := ⟨⟨0, none, false⟩, .v1, [], [], []⟩

def ids (s : State) : List Nat := s.events.map Event.episode

/-- Reporting ownership is derived from the journal, not merely asserted by a flag. -/
structure Invariant (s : State) : Prop where
  valid : s.cursor.Valid
  unique : (ids s).Nodup
  past : ∀ e ∈ s.events, e.episode ≤ s.cursor.position
  ownership : ∀ first, s.cursor.first = some first →
    (first ∈ ids s ↔ s.cursor.reported = true)

theorem initial_invariant : Invariant initial := by
  constructor <;> simp [initial, Cursor.Valid, ids]

def eligible (v : Version) (position first : Nat) (window : List Bool) : Bool :=
  match v with
  | .v1 => decide (2 ≤ position - first + 1)
  | .v2 => decide (window = [true, true, true])

/-- A high sample either retains the committed report or publishes it once. -/
def highStep (s : State) (first : Nat) (already ready : Bool) : State :=
  { s with
    cursor := ⟨s.cursor.position + 1, some first, already || ready⟩
    events := if already then s.events else if ready then
      ⟨first, s.cursor.position + 1, s.owner⟩ :: s.events else s.events }

theorem highStep_invariant (s : State) (h : Invariant s)
    (first : Nat) (already ready : Bool)
    (hfirst : 1 ≤ first ∧ first ≤ s.cursor.position + 1)
    (howner : first ∈ ids s ↔ already = true) :
    Invariant (highStep s first already ready) := by
  cases already <;> cases ready
  · constructor
    · exact hfirst
    · exact h.unique
    · intro e he
      have := h.past e he
      change e.episode ≤ s.cursor.position + 1
      omega
    · intro f hf
      have hf' : first = f := Option.some.inj hf
      subst f
      exact howner
  · have hfresh : first ∉ ids s := by simpa using howner
    constructor
    · exact hfirst
    · exact List.nodup_cons.mpr ⟨hfresh, h.unique⟩
    · intro e he
      simp only [highStep, Bool.false_eq_true, ↓reduceIte, List.mem_cons] at he
      rcases he with rfl | he
      · exact hfirst.2
      · have := h.past e he
        change e.episode ≤ s.cursor.position + 1
        omega
    · intro f hf
      have hf' : first = f := Option.some.inj hf
      subst f
      simp [ids, highStep]
  · constructor
    · exact hfirst
    · exact h.unique
    · intro e he
      have := h.past e he
      change e.episode ≤ s.cursor.position + 1
      omega
    · intro f hf
      have hf' : first = f := Option.some.inj hf
      subst f
      exact howner
  · constructor
    · exact hfirst
    · exact h.unique
    · intro e he
      have := h.past e he
      change e.episode ≤ s.cursor.position + 1
      omega
    · intro f hf
      have hf' : first = f := Option.some.inj hf
      subst f
      exact howner

def process (s : State) (value : Bool) : State :=
  let window := recent (s.window ++ [value])
  let base := { s with
    window := window
    frames := ⟨s.cursor.position + 1, value, s.owner⟩ :: s.frames }
  if value then
    match s.cursor.first with
    | none => highStep base (s.cursor.position + 1) false
        (eligible s.owner (s.cursor.position + 1) (s.cursor.position + 1) window)
    | some first => highStep base first s.cursor.reported
        (eligible s.owner (s.cursor.position + 1) first window)
  else { base with cursor := ⟨s.cursor.position + 1, none, false⟩ }

theorem process_invariant (s : State) (h : Invariant s) (value : Bool) :
    Invariant (process s value) := by
  cases value with
  | false =>
    constructor
    · rfl
    · exact h.unique
    · intro e he
      have := h.past e he
      change e.episode ≤ s.cursor.position + 1
      omega
    · intro first hf
      cases hf
  | true =>
    simp only [process, ↓reduceIte]
    split
    · refine highStep_invariant _ ?_ _ _ _ ?_ ?_
      · exact ⟨h.valid, h.unique, h.past, h.ownership⟩
      · dsimp
        omega
      · have hfresh : s.cursor.position + 1 ∉ ids s := by
          intro hm
          obtain ⟨e, he, hid⟩ := List.mem_map.mp hm
          have hp := h.past e he
          omega
        simpa only [ids, Bool.false_eq_true, iff_false] using hfresh
    · rename_i first hf
      refine highStep_invariant _ ?_ _ _ _ ?_ ?_
      · exact ⟨h.valid, h.unique, h.past, h.ownership⟩
      · have hv := h.valid
        simp only [Cursor.Valid, hf] at hv
        dsimp
        omega
      · exact h.ownership first hf

@[simp] theorem process_position (s : State) (value : Bool) :
    (process s value).cursor.position = s.cursor.position + 1 := by
  cases value <;> simp [process, highStep] <;> split <;> rfl

@[simp] theorem process_owner (s : State) (value : Bool) :
    (process s value).owner = s.owner := by
  cases value <;> simp [process, highStep] <;> split <;> rfl

@[simp] theorem process_frames (s : State) (value : Bool) :
    (process s value).frames = ⟨s.cursor.position + 1, value, s.owner⟩ :: s.frames := by
  cases value <;> simp [process, highStep] <;> split <;> rfl

/-- Newest-first storage: old committed entries form an unchanged suffix. -/
def PreservesJournal (before after : State) : Prop :=
  ∃ added, after.events = added ++ before.events

theorem process_preserves_journal (s : State) (value : Bool) :
    PreservesJournal s (process s value) := by
  cases value <;> simp only [process, Bool.false_eq_true, ↓reduceIte]
  · exact ⟨[], rfl⟩
  · split <;> simp only [highStep, PreservesJournal]
    all_goals split <;> first | exact ⟨[], rfl⟩ | skip
    all_goals split
    all_goals first | exact ⟨[_], rfl⟩ | exact ⟨[], rfl⟩

structure Candidate where
  target : Version
  cursor : Cursor
  window : List Bool
  deriving DecidableEq, Repr

/-- Only the normalized live cursor and current window may cross a handover.
The concrete representation obligations are proved in Migration.lean. -/
def compatible (s : State) (c : Candidate) : Bool :=
  decide (c.cursor = s.cursor ∧ c.window = s.window)

def activate (s : State) (candidate : Option Candidate) : State :=
  match candidate with
  | none => s
  | some c => if compatible s c then
      { s with owner := c.target, cursor := c.cursor, window := c.window }
    else s

theorem rejected_unchanged (s : State) (c : Candidate) (h : compatible s c = false) :
    activate s (some c) = s := by simp [activate, h]

theorem accepted_installs_target (s : State) (c : Candidate)
    (h : compatible s c = true) : (activate s (some c)).owner = c.target := by
  simp [activate, h]

@[simp] theorem activate_cursor (s : State) (c : Option Candidate) :
    (activate s c).cursor = s.cursor := by
  cases c with
  | none => rfl
  | some c =>
    simp only [activate]
    split
    · rename_i h
      exact (of_decide_eq_true h).1
    · rfl

@[simp] theorem activate_frames (s : State) (c : Option Candidate) :
    (activate s c).frames = s.frames := by
  cases c <;> simp [activate] <;> split <;> rfl

@[simp] theorem activate_events (s : State) (c : Option Candidate) :
    (activate s c).events = s.events := by
  cases c <;> simp [activate] <;> split <;> rfl

theorem activate_invariant (s : State) (h : Invariant s) (c : Option Candidate) :
    Invariant (activate s c) := by
  constructor
  · simpa only [activate_cursor] using h.valid
  · simpa only [ids, activate_events] using h.unique
  · simpa only [activate_events, activate_cursor] using h.past
  · simpa only [activate_cursor, ids, activate_events] using h.ownership

/-- Candidate data is validated after processing the current input. -/
def tick (s : State) (input : Bool × Option Candidate) : State :=
  activate (process s input.1) input.2

theorem tick_invariant (s : State) (h : Invariant s) (input : Bool × Option Candidate) :
    Invariant (tick s input) := activate_invariant _ (process_invariant s h _) _

@[simp] theorem tick_position (s : State) (input : Bool × Option Candidate) :
    (tick s input).cursor.position = s.cursor.position + 1 := by simp [tick]

@[simp] theorem tick_frames (s : State) (input : Bool × Option Candidate) :
    (tick s input).frames = ⟨s.cursor.position + 1, input.1, s.owner⟩ :: s.frames := by
  simp [tick]

theorem tick_preserves_journal (s : State) (input : Bool × Option Candidate) :
    PreservesJournal s (tick s input) := by
  simpa only [PreservesJournal, tick, activate_events] using
    process_preserves_journal s input.1

def run (s : State) : List (Bool × Option Candidate) → State
  | [] => s
  | input :: rest => run (tick s input) rest

theorem run_invariant (s : State) (h : Invariant s)
    (inputs : List (Bool × Option Candidate)) : Invariant (run s inputs) := by
  induction inputs generalizing s with
  | nil => exact h
  | cons input rest ih => exact ih _ (tick_invariant s h input)

/-- Arbitrary length, binary values, and boundary candidates; not a bounded test. -/
theorem no_duplicate_episode_reports (inputs : List (Bool × Option Candidate)) :
    (ids (run initial inputs)).Nodup := (run_invariant _ initial_invariant inputs).unique

theorem run_position (s : State) (inputs : List (Bool × Option Candidate)) :
    (run s inputs).cursor.position = s.cursor.position + inputs.length := by
  induction inputs generalizing s with
  | nil => simp [run]
  | cons input rest ih => simp [run, ih, Nat.add_comm, Nat.add_left_comm]

theorem exact_input_values (s : State) (inputs : List (Bool × Option Candidate)) :
    (run s inputs).frames.map Frame.value =
      (inputs.map Prod.fst).reverse ++ s.frames.map Frame.value := by
  induction inputs generalizing s with
  | nil => simp [run]
  | cons input rest ih => simp [run, ih, List.reverse_cons, List.append_assoc]

/-- Exact contiguous indices imply neither omitted nor duplicated observations. -/
theorem exact_input_indices (s : State) (inputs : List (Bool × Option Candidate)) :
    (run s inputs).frames.map Frame.seq =
      (List.range' (s.cursor.position + 1) inputs.length).reverse ++
        s.frames.map Frame.seq := by
  induction inputs generalizing s with
  | nil => simp [run]
  | cons input rest ih => simp [run, ih, List.range'_succ, List.reverse_cons,
      List.append_assoc, Nat.add_assoc]

theorem run_preserves_journal (s : State) (inputs : List (Bool × Option Candidate)) :
    PreservesJournal s (run s inputs) := by
  induction inputs generalizing s with
  | nil => exact ⟨[], rfl⟩
  | cons input rest ih =>
    obtain ⟨a, ha⟩ := tick_preserves_journal s input
    obtain ⟨b, hb⟩ := ih (tick s input)
    exact ⟨b ++ a, by simpa only [run, ha, List.append_assoc] using hb⟩

/-- One concrete frame at the boundary belongs to the previous active version. -/
theorem boundary_owned_by_old (s : State) (value : Bool) (c : Option Candidate) :
    (tick s (value, c)).frames.head? = some ⟨s.cursor.position + 1, value, s.owner⟩ := by
  simp

/-- The first frame after an accepted handover belongs to the target. -/
theorem next_owned_by_target (s : State) (c : Candidate) (h : compatible s c = true)
    (value : Bool) (nextCandidate : Option Candidate) :
    (tick (activate s (some c)) (value, nextCandidate)).frames.head? =
      some ⟨s.cursor.position + 1, value, c.target⟩ := by
  simp [accepted_installs_target s c h]

theorem stale_candidate_rejected (s : State) (c : Candidate)
    (h : c.cursor.position < s.cursor.position) : activate s (some c) = s := by
  apply rejected_unchanged
  have hn : c.cursor ≠ s.cursor := by
    intro heq
    have hp := congrArg Cursor.position heq
    omega
  simp [compatible, hn]

theorem changed_report_flag_rejected (s : State) (c : Candidate)
    (h : c.cursor.reported ≠ s.cursor.reported) : activate s (some c) = s := by
  apply rejected_unchanged
  have hn : c.cursor ≠ s.cursor := fun heq => h (congrArg Cursor.reported heq)
  simp [compatible, hn]

/-- A qualifying unreported ongoing episode publishes its event in this tick,
including when the subsequent candidate is accepted, rejected, or absent. -/
theorem eligible_unreported_emits (s : State) (first : Nat) (c : Option Candidate)
    (hf : s.cursor.first = some first) (hu : s.cursor.reported = false)
    (he : eligible s.owner (s.cursor.position + 1) first
      (recent (s.window ++ [true])) = true) :
    (tick s (true, c)).events = ⟨first, s.cursor.position + 1, s.owner⟩ :: s.events := by
  simp [tick, process, hf, hu, he, highStep]

theorem no_duplicate_input_indices (inputs : List (Bool × Option Candidate)) :
    ((run initial inputs).frames.map Frame.seq).Nodup := by
  rw [exact_input_indices]
  simp only [initial, List.map_nil, List.append_nil, List.Nodup, List.pairwise_reverse]
  exact (List.nodup_range' (s := 1) (n := inputs.length)).imp (fun h => Ne.symm h)

/-- One theorem collecting the arbitrary-run observation and reporting claims. -/
theorem continuity_contract (inputs : List (Bool × Option Candidate)) :
    (run initial inputs).cursor.position = inputs.length ∧
    (run initial inputs).frames.map Frame.value = (inputs.map Prod.fst).reverse ∧
    (run initial inputs).frames.map Frame.seq = (List.range' 1 inputs.length).reverse ∧
    (ids (run initial inputs)).Nodup ∧ Invariant (run initial inputs) := by
  refine ⟨?_, ?_, ?_, no_duplicate_episode_reports inputs,
    run_invariant _ initial_invariant inputs⟩
  · simpa [initial] using run_position initial inputs
  · simpa [initial] using exact_input_values initial inputs
  · simpa [initial] using exact_input_indices initial inputs

end Firmboot.Continuity
