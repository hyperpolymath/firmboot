import Firmboot
import AuditPolicy

-- A new, otherwise unused assumption must fail the audit even when it does not
-- occur in any of the named theorem expectations in Audit.lean.
axiom Firmboot.unjustifiedContinuity : False

#audit_firmboot_axioms
