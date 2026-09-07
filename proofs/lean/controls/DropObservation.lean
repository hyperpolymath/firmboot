import Firmboot

-- Expected rejection: losing the new record violates the contiguous input claim.
open Firmboot.Continuity
def lost : State := { tick initial (true, none) with frames := [] }
example : lost.frames.map Frame.seq = [1] := by decide
