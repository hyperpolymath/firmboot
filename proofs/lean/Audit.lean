import Firmboot

/-- info: 'Firmboot.Supervision.begin_preserves_core' does not depend on any axioms -/
#guard_msgs in
#print axioms Firmboot.Supervision.begin_preserves_core

/-- info: 'Firmboot.Supervision.busy_unchanged' depends on axioms: [propext] -/
#guard_msgs in
#print axioms Firmboot.Supervision.busy_unchanged

/-- info: 'Firmboot.Supervision.begin_fresh' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms Firmboot.Supervision.begin_fresh

/-- info: 'Firmboot.Supervision.begin_valid' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms Firmboot.Supervision.begin_valid

/-- info: 'Firmboot.Supervision.step_position' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms Firmboot.Supervision.step_position

/-- info: 'Firmboot.Supervision.step_frames' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms Firmboot.Supervision.step_frames

/-- info: 'Firmboot.Supervision.step_invariant' depends on axioms: [propext, Classical.choice, Quot.sound] -/
#guard_msgs in
#print axioms Firmboot.Supervision.step_invariant

/-- info: 'Firmboot.Supervision.step_preserves_journal' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms Firmboot.Supervision.step_preserves_journal

/-- info: 'Firmboot.Supervision.step_pending_valid' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms Firmboot.Supervision.step_pending_valid

/-- info: 'Firmboot.Supervision.allowance_decreases' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms Firmboot.Supervision.allowance_decreases

/-- info: 'Firmboot.Supervision.waiting_keeps_active' depends on axioms: [propext] -/
#guard_msgs in
#print axioms Firmboot.Supervision.waiting_keeps_active

/-- info: 'Firmboot.Supervision.failure_keeps_active' depends on axioms: [propext] -/
#guard_msgs in
#print axioms Firmboot.Supervision.failure_keeps_active

/-- info: 'Firmboot.Supervision.matching_failure_retires' depends on axioms: [propext] -/
#guard_msgs in
#print axioms Firmboot.Supervision.matching_failure_retires

/-- info: 'Firmboot.Supervision.stale_success_is_waiting' depends on axioms: [propext] -/
#guard_msgs in
#print axioms Firmboot.Supervision.stale_success_is_waiting

/-- info: 'Firmboot.Supervision.stale_failure_is_waiting' depends on axioms: [propext] -/
#guard_msgs in
#print axioms Firmboot.Supervision.stale_failure_is_waiting

/-- info: 'Firmboot.Supervision.old_token_cannot_release_new_attempt' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms Firmboot.Supervision.old_token_cannot_release_new_attempt

/-- info: 'Firmboot.Supervision.wrong_target_keeps_active' depends on axioms: [propext] -/
#guard_msgs in
#print axioms Firmboot.Supervision.wrong_target_keeps_active

/-- info: 'Firmboot.Supervision.ready_compatible_activates' depends on axioms: [propext] -/
#guard_msgs in
#print axioms Firmboot.Supervision.ready_compatible_activates

/-- info: 'Firmboot.Supervision.run_invariant' depends on axioms: [propext, Classical.choice, Quot.sound] -/
#guard_msgs in
#print axioms Firmboot.Supervision.run_invariant

/-- info: 'Firmboot.Supervision.run_pending_valid' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms Firmboot.Supervision.run_pending_valid

/-- info: 'Firmboot.Supervision.run_allowance_bound' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms Firmboot.Supervision.run_allowance_bound

/-- info: 'Firmboot.Supervision.resolved_within_allowance' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms Firmboot.Supervision.resolved_within_allowance

/-- info: 'Firmboot.Supervision.run_position' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms Firmboot.Supervision.run_position

/-- info: 'Firmboot.Supervision.run_input_values' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms Firmboot.Supervision.run_input_values

/-- info: 'Firmboot.Supervision.run_input_indices' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms Firmboot.Supervision.run_input_indices

/-- info: 'Firmboot.Supervision.run_journal_preserved' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms Firmboot.Supervision.run_journal_preserved

/-- info: 'Firmboot.Supervision.hung_worker_expires_while_samples_continue' depends on axioms: [propext] -/
#guard_msgs in
#print axioms Firmboot.Supervision.hung_worker_expires_while_samples_continue

/-- info: 'Firmboot.Supervision.retired_token_cannot_release_successor' depends on axioms: [propext] -/
#guard_msgs in
#print axioms Firmboot.Supervision.retired_token_cannot_release_successor

/-- info: 'Firmboot.Timing.transition_deadline' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms Firmboot.Timing.transition_deadline

/-- info: 'Firmboot.Timing.target_deadline' does not depend on any axioms -/
#guard_msgs in
#print axioms Firmboot.Timing.target_deadline

/-- info: 'Firmboot.Timing.completion_before_next_arrival' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms Firmboot.Timing.completion_before_next_arrival

/-- info: 'Firmboot.Timing.decision_delay' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms Firmboot.Timing.decision_delay

/-- info: 'Firmboot.Timing.pause_exceeds_deadline' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms Firmboot.Timing.pause_exceeds_deadline

/-- info: 'Firmboot.Timing.overlapping_phases_can_miss' does not depend on any axioms -/
#guard_msgs in
#print axioms Firmboot.Timing.overlapping_phases_can_miss

/-- info: 'Firmboot.Witnesses.v1_migration_admitted' depends on axioms: [propext] -/
#guard_msgs in
#print axioms Firmboot.Witnesses.v1_migration_admitted

/-- info: 'Firmboot.Witnesses.v2_migration_admitted' depends on axioms: [propext] -/
#guard_msgs in
#print axioms Firmboot.Witnesses.v2_migration_admitted

/-- info: 'Firmboot.Witnesses.real_bidirectional_handover' does not depend on any axioms -/
#guard_msgs in
#print axioms Firmboot.Witnesses.real_bidirectional_handover

/-- info: 'Firmboot.Witnesses.target_algorithm_changes' does not depend on any axioms -/
#guard_msgs in
#print axioms Firmboot.Witnesses.target_algorithm_changes

/-- info: 'Firmboot.Witnesses.unchecked_reset_duplicates' does not depend on any axioms -/
#guard_msgs in
#print axioms Firmboot.Witnesses.unchecked_reset_duplicates

/-- info: 'Firmboot.Witnesses.guard_rejects_reset' does not depend on any axioms -/
#guard_msgs in
#print axioms Firmboot.Witnesses.guard_rejects_reset

/-- info: 'Firmboot.Witnesses.guard_rejects_stale' does not depend on any axioms -/
#guard_msgs in
#print axioms Firmboot.Witnesses.guard_rejects_stale

/-- info: 'Firmboot.Continuity.initial_invariant' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms Firmboot.Continuity.initial_invariant

/-- info: 'Firmboot.Continuity.highStep_invariant' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms Firmboot.Continuity.highStep_invariant

/-- info: 'Firmboot.Continuity.process_invariant' depends on axioms: [propext, Classical.choice, Quot.sound] -/
#guard_msgs in
#print axioms Firmboot.Continuity.process_invariant

/-- info: 'Firmboot.Continuity.process_position' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms Firmboot.Continuity.process_position

/-- info: 'Firmboot.Continuity.process_owner' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms Firmboot.Continuity.process_owner

/-- info: 'Firmboot.Continuity.process_frames' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms Firmboot.Continuity.process_frames

/-- info: 'Firmboot.Continuity.process_preserves_journal' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms Firmboot.Continuity.process_preserves_journal

/-- info: 'Firmboot.Continuity.rejected_unchanged' depends on axioms: [propext] -/
#guard_msgs in
#print axioms Firmboot.Continuity.rejected_unchanged

/-- info: 'Firmboot.Continuity.accepted_installs_target' depends on axioms: [propext] -/
#guard_msgs in
#print axioms Firmboot.Continuity.accepted_installs_target

/-- info: 'Firmboot.Continuity.activate_cursor' does not depend on any axioms -/
#guard_msgs in
#print axioms Firmboot.Continuity.activate_cursor

/-- info: 'Firmboot.Continuity.activate_frames' depends on axioms: [propext] -/
#guard_msgs in
#print axioms Firmboot.Continuity.activate_frames

/-- info: 'Firmboot.Continuity.activate_events' depends on axioms: [propext] -/
#guard_msgs in
#print axioms Firmboot.Continuity.activate_events

/-- info: 'Firmboot.Continuity.activate_invariant' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms Firmboot.Continuity.activate_invariant

/-- info: 'Firmboot.Continuity.tick_invariant' depends on axioms: [propext, Classical.choice, Quot.sound] -/
#guard_msgs in
#print axioms Firmboot.Continuity.tick_invariant

/-- info: 'Firmboot.Continuity.tick_position' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms Firmboot.Continuity.tick_position

/-- info: 'Firmboot.Continuity.tick_frames' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms Firmboot.Continuity.tick_frames

/-- info: 'Firmboot.Continuity.tick_preserves_journal' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms Firmboot.Continuity.tick_preserves_journal

/-- info: 'Firmboot.Continuity.run_invariant' depends on axioms: [propext, Classical.choice, Quot.sound] -/
#guard_msgs in
#print axioms Firmboot.Continuity.run_invariant

/-- info: 'Firmboot.Continuity.no_duplicate_episode_reports' depends on axioms: [propext, Classical.choice, Quot.sound] -/
#guard_msgs in
#print axioms Firmboot.Continuity.no_duplicate_episode_reports

/-- info: 'Firmboot.Continuity.run_position' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms Firmboot.Continuity.run_position

/-- info: 'Firmboot.Continuity.exact_input_values' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms Firmboot.Continuity.exact_input_values

/-- info: 'Firmboot.Continuity.exact_input_indices' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms Firmboot.Continuity.exact_input_indices

/-- info: 'Firmboot.Continuity.run_preserves_journal' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms Firmboot.Continuity.run_preserves_journal

/-- info: 'Firmboot.Continuity.boundary_owned_by_old' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms Firmboot.Continuity.boundary_owned_by_old

/-- info: 'Firmboot.Continuity.next_owned_by_target' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms Firmboot.Continuity.next_owned_by_target

/-- info: 'Firmboot.Continuity.stale_candidate_rejected' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms Firmboot.Continuity.stale_candidate_rejected

/-- info: 'Firmboot.Continuity.changed_report_flag_rejected' depends on axioms: [propext] -/
#guard_msgs in
#print axioms Firmboot.Continuity.changed_report_flag_rejected

/-- info: 'Firmboot.Continuity.eligible_unreported_emits' depends on axioms: [propext] -/
#guard_msgs in
#print axioms Firmboot.Continuity.eligible_unreported_emits

/-- info: 'Firmboot.Continuity.no_duplicate_input_indices' depends on axioms: [propext, Classical.choice, Quot.sound] -/
#guard_msgs in
#print axioms Firmboot.Continuity.no_duplicate_input_indices

/-- info: 'Firmboot.Continuity.continuity_contract' depends on axioms: [propext, Classical.choice, Quot.sound] -/
#guard_msgs in
#print axioms Firmboot.Continuity.continuity_contract

/-- info: 'Firmboot.recent_bounded' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms Firmboot.recent_bounded

/-- info: 'Firmboot.migrate12_identity' does not depend on any axioms -/
#guard_msgs in
#print axioms Firmboot.migrate12_identity

/-- info: 'Firmboot.migrate21_identity' does not depend on any axioms -/
#guard_msgs in
#print axioms Firmboot.migrate21_identity

/-- info: 'Firmboot.migrate12_valid' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms Firmboot.migrate12_valid

/-- info: 'Firmboot.migrate21_valid' does not depend on any axioms -/
#guard_msgs in
#print axioms Firmboot.migrate21_valid

/-- info: 'Firmboot.migrate12_window' does not depend on any axioms -/
#guard_msgs in
#print axioms Firmboot.migrate12_window

/-- info: 'Firmboot.roundtrip_v1' does not depend on any axioms -/
#guard_msgs in
#print axioms Firmboot.roundtrip_v1

/-- info: 'Firmboot.roundtrip_v2' depends on axioms: [propext] -/
#guard_msgs in
#print axioms Firmboot.roundtrip_v2
