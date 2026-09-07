import Firmboot

-- Expected rejection: the unchecked reset repeats episode 1.
open Firmboot.Continuity Firmboot.Witnesses
example : (ids (process brokenReset true)).Nodup := by decide
