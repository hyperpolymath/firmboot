import Lean

open Lean Elab Command

/-- Audit all declarations owned by imported Firmboot modules, including private
declarations, plus any Firmboot declarations in the file running this command.
Use Lean's transitive axiom collector rather than inspecting source text. -/
elab "#audit_firmboot_axioms" : command => do
  let env ← getEnv
  let allowed : Array Name := #[``propext, ``Classical.choice, ``Quot.sound]
  let mut checked : Nat := 0
  for (name, _) in env.constants.toList do
    let owned := match env.getModuleIdxFor? name with
      | some index => Name.isPrefixOf `Firmboot env.header.moduleNames[index.toNat]!
      | none => Name.isPrefixOf `Firmboot name
    if owned then
      checked := checked + 1
      let axioms ← collectAxioms name
      for axiomName in axioms do
        unless allowed.contains axiomName do
          throwError "Firmboot axiom policy rejected {name}: unexpected axiom {axiomName}"
  if checked == 0 then
    throwError "Firmboot axiom policy found no declarations to check"
  logInfo m!"Firmboot axiom policy checked {checked} declarations"
