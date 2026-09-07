import Firmboot.Continuity

/-!
A controller which consumes one input on every step, including when preparation
has not completed or has failed. Waiting covers preparation/history deferral.
A finite allowance bounds an attempt's lifetime in continuing source ticks.
The Elixir worker, mailbox, wall timer and retirement acknowledgement are not
formally extracted here; this is their intended abstract tick contract.
-/
namespace Firmboot.Supervision
open Continuity

structure Attempt where
  token : Nat
  target : Version
  remaining : Nat
  deriving DecidableEq, Repr

structure Controller where
  core : State
  pending : Option Attempt
  nextToken : Nat
  deriving DecidableEq, Repr

inductive Reply where
  | waiting
  | ready (token : Nat) (candidate : Candidate)
  | failed (token : Nat)
  deriving DecidableEq, Repr

def initial : Controller := ⟨Continuity.initial, none, 0⟩

def beginAttempt (s : Controller) (target : Version) (allowance : Nat) : Controller :=
  match s.pending with
  | some _ => s
  | none => if allowance = 0 then s else
      { s with
        pending := some ⟨s.nextToken, target, allowance⟩
        nextToken := s.nextToken + 1 }

def matchesAttempt (a : Attempt) : Reply → Bool
  | .waiting => false
  | .ready token _ => decide (token = a.token)
  | .failed token => decide (token = a.token)

def candidate (s : Controller) (reply : Reply) : Option Candidate :=
  match s.pending, reply with
  | some a, .ready token c =>
    if 0 < a.remaining ∧ token = a.token ∧ c.target = a.target then some c else none
  | _, _ => none

def settle (pending : Option Attempt) (reply : Reply) : Option Attempt :=
  match pending with
  | none => none
  | some a => if matchesAttempt a reply ∨ a.remaining ≤ 1 then none
      else some { a with remaining := a.remaining - 1 }

def step (s : Controller) (input : Bool × Reply) : Controller :=
  { s with
    core := tick s.core (input.1, candidate s input.2)
    pending := settle s.pending input.2 }

def run (s : Controller) : List (Bool × Reply) → Controller
  | [] => s
  | input :: rest => run (step s input) rest

def remaining (s : Controller) : Nat :=
  match s.pending with | none => 0 | some a => a.remaining

def PendingValid (s : Controller) : Prop :=
  ∀ a, s.pending = some a → 0 < a.remaining

@[simp] theorem begin_preserves_core (s : Controller) (target : Version) (allowance : Nat) :
    (beginAttempt s target allowance).core = s.core := by
  simp only [beginAttempt]
  split
  · rfl
  · split <;> rfl

theorem busy_unchanged (s : Controller) (a : Attempt) (hp : s.pending = some a)
    (target : Version) (allowance : Nat) : beginAttempt s target allowance = s := by
  simp [beginAttempt, hp]

theorem begin_fresh (s : Controller) (target : Version) (allowance : Nat)
    (hp : s.pending = none) (ha : 0 < allowance) :
    (beginAttempt s target allowance).pending = some ⟨s.nextToken, target, allowance⟩ ∧
    (beginAttempt s target allowance).nextToken = s.nextToken + 1 := by
  have hn : allowance ≠ 0 := by omega
  simp [beginAttempt, hp, hn]

theorem begin_valid (s : Controller) (h : PendingValid s)
    (target : Version) (allowance : Nat) : PendingValid (beginAttempt s target allowance) := by
  simp only [beginAttempt]
  split
  · exact h
  · split
    · exact h
    · rename_i hn
      intro a ha
      have heq : (⟨s.nextToken, target, allowance⟩ : Attempt) = a := Option.some.inj ha
      subst a
      change 0 < allowance
      omega

@[simp] theorem step_position (s : Controller) (input : Bool × Reply) :
    (step s input).core.cursor.position = s.core.cursor.position + 1 := by simp [step]

@[simp] theorem step_frames (s : Controller) (input : Bool × Reply) :
    (step s input).core.frames = ⟨s.core.cursor.position + 1, input.1, s.core.owner⟩ ::
      s.core.frames := by simp [step]

theorem step_invariant (s : Controller) (h : Invariant s.core) (input : Bool × Reply) :
    Invariant (step s input).core := tick_invariant _ h _

theorem step_preserves_journal (s : Controller) (input : Bool × Reply) :
    PreservesJournal s.core (step s input).core := tick_preserves_journal _ _

/-- Pending attempts always have a positive allowance after a controller step. -/
theorem step_pending_valid (s : Controller) (input : Bool × Reply) :
    PendingValid (step s input) := by
  unfold PendingValid step settle
  split
  · intro a ha
    cases ha
  · split
    · intro a ha
      cases ha
    · rename_i a ha hn
      intro b hb
      have heq : { a with remaining := a.remaining - 1 } = b := Option.some.inj hb
      subst b
      simp only [not_or] at hn
      change 0 < a.remaining - 1
      omega

/-- Every input consumes allowance, even if no useful worker response arrives. -/
theorem allowance_decreases (s : Controller) (input : Bool × Reply) :
    remaining (step s input) ≤ remaining s - 1 := by
  cases hp : s.pending with
  | none => simp [remaining, step, settle, hp]
  | some a =>
    by_cases hm : matchesAttempt a input.2 ∨ a.remaining ≤ 1
    all_goals simp [remaining, step, settle, hp, hm]

theorem waiting_keeps_active (s : Controller) (value : Bool) :
    (step s (value, .waiting)).core = process s.core value := by
  cases hp : s.pending <;> simp [step, candidate, hp, tick, activate]

theorem failure_keeps_active (s : Controller) (value : Bool) (token : Nat) :
    (step s (value, .failed token)).core = process s.core value := by
  cases hp : s.pending <;> simp [step, candidate, hp, tick, activate]

theorem matching_failure_retires (s : Controller) (a : Attempt) (hp : s.pending = some a)
    (value : Bool) : (step s (value, .failed a.token)).pending = none := by
  simp [step, settle, hp, matchesAttempt]

/-- A stale success is observationally identical to waiting, including countdown. -/
theorem stale_success_is_waiting (s : Controller) (a : Attempt) (hp : s.pending = some a)
    (token : Nat) (hn : token ≠ a.token) (c : Candidate) (value : Bool) :
    step s (value, .ready token c) = step s (value, .waiting) := by
  simp [step, candidate, settle, matchesAttempt, hp, hn]

theorem stale_failure_is_waiting (s : Controller) (a : Attempt) (hp : s.pending = some a)
    (token : Nat) (hn : token ≠ a.token) (value : Bool) :
    step s (value, .failed token) = step s (value, .waiting) := by
  simp [step, candidate, settle, matchesAttempt, hp, hn]

theorem old_token_cannot_release_new_attempt (s : Controller) (target : Version)
    (allowance token : Nat) (hp : s.pending = none) (ha : 0 < allowance)
    (ht : token < s.nextToken) (c : Candidate) (value : Bool) :
    step (beginAttempt s target allowance) (value, .ready token c) =
      step (beginAttempt s target allowance) (value, .waiting) := by
  have hf := (begin_fresh s target allowance hp ha).1
  apply stale_success_is_waiting _ _ hf token _ c value
  change token ≠ s.nextToken
  omega

theorem wrong_target_keeps_active (s : Controller) (a : Attempt) (hp : s.pending = some a)
    (c : Candidate) (ht : c.target ≠ a.target) (value : Bool) :
    (step s (value, .ready a.token c)).core = process s.core value := by
  simp [step, candidate, hp, ht, tick, activate]

theorem ready_compatible_activates (s : Controller) (a : Attempt)
    (hp : s.pending = some a) (ha : 0 < a.remaining) (value : Bool) (c : Candidate)
    (ht : c.target = a.target) (hc : compatible (process s.core value) c = true) :
    (step s (value, .ready a.token c)).core.owner = a.target ∧
    (step s (value, .ready a.token c)).pending = none := by
  constructor
  · simpa [step, candidate, hp, ha, ht, tick] using
      accepted_installs_target (process s.core value) c hc
  · simp [step, settle, hp, matchesAttempt]

theorem run_invariant (s : Controller) (h : Invariant s.core) (inputs : List (Bool × Reply)) :
    Invariant (run s inputs).core := by
  induction inputs generalizing s with
  | nil => exact h
  | cons input rest ih => exact ih _ (step_invariant s h input)

theorem run_pending_valid (s : Controller) (h : PendingValid s) (inputs : List (Bool × Reply)) :
    PendingValid (run s inputs) := by
  induction inputs generalizing s with
  | nil => exact h
  | cons input rest ih => exact ih _ (step_pending_valid s input)

theorem run_allowance_bound (s : Controller) (inputs : List (Bool × Reply)) :
    remaining (run s inputs) ≤ remaining s - inputs.length := by
  induction inputs generalizing s with
  | nil => simp [run]
  | cons input rest ih =>
    have hr := ih (step s input)
    have hd := allowance_decreases s input
    simp only [run, List.length_cons]
    omega

/-- Bounded resolution, NOT guaranteed activation: rejection/timeout is allowed.
No new requests are inserted into this run, and source ticks must keep arriving. -/
theorem resolved_within_allowance (s : Controller) (h : PendingValid s)
    (inputs : List (Bool × Reply)) (hl : remaining s ≤ inputs.length) :
    (run s inputs).pending = none := by
  have hb := run_allowance_bound s inputs
  have hv := run_pending_valid s h inputs
  have hz : remaining (run s inputs) = 0 := by omega
  cases hp : (run s inputs).pending with
  | none => rfl
  | some a =>
    have ha := hv a hp
    have hz' : a.remaining = 0 := by simpa only [remaining, hp] using hz
    omega

theorem run_position (s : Controller) (inputs : List (Bool × Reply)) :
    (run s inputs).core.cursor.position = s.core.cursor.position + inputs.length := by
  induction inputs generalizing s with
  | nil => simp [run]
  | cons input rest ih => simp [run, ih, Nat.add_comm, Nat.add_left_comm]

theorem run_input_values (s : Controller) (inputs : List (Bool × Reply)) :
    (run s inputs).core.frames.map Frame.value =
      (inputs.map Prod.fst).reverse ++ s.core.frames.map Frame.value := by
  induction inputs generalizing s with
  | nil => simp [run]
  | cons input rest ih => simp [run, ih, List.reverse_cons, List.append_assoc]

theorem run_input_indices (s : Controller) (inputs : List (Bool × Reply)) :
    (run s inputs).core.frames.map Frame.seq =
      (List.range' (s.core.cursor.position + 1) inputs.length).reverse ++
        s.core.frames.map Frame.seq := by
  induction inputs generalizing s with
  | nil => simp [run]
  | cons input rest ih => simp [run, ih, List.range'_succ, List.reverse_cons,
      List.append_assoc, Nat.add_assoc]

theorem run_journal_preserved (s : Controller) (inputs : List (Bool × Reply)) :
    PreservesJournal s.core (run s inputs).core := by
  induction inputs generalizing s with
  | nil => exact ⟨[], rfl⟩
  | cons input rest ih =>
    obtain ⟨a, ha⟩ := step_preserves_journal s input
    obtain ⟨b, hb⟩ := ih (step s input)
    exact ⟨b ++ a, by simpa only [run, ha, List.append_assoc] using hb⟩

def hungExample : Controller := beginAttempt initial .v2 3

theorem hung_worker_expires_while_samples_continue :
    let result := run hungExample [(true, .waiting), (true, .waiting), (true, .waiting)]
    result.pending = none ∧ result.core.cursor.position = 3 ∧
    result.core.owner = .v1 ∧ ids result.core = [1] := by decide

theorem retired_token_cannot_release_successor :
    let exhausted := run hungExample [(false, .waiting), (false, .waiting), (false, .waiting)]
    let successor := beginAttempt exhausted .v2 3
    let c : Candidate := ⟨.v2, (process successor.core false).cursor,
      (process successor.core false).window⟩
    (step successor (false, .ready 0 c)).core.owner = .v1 ∧
    (step successor (false, .ready 0 c)).pending = some ⟨1, .v2, 2⟩ := by decide

end Firmboot.Supervision
