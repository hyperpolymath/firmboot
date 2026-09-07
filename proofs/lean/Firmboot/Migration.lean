import Std

/-!
Representation-level migration obligations for the two known detectors.
`Bool` excludes non-binary history and `Nat` excludes negative input positions.
This is a handwritten mathematical model, not verified Elixir extraction.
-/
namespace Firmboot

inductive Version where
  | v1 | v2
  deriving DecidableEq, Repr

structure Cursor where
  position : Nat
  first : Option Nat
  reported : Bool
  deriving DecidableEq, Repr

def Cursor.Valid (c : Cursor) : Prop :=
  match c.first with
  | none => c.reported = false
  | some first => 1 ≤ first ∧ first ≤ c.position

structure V1 where
  position : Nat
  first : Option Nat
  sent : Bool
  count : Nat
  deriving DecidableEq, Repr

structure Episode where
  first : Nat
  reported : Bool
  deriving DecidableEq, Repr

structure V2 where
  position : Nat
  episode : Option Episode
  window : List Bool
  deriving DecidableEq, Repr

def V1.cursor (s : V1) : Cursor := ⟨s.position, s.first, s.sent⟩

def V2.cursor (s : V2) : Cursor :=
  match s.episode with
  | none => ⟨s.position, none, false⟩
  | some e => ⟨s.position, some e.first, e.reported⟩

def V1.Valid (s : V1) : Prop :=
  s.cursor.Valid ∧ s.count = (match s.first with
    | none => 0
    | some first => s.position - first + 1)

def V2.Valid (s : V2) : Prop := s.cursor.Valid ∧ s.window.length ≤ 3

/-- Chronological history; retain the last three entries. -/
def recent (history : List Bool) : List Bool := history.drop (history.length - 3)

theorem recent_bounded (history : List Bool) : (recent history).length ≤ 3 := by
  simp only [recent, List.length_drop]
  omega

def migrate12 (old : V1) (history : List Bool) : V2 :=
  ⟨old.position, old.first.map (fun first => ⟨first, old.sent⟩), recent history⟩

def migrate21 (old : V2) : V1 :=
  match old.episode with
  | none => ⟨old.position, none, false, 0⟩
  | some e => ⟨old.position, some e.first, e.reported, old.position - e.first + 1⟩

/-- V1's absent episode must have a cleared report flag. -/
theorem migrate12_identity (old : V1) (history : List Bool) (h : old.Valid) :
    (migrate12 old history).cursor = old.cursor := by
  rcases old with ⟨position, first, sent, count⟩
  cases first with
  | none =>
    have hs : sent = false := h.1
    subst sent
    rfl
  | some first => rfl

theorem migrate21_identity (old : V2) : (migrate21 old).cursor = old.cursor := by
  rcases old with ⟨position, episode, window⟩
  cases episode <;> rfl

theorem migrate12_valid (old : V1) (history : List Bool) (h : old.Valid) :
    (migrate12 old history).Valid := by
  constructor
  · rw [migrate12_identity old history h]
    exact h.1
  · exact recent_bounded history

theorem migrate21_valid (old : V2) (h : old.Valid) : (migrate21 old).Valid := by
  constructor
  · rw [migrate21_identity]
    exact h.1
  · cases old with
    | mk position episode window => cases episode <;> rfl

/-- The V2 window is reconstructed from boundary history, not an old snapshot. -/
theorem migrate12_window (old : V1) (history : List Bool) :
    (migrate12 old history).window = recent history := rfl

theorem roundtrip_v1 (old : V1) (history : List Bool) (h : old.Valid) :
    migrate21 (migrate12 old history) = old := by
  rcases old with ⟨position, first, sent, count⟩
  cases first with
  | none =>
    have hs : sent = false := h.1
    have hc : count = 0 := h.2
    subst sent
    subst count
    rfl
  | some first =>
    have hc : count = position - first + 1 := h.2
    subst count
    rfl

theorem roundtrip_v2 (old : V2) (history : List Bool)
    (hw : old.window = recent history) : migrate12 (migrate21 old) history = old := by
  rcases old with ⟨position, episode, window⟩
  cases episode <;> simp_all [migrate12, migrate21]

end Firmboot
