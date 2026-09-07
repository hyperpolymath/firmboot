import Firmboot

-- Expected rejection: waiting synchronously for preparation stops input progress.
open Firmboot.Supervision
def blockingStep (s : Controller) (input : Bool × Reply) : Controller :=
  if s.pending.isSome then s else step s input
example : (blockingStep hungExample (true, .waiting)).core.cursor.position = 1 := by decide
