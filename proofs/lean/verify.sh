#!/usr/bin/env bash
# Full proof build, pinned transitive axiom audit, and expected-failure controls.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

lake --no-cache --wfail build
lake env lean Audit.lean

# Enumerate the complete proof source directory, so an unimported new module
# cannot bypass compilation or the transitive axiom policy. Reject unsupported
# paths before turning filenames into Lean import commands.
module_list="$(rg --files Firmboot -g '*.lean' | sort)"
[[ -n "$module_list" ]] || { printf 'FAIL: no Firmboot proof modules\n' >&2; exit 1; }
audit_file=.lake/AllModulesAudit.lean
printf 'import AuditPolicy\nimport Firmboot\n' > "$audit_file"
while IFS= read -r proof_path; do
  if [[ ! "$proof_path" =~ ^Firmboot(/[A-Za-z_][A-Za-z_0-9]*)+\.lean$ ]]; then
    printf 'FAIL: unsupported proof module path: %s\n' "$proof_path" >&2
    exit 1
  fi
  proof_module="${proof_path%.lean}"
  proof_module="${proof_module//\//.}"
  lake --no-cache --wfail build "$proof_module"
  printf 'import %s\n' "$proof_module" >> "$audit_file"
done <<< "$module_list"
printf '\n#audit_firmboot_axioms\n' >> "$audit_file"
audit_output="$(lake env lean "$audit_file" 2>&1)" || {
  printf '%s\n' "$audit_output" >&2
  exit 1
}
printf '%s\n' "$audit_output"
if rg -q 'warning:' <<< "$audit_output"; then
  printf 'FAIL: warning in the all-module axiom audit\n' >&2
  exit 1
fi

axiom_status=0
axiom_output="$(lake env lean controls/ExtraAxiom.lean 2>&1)" || axiom_status=$?
if [[ "$axiom_status" -ne 1 ]] ||
    ! rg -Fq 'unexpected axiom Firmboot.unjustifiedContinuity' <<< "$axiom_output" ||
    [[ "$(rg -c 'error:' <<< "$axiom_output")" != 1 ]] ||
    rg -q 'warning:' <<< "$axiom_output"; then
  printf 'FAIL: unexpected axiom control result (exit %s)\n%s\n' \
    "$axiom_status" "$axiom_output" >&2
  exit 1
fi
printf 'PASS: the axiom policy rejected an additional custom assumption\n'

for control in ResetOwnership DropObservation OverlapPhases StaleReply BlockingPreparation ClearWarningOnUpdate AcknowledgeOtherSource; do
  control_status=0
  control_output="$(lake env lean "controls/${control}.lean" 2>&1)" || control_status=$?
  if [[ "$control_status" -ne 1 ]] ||
      ! rg -Fq 'error: Tactic `decide` proved that the proposition' <<< "$control_output" ||
      ! rg -xq 'is false' <<< "$control_output" ||
      [[ "$(rg -c 'error:' <<< "$control_output")" != 1 ]] ||
      rg -q 'warning:' <<< "$control_output"; then
    printf 'FAIL: unexpected result for %s (exit %s)\n%s\n' \
      "$control" "$control_status" "$control_output" >&2
    exit 1
  fi
  printf 'PASS: Lean rejected the false %s claim\n' "$control"
done

printf 'PASS: proof build, both axiom audits, custom-axiom control and seven false-claim controls\n'
