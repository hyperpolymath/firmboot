import Firmboot

-- Expected rejection: a retired attempt cannot authorize its successor.
open Firmboot Firmboot.Continuity Firmboot.Supervision
def expired : Controller := Supervision.run hungExample
  [(false, .waiting), (false, .waiting), (false, .waiting)]
def successor : Controller := beginAttempt expired .v2 3
def oldReply : Candidate := ⟨.v2, (process successor.core false).cursor,
  (process successor.core false).window⟩
example : (step successor (false, .ready 0 oldReply)).core.owner = .v2 := by decide
