# CommonCode staged migration plan

## Status and scope

- Status: planning/specification only
- Change scope: docs-only
- Sole implementation artifact for issue #48: `docs/architecture/commoncode-staged-migration-plan.md`
- Required completion action outside this diff: an explicit acceptance comment on issue #48 linking this document as the approved staged migration plan

This document defines migration order, stage dependencies, prerequisite seams, and stage stability rules needed to move from the current codebase shape to the already accepted target architecture. It does not reopen the accepted architecture baseline from issues #39 through #47, and it does not authorize code changes, file moves, package creation, refactors, dependency rewrites, branch choreography, or implementation PR batching.

## Alignment with accepted architecture baseline

| Accepted prerequisite | Governing reuse in this migration plan |
| --- | --- |
| Issue #39 / `docs/adr/0006-commoncode-layered-architecture-constitution.md` | Keeps the governing `Presentation -> Application Facade -> Domain` direction and keeps persistence and infrastructure concerns behind inward-facing seams. |
| Issue #40 / `docs/architecture/commoncode-target-module-package-map.md` | Limits long-term target homes to `apps/common_code_desktop`, `packages/common_code_domain`, `packages/common_code_application`, `packages/common_code_persistence`, `packages/common_code_observability`, `packages/host_in_memory`, and `packages/host_opencode`. |
| Issue #41 / `docs/architecture/commoncode-dependency-matrix-and-allowed-imports.md` | Keeps dependency direction and import-surface rules fixed during migration; this plan sequences work without redefining those rules. |
| Issue #42 / `docs/architecture/commoncode-application-facade-contract.md` | Keeps the Application Facade as the only stable presentation-facing boundary while lower seams are split and re-homed. |
| Issue #43 / `docs/architecture/commoncode-application-port-contract-set.md` | Keeps host gateway, session store, session observation, identity context, and observability / diagnostics as Application-owned contract concerns beneath the facade. |
| Issue #44 / `docs/adr/0007-opencode-host-adapter-boundary-and-mapping-rules.md` | Keeps OpenCode-specific runtime semantics behind `packages/host_opencode`; the local ADR status label is stale, but the accepted issue/artifact content remains authoritative for this plan. |
| Issue #45 / `docs/architecture/commoncode-persistence-model-and-adapter-contract.md` | Keeps durable continuity, snapshot translation, and persistence normalization behind the accepted persistence boundary. |
| Issue #46 / `docs/architecture/commoncode-observability-model-and-diagnostics-boundary.md` | Keeps observability contract ownership in Application and concrete observability support in `packages/common_code_observability`. |
| Issue #47 / `docs/architecture/commoncode-current-to-target-architecture-mapping.md` | Supplies the authoritative current-to-target seam mapping baseline used to sequence this plan; issue #48 does not re-derive target homes. |

Issue #48 introduces only migration-staging decisions: stage order, prerequisite seams, dependency relationships, pressure-point sequencing, and stability constraints. Target package ownership, dependency rules, facade shape, application ports, OpenCode boundary rules, persistence semantics, observability semantics, and seam-to-home mapping remain inherited from accepted issues #39 through #47.

## Migration planning principles and inherited constraints

1. Issue #47 is the authoritative migration starting point. This plan sequences the accepted mapping; it does not replace it.
2. Mixed seams must split before later re-home work when a single current seam blends responsibilities owned by multiple accepted target homes.
3. Presentation continues to depend on the Application Facade rather than on concrete persistence, host, or observability adapters while migration is in progress.
4. Application-owned ports remain the stable contract layer while persistence, host, and observability responsibilities are separated beneath them.
5. `apps/common_code_desktop` ends as presentation and app-edge composition only; desktop-local current placement does not redefine long-term ownership.
6. `packages/host_core` is transitional current-state context to be drained and retired after stable replacement responsibilities exist in accepted homes.
7. This artifact is normative about stage order and prerequisites, but deliberately non-normative about exact PR slicing, commit ordering, branch choreography, file-move commands, and concrete API design.

## Canonical stage model

| Stage concept | Meaning in this plan |
| --- | --- |
| `foundational prerequisite` | An earlier stage that must establish stable contracts or split mixed seams before later re-home work is safe. |
| `dependent follow-on stage` | A later stage that assumes the boundary and stability guarantees established by earlier stages. |
| `stability constraint during migration` | A rule that must remain true while a stage is in progress so migration work does not redefine accepted contracts or dependency direction. |
| `mixed seam that must split before later re-home work` | A current seam that blends responsibilities belonging to multiple accepted target homes and therefore cannot be migrated truthfully as one unit. |
| `transitional seam retired only after replacement responsibilities are stable` | A current seam or package that remains temporarily only until its accepted replacement responsibilities are stable in their final homes. |

Canonical stage order is fixed as `S1 -> S2 -> S3 -> S4 -> S5`.

## Canonical staged migration plan

### Stage `S1`

- `stage_id`: `S1`
- `stage_name`: `Stabilize presentation-to-application boundaries and split mixed orchestration seams`
- `objective`: Establish the earliest safe boundary work by using issue #47 as the sequencing baseline, preserving the facade boundary from issue #42, and defining split-before-rehome prerequisites for mixed seams.
- `depends_on`: `none`
- `migration_focus`: Stabilize Presentation-to-Application interaction, isolate Application-owned orchestration from desktop-owned controller/runtime/app-edge code, and make mixed seams explicit before persistence, host-adapter, or observability re-home work begins.
- `prerequisite_seams`: `apps/common_code_desktop/lib/src/desktop_session_controller.dart`; `apps/common_code_desktop/lib/src/desktop_session_runtime.dart`; `apps/common_code_desktop/lib/src/durable_local_host_service.dart`; `packages/host_core/lib/src/host_service.dart`
- `target_homes_or_boundaries`: `apps/common_code_desktop` as presentation/app-edge composition only; `packages/common_code_application` as the owner of reusable orchestration plus facade/port contracts from issues #42 and #43.
- `stability_requirements`: Presentation continues to depend on the Application Facade; Application-owned port contracts remain stable; dependency direction from issue #41 is not relaxed; no stage-1 work normalizes desktop-local or `host_core` placement as final ownership.
- `why_this_stage_precedes_later_work`: Later persistence, host, and observability moves would otherwise carry unstable mixed responsibilities into the wrong target homes. `desktop_session_runtime.dart`, `durable_local_host_service.dart`, and `host_service.dart` must first be understood and split as mixed seams rather than treated as single-unit moves.
- `explicitly_out_of_scope_for_stage`: Re-homing persistence adapters, draining `host_core`, moving observability code, defining exact APIs, or prescribing execution choreography.

### Stage `S2`

- `stage_id`: `S2`
- `stage_name`: `Re-home persistence-owned continuity, snapshot, and translation responsibilities`
- `objective`: Move persistence-owned responsibilities behind the accepted persistence boundary from issue #45 after S1 has made the contract seams and split points explicit.
- `depends_on`: `S1`
- `migration_focus`: Re-home snapshot store, snapshot codec, durable continuity persistence, and legacy-shape normalization behind the Application-owned session-store port and `packages/common_code_persistence`.
- `prerequisite_seams`: `apps/common_code_desktop/lib/src/desktop_session_snapshot_store.dart`; `apps/common_code_desktop/lib/src/desktop_session_snapshot_codec.dart`; persistence-owned portions of `apps/common_code_desktop/lib/src/durable_local_host_service.dart`
- `target_homes_or_boundaries`: `packages/common_code_persistence`; Application-owned `session store` contract from issue #43; persistence model and continuity rules from issue #45.
- `stability_requirements`: Restart and continuity semantics from issue #45 remain stable; persistence does not absorb host execution, presentation state, or observability ownership; dependency direction remains adapter-inward toward Application and Domain only.
- `why_this_stage_precedes_later_work`: Durable continuity is currently entangled with mixed desktop/runtime seams. Host-adapter draining and later retirement work depend on persistence-owned responsibilities first becoming stable behind their accepted boundary.
- `explicitly_out_of_scope_for_stage`: Host gateway re-home, session-observation adapter draining, observability re-home, final desktop retirement, or concrete storage-engine implementation details.

### Stage `S3`

- `stage_id`: `S3`
- `stage_name`: `Separate host gateway, session observation, and in-memory host adapter responsibilities while draining host_core`
- `objective`: Re-home host-related responsibilities only after S1 boundary splits and S2 persistence separation have removed blended continuity ownership from transitional seams.
- `depends_on`: `S1`, `S2`
- `migration_focus`: Separate host gateway and session observation concerns into Application-owned contracts, re-home in-memory host implementation responsibility toward `packages/host_in_memory`, and drain transitional `packages/host_core` ownership without turning `host_core` into a target home.
- `prerequisite_seams`: host-related portions of `apps/common_code_desktop/lib/src/durable_local_host_service.dart`; `packages/host_core/lib/src/host_service.dart`; `packages/host_core/lib/src/host_service_failure.dart`; `packages/host_core/lib/src/in_memory_host_service.dart`
- `target_homes_or_boundaries`: `packages/common_code_application` host gateway and session observation contracts; `packages/host_in_memory` for the in-memory adapter path; `packages/host_opencode` remains the only valid OpenCode-specific adapter home under issue #44.
- `stability_requirements`: OpenCode boundary integrity from issue #44 remains fixed; Application does not depend on concrete host adapters; `packages/host_core` remains transitional only; persistence responsibilities already stabilized in S2 do not flow back into host seams.
- `why_this_stage_precedes_later_work`: Observability re-home should follow stabilized adapter boundaries rather than current blended seams, and final retirement cannot happen while host gateway, observation, and bounded failure ownership still live in transitional `host_core` or desktop-local mixed seams.
- `explicitly_out_of_scope_for_stage`: Final observability package placement, retirement of all transitional seams, exact adapter APIs, or implementation-specific bootstrap/transport wiring.

### Stage `S4`

- `stage_id`: `S4`
- `stage_name`: `Re-home observability and diagnostics behind the accepted observability boundary`
- `objective`: Re-home diagnostics and observability responsibilities behind the Application-owned observability port and `packages/common_code_observability` after orchestration and adapter seams are stable enough to avoid moving blended runtime logic with them.
- `depends_on`: `S1`, `S2`, `S3`
- `migration_focus`: Separate concrete diagnostics sinks, diagnostic records, and observability helpers from desktop/runtime seams and align them with the issue #46 boundary.
- `prerequisite_seams`: observability-related portions of `apps/common_code_desktop/lib/src/durable_local_host_service.dart`; diagnostics threading in `apps/common_code_desktop/lib/src/desktop_session_runtime.dart`
- `target_homes_or_boundaries`: Application-owned observability / diagnostics port from issue #43; `packages/common_code_observability` as the concrete adapter home from issue #46.
- `stability_requirements`: Observability boundary integrity from issue #46 remains explicit; user-facing presentation signals stay facade-owned rather than becoming observability contracts; desktop-local diagnostics placement is treated as transitional only; dependency direction from issue #41 still applies.
- `why_this_stage_precedes_later_work`: Diagnostics must follow stabilized application and adapter seams, not current blended runtime files. Moving observability earlier would risk preserving desktop-local or host-mixed ownership assumptions that the accepted architecture rejects.
- `explicitly_out_of_scope_for_stage`: Final retirement choreography, exact logging/metrics/tracing implementations, or adapter/runtime code changes.

### Stage `S5`

- `stage_id`: `S5`
- `stage_name`: `Retire transitional seams and leave desktop as presentation/app-edge composition only`
- `objective`: Close the staged migration plan by defining retirement conditions for transitional seams once replacement responsibilities are stable in their accepted homes.
- `depends_on`: `S1`, `S2`, `S3`, `S4`
- `migration_focus`: Retire transitional ownership assumptions in desktop-local mixed seams and `packages/host_core`, leaving `apps/common_code_desktop` as presentation/app-edge composition only.
- `prerequisite_seams`: transitional remnants of `apps/common_code_desktop/lib/src/desktop_session_runtime.dart`; `apps/common_code_desktop/lib/src/durable_local_host_service.dart`; `packages/host_core/lib/src/host_service.dart`; `packages/host_core/lib/src/host_service_failure.dart`; `packages/host_core/lib/src/in_memory_host_service.dart`
- `target_homes_or_boundaries`: `apps/common_code_desktop` as final presentation/app-edge composition only; accepted target packages from issue #40 as the only long-term ownership homes; no canonical target home for `packages/host_core`.
- `stability_requirements`: Transitional seams retire only after replacement responsibilities are stable; desktop remains a client/composition host rather than a reusable architecture home; `host_core` is retired rather than normalized; accepted dependency, persistence, observability, and OpenCode boundaries remain unchanged.
- `why_this_stage_precedes_later_work`: Final retirement must happen last because it depends on prior responsibility re-home work already being stable. Otherwise desktop-local and `host_core` placement would continue to hide unresolved ownership ambiguity.
- `explicitly_out_of_scope_for_stage`: Exact PR sequence, branch choreography, file-deletion timing, or concrete refactor scripts.

## Pressure-point crosswalk

| current_seam | responsibility_cluster | first_migration_stage | depends_on | target_home_reference | notes |
| --- | --- | --- | --- | --- | --- |
| `apps/common_code_desktop/lib/src/desktop_session_controller.dart` | Presentation controller and facade-only command delegation boundary | `S1` | `Issue #47 mapping baseline` | `apps/common_code_desktop` constrained by the issue #42 Application Facade boundary | Keep controller ownership presentation-only; do not let it continue to own reusable orchestration while S1 stabilizes the facade boundary. |
| `apps/common_code_desktop/lib/src/desktop_session_runtime.dart` | Mixed runtime seam: desktop app-edge composition plus Application-owned bootstrap / refresh / watch orchestration | `S1` | `Issue #47 mapping baseline` | Split between `apps/common_code_desktop` app-edge composition and `packages/common_code_application` orchestration | This seam must split before persistence, host, or observability work proceeds, because later stages depend on stable orchestration boundaries rather than a blended runtime file. |
| `apps/common_code_desktop/lib/src/desktop_session_snapshot_store.dart` | Durable continuity store adapter | `S2` | `S1` | `packages/common_code_persistence` via the Application-owned session-store port | Re-home after S1 makes the store boundary explicit; do not keep durable continuity owned by desktop-local storage seams. |
| `apps/common_code_desktop/lib/src/desktop_session_snapshot_codec.dart` | Snapshot translation and storage-shape normalization | `S2` | `S1` | `packages/common_code_persistence` under issue #45 persistence rules | Storage translation belongs with persistence-owned continuity rather than desktop presentation. |
| `apps/common_code_desktop/lib/src/durable_local_host_service.dart` | Mixed bootstrap/orchestration split point | `S1` | `Issue #47 mapping baseline` | `packages/common_code_application` for reusable orchestration, with later adapter re-home to accepted homes | This seam cannot be migrated truthfully as one unit; S1 defines the split prerequisite that later stages consume. |
| `apps/common_code_desktop/lib/src/durable_local_host_service.dart` | Persistence-owned continuity, restore, and legacy-shape normalization | `S2` | `S1` | `packages/common_code_persistence` | Re-home only after the S1 split makes persistence-owned behavior separate from host execution and diagnostics. |
| `apps/common_code_desktop/lib/src/durable_local_host_service.dart` | In-memory host execution lifecycle and session observation implementation | `S3` | `S1`, `S2` | `packages/host_in_memory` plus Application-owned host gateway / session observation contracts | Drain host-runtime ownership after persistence is already separated so host concerns do not continue to carry continuity ownership. |
| `apps/common_code_desktop/lib/src/durable_local_host_service.dart` | Diagnostics emission and sink threading | `S4` | `S1`, `S2`, `S3` | `packages/common_code_observability` behind the Application-owned observability port | Observability follows stabilized application and host seams; desktop-local diagnostics are transitional only. |
| `packages/host_core/lib/src/host_service.dart` | Mixed transitional contract seam for host gateway, session observation, and continuity-adjacent restore behavior | `S1` | `Issue #47 mapping baseline` | Split into Application-owned ports in `packages/common_code_application`; no final target home in `packages/host_core` | This seam must split before `host_core` can be drained in S3; otherwise later re-home work would preserve a transitional aggregate contract. |
| `packages/host_core/lib/src/host_service_failure.dart` | Bounded contract-visible failure categories for host-facing operations | `S3` | `S1`, `S2` | `packages/common_code_application` bounded failure surface aligned with facade and port contracts | Adapter-specific runtime or storage failures remain adapter-local; only bounded contract-visible failure categories move with the Application-owned contract set. |
| `packages/host_core/lib/src/in_memory_host_service.dart` | In-memory host adapter implementation | `S3` | `S1`, `S2` | `packages/host_in_memory` | This seam is drained only after S1 and S2 remove mixed contract and persistence ownership from transitional host seams. |

## Stage stability constraints

- **During `S1`**: Presentation continues to call the Application Facade only; Application-owned port contracts remain the stable contract layer; issue #47 remains the authoritative mapping baseline; no mixed seam is treated as a single final ownership unit.
- **During `S2`**: Durable continuity semantics from issue #45 remain stable, including restart continuity and legacy-shape normalization expectations; persistence remains distinct from host execution, presentation state, and observability.
- **During `S3`**: Dependency direction from issue #41 remains intact; `packages/host_core` is treated as transitional current-state context only; OpenCode-specific semantics remain behind the issue #44 adapter boundary and do not leak upward.
- **During `S4`**: The Application-owned observability / diagnostics port remains the only stable orchestration-facing observability boundary; presentation-visible status or notifications are not redefined as raw observability contracts; desktop-local diagnostics wiring does not become long-term ownership.
- **During `S5`**: Transitional seams retire only after replacement responsibilities are stable in accepted homes; `apps/common_code_desktop` remains presentation and app-edge composition only; desktop-specific current placement never overrides accepted target ownership.

## Dependency notes and deferred work boundaries

- `S1` is the foundational prerequisite because boundary stabilization and mixed-seam splitting must happen before any truthful re-home work can occur.
- `S2` is a dependent follow-on stage because durable continuity responsibilities are currently entangled with runtime seams; later host retirement is unsafe until persistence ownership is stabilized.
- `S3` depends on `S1` and `S2` because host gateway, session observation, and in-memory host responsibilities should follow stable application contracts and separated persistence ownership, not current blended seams.
- `S4` depends on `S1`, `S2`, and `S3` because observability should follow stabilized orchestration and adapter boundaries rather than today’s desktop-local diagnostics placement.
- `S5` depends on all earlier stages because transitional seam retirement is valid only after replacement responsibilities are stable in accepted target homes.

This plan intentionally defers exact implementation choreography. Later slices must still decide exact PR batching, branch strategy, commit order, file-move mechanics, package creation steps, and concrete API/class/method signatures without reopening the normative stage ordering and dependency rules recorded here.

## Non-goals

This artifact does not:

- re-derive target homes already accepted in issues #40 and #47
- change the dependency rules from issue #41
- redefine the facade or application-port contract shapes from issues #42 and #43
- reinterpret the accepted OpenCode boundary from issue #44 because of the stale local ADR status label
- prescribe exact PR batches, branch choreography, commit ordering, or refactor scripts
- create implementation issues for every stage
- authorize code changes, file moves, package creation, import rewrites, or dependency rewrites

The separately required acceptance comment on issue #48 remains part of completion semantics, but it is outside this implementation diff.
