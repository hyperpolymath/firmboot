import Firmboot

-- Expected rejection: admission for separate phases does not cover their sum.
open Firmboot.Timing
def b : Budget := ⟨1, 2, 3, 2, 2, 5, 10⟩
example : b.capture + b.current + b.prepare + b.commit ≤ b.deadline := by decide
