# Continuity, identity and the services worth preserving

Firmboot studies how running software can change while preserving explicit
obligations. The ambition is dependable change: maintain what people and their
environment rely on, make the costs visible, and retain the authority to refuse
an update, reduce activity or stop safely.

## Its place in the research programme

The [Hyperpolymath profile](https://github.com/hyperpolymath/hyperpolymath)
organises the wider work around identity through structure-preserving
transformation. The [language coordinator](https://github.com/hyperpolymath/nextgen-languages)
indexes different instances of that question. Firmboot develops its temporal
aspect in software transition contracts.

- **Synchronic coherence:** at a given boundary, the active representation,
  current-state evidence, retained history and recorded output authority must
  agree. An old certificate cannot simply stand in for evidence about now.
- **Diachronic continuity:** across a change, observations retain their order,
  already committed events retain their meaning, and responsibility passes under
  an explicit migration contract. The new implementation may make different
  future decisions without rewriting what the earlier one already committed.

These are scoped criteria for continuing a software service. They are not a
complete theory of personal identity, an assertion that all versions behave
identically, or a proof of physical immortality. The model deliberately changes
the detector's future behaviour while preserving specified commitments.

[Epistemic types](https://github.com/hyperpolymath/epistemic-types) contribute
explicit meaning and current-state evidence; the
[Echo work](https://github.com/hyperpolymath/echo-types) motivates asking whether
retained information is sufficient for a particular later use. The Agda contract
uses the repaired epistemic library's retention and migration definitions.
Connections to resource budgeting in
[Eclexia](https://github.com/hyperpolymath/eclexia) and graded loss in
[Haec](https://github.com/hyperpolymath/haec) are research relationships, not
implemented integrations or inherited guarantees.

## Ecological and public-service directions

These are proposed applications, not deployed Firmboot capabilities. Each needs
its own domain model and evidence beyond the current binary-detector experiment.

| Direction | Continuity worth protecting | Additional obligation to establish |
|---|---|---|
| Clean-water and wastewater monitoring | Measurement provenance, an ongoing incident's identity, operator alarms and handover records during an analyser update | Valid sensor interpretation, treatment-specific safety constraints and independently justified control decisions |
| Leak detection and water conservation | An unresolved leak should not disappear or be reported as a new incident merely because the detector changes | Detection quality, water and energy accounting, sensor failures and authority for any automatic shut-off |
| Dam, reservoir and river observation | Preserve readings and warning history while revising an analysis method | Geotechnical/hydrological interpretation, communication outages and independent protective systems; continuity alone proves no dam safe |
| Wetland, reef, forest and wildlife observatories | Preserve provenance and avoid update-induced blind intervals in an infrequent-event record | Battery budgets, duty cycling, calibration, sampling adequacy and honest records of actual gaps |
| Distributed environmental IoT | Devices may sleep or be replaced while the agreed observation service remains accountable | Explicit coverage requirements, bounded communication costs, device identity and permitted periods without observation |

The motivation has an established practical basis: EPA describes leak detection
and monitoring as tools for [reducing water waste](https://www.epa.gov/watersense/leak-detection-and-flow-monitoring-devices),
and treats [energy efficiency in water utilities](https://www.epa.gov/sustainable-water-infrastructure/energy-efficiency-water-utilities)
as a distinct objective. USGS documents the public uses and quality assurance of
[streamflow monitoring](https://www.usgs.gov/programs/groundwater-and-streamflow-information-program/streamflow-monitoring).
Those sources motivate the domains; they provide no validation of Firmboot.

A useful first domain study would be **continuity of a water-leak warning
episode**, using recorded or simulated inputs. It maps directly to the existing
experiment's history and no-duplicate-report questions. Establish the observation
contract and detection-quality limits before considering any physical control.

## Continuity must include limits and stopping

A future ecological contract should state resource ceilings, observation needs,
permitted degradation, shutdown authority and what evidence survives a stop.
An update that exceeds an energy budget, erases an alarm or disables a protective
stop should fail that contract. Scheduled sleep, component replacement and an
orderly shutdown can all be correct behaviour under the service's requirements.

The present proofs concern specified transition invariants and assigned costs.
They do not establish energy savings, carbon reductions, environmental justice,
or the safety of autonomous actuation. Those require measurements, domain review
and additional formal obligations. The ability to stop safely is a design
requirement here, not a verified emergency-stop implementation.

## Everyday continuity: keep a person's work intact

Desktop users encounter the same issue at a different scale: an update interrupts
a document, a call, an accessibility setup or a long-running task. A useful
Firmboot direction is updating an application component while preserving a
well-defined session contract: work already saved, pending operations, consent,
document identity and recoverable state.

Existing systems already address parts of this problem. Microsoft's
[Restart Manager](https://learn.microsoft.com/en-us/windows/win32/rstmgr/about-restart-manager)
reduces update-related reboots by coordinating affected applications and
services. Firmboot's research question concerns the evidence needed to preserve
application obligations through such changes. It does not currently patch
Windows, remove the need for every kernel or firmware restart, or justify
postponing security updates indefinitely.

The shared objective is to let necessary change happen with less loss of work,
less avoidable disruption and explicit limits on the resources it consumes.
