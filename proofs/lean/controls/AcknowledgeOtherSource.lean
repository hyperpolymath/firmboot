import Firmboot.WaterLeak

open Firmboot.WaterLeak
-- Expected rejection: the same episode number on another source is not this warning.
example : outstanding (acknowledge warned ⟨8, 3⟩ 42) ⟨7, 3⟩ = false := by decide
