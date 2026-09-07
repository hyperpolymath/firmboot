import Firmboot.WaterLeak

open Firmboot.WaterLeak
-- Expected rejection: updating the detector cannot acknowledge its warning.
example : outstanding (handover warned (some upgrade)) ⟨7, 3⟩ = false := by decide
