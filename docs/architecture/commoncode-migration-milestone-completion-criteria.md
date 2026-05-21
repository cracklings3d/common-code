# CommonCode migration milestone completion criteria

## Status and scope

- Status: planning/specification only
- Change scope: docs-only
- Sole canonical artifact for issue #49: `docs/architecture/commoncode-migration-milestone-completion-criteria.md`
- Required completion action outside this diff: an explicit acceptance comment on issue #49 linking this document as the approved milestone artifact

This document defines how completion of the accepted staged migration plan is judged. It defines milestone completion checkpoints for the stage model accepted in issue #48. It does not reopen architecture decisions from issues #39 through #48, redefine stage order or dependencies, authorize migration execution, or prescribe implementation slicing, PR batching, branch choreography, or release planning.

## Alignment with accepted architecture and migration baseline

This artifact is a consequence of accepted issues #39 through #48 and does not replace them.

| Accepted prerequisite | Governing reuse in this milestone document |
| --- | --- |
| Issue #39 / `docs/adr/0006-commoncode-layered-architecture-constitution.md` | Keeps the governing `Presentation -> Application Facade -> Domain` direction and the adapter/infrastructure posture the milestones must preserve. |
| Issue #40 / `docs/architecture/commoncode-target-module-package-map.md` | Keeps the accepted target homes fixed while milestones judge whether responsibility ownership has been structurally re-homed. |
| Issue #41 / `docs/architecture/commoncode-dependency-matrix-and-allowed-imports.md` | Keeps dependency direction and import-surface rules fixed while milestones judge completion. |
| Issue #42 / `docs/architecture/commoncode-application-facade-contract.md` | Keeps the Application Facade as the only stable presentation-facing boundary. |
| Issue #43 / `docs/architecture/commoncode-application-port-contract-set.md` | Keeps host gateway, session store, session observation, identity context, and observability / diagnostics as Application-owned contract concerns. |
| Issue #44 / `docs/adr/0007-opencode-host-adapter-boundary-and-mapping-rules.md` | Keeps the accepted OpenCode host-adapter boundary fixed. The local ADR status label may be stale, but accepted issue/artifact content remains authoritative for this document. |
| Issue #45 / `docs/architecture/commoncode-persistence-model-and-adapter-contract.md` | Keeps persistence-owned continuity, snapshot translation, and normalization semantics fixed. |
| Issue #46 / `docs/architecture/commoncode-observability-model-and-diagnostics-boundary.md` | Keeps the observability / diagnostics boundary fixed behind Application-owned contracts and observability adapters. |
| Issue #47 / `docs/architecture/commoncode-current-to-target-architecture-mapping.md` | Keeps the current-to-target seam mapping baseline fixed so milestone completion can be judged against accepted target homes rather than re-derived. |
| Issue #48 / `docs/architecture/commoncode-staged-migration-plan.md` | Supplies the authoritative milestone backbone, accepted stage order, and accepted stage dependency structure used by this document. |

Milestone completion criteria are acceptance checkpoints for the migration plan, not the migration plan itself. Milestone acceptance does not mean all related implementation work is done forever; it means the accepted structural outcome has been achieved and evidenced. Implementation slicing, refactor batching, branch choreography, and release planning remain separate concerns outside issue #49.

## Canonical milestone backbone and traceability

Issue #48 is the authoritative milestone backbone. The canonical milestone set in this document is derived directly from accepted stages `S1` through `S5` without changing order or dependencies.

| milestone_id | source_stage_ids | milestone_name | depends_on | structural_outcome_proved | enables_after_acceptance |
| --- | --- | --- | --- | --- | --- |
| `M1` | `S1` | Stabilized presentation-to-application boundary milestone | `none` | Mixed desktop/runtime orchestration seams no longer define the presentation boundary, and reusable orchestration is structurally separated from desktop-owned presentation/app-edge concerns. | Later persistence re-home work may rely on stable presentation-to-application boundaries and explicit mixed-seam split points. |
| `M2` | `S2` | Persistence boundary stabilization milestone | `M1` | Continuity, snapshot, and translation responsibilities are structurally owned by the accepted persistence boundary rather than desktop-local seams. | Later host-adapter draining work may rely on persistence-owned continuity no longer being blended into transitional host/runtime seams. |
| `M3` | `S3` | Host gateway and in-memory host separation milestone | `M1`, `M2` | Host gateway, session observation, and in-memory host responsibilities are structurally separated from transitional `host_core` ownership and aligned with accepted Application and host-adapter boundaries. | Later observability re-home and final seam retirement may rely on stable host/application separation and a drained transitional `host_core` ownership model. |
| `M4` | `S4` | Observability boundary stabilization milestone | `M1`, `M2`, `M3` | Diagnostics and observability responsibilities are structurally behind the accepted observability boundary instead of desktop runtime seams. | Final seam retirement work may rely on observability ownership no longer being blended into desktop/runtime or host-transition seams. |
| `M5` | `S5` | Transitional seam retirement milestone | `M1`, `M2`, `M3`, `M4` | Transitional seams are retired and `apps/common_code_desktop` remains only presentation and app-edge composition, consistent with the accepted target architecture. | Subsequent implementation and enforcement work may treat the accepted target homes and retired transitional seams as the stable architecture baseline. |

## Milestone completion criteria

### Milestone `M1`

- `milestone_id`: `M1`
- `source_stage_ids`: `S1`
- `depends_on`: `none`
- `structural_outcome_proved`: Presentation-to-Application boundaries are stabilized enough that mixed orchestration concerns no longer define the desktop presentation seam, and split points between desktop-owned app-edge code and reusable Application-owned orchestration are explicit and reviewable.
- `acceptance_criteria`:
  - Presentation feature behavior depends on the Application Facade boundary rather than directly on persistence, host, or observability implementations.
  - The current mixed seams called out by issue #48 are no longer judged as single final ownership units; their desktop-owned, Application-owned, and later adapter-owned portions are structurally distinguishable.
  - Desktop-owned controller/view-state shaping and app-edge composition remain bounded to `apps/common_code_desktop` rather than continuing to own reusable orchestration.
  - Application-owned orchestration and contract concerns are stable enough that later stages can re-home persistence, host, and observability responsibilities without re-deriving boundary intent.
  - Dependency direction from issue #41 remains intact while this boundary stabilization is judged complete.
- `completion_evidence`:
  - Accepted architecture state shows a stable presentation-facing facade boundary and explicit separation of desktop presentation/app-edge concerns from reusable Application-owned orchestration concerns.
  - The mixed seams identified in issue #48 can be reviewed as split responsibilities mapped to accepted homes rather than as blended desktop or `host_core` ownership.
  - No accepted boundary statement for persistence, host adapters, or observability must be reinterpreted to explain where presentation responsibility ends.
- `non_evidence`:
  - A PR exists, work started, or some controller/runtime refactor landed.
  - A to-do list, extraction checklist, or branch plan says the seam will be split later.
  - Partial code movement that still leaves presentation and reusable orchestration ownership structurally ambiguous.
- `enables_after_acceptance`:
  - `M2` may rely on persistence re-home work not needing to rediscover the presentation/application split.
  - `M3` may rely on host-related contract separation beginning from stable Application-owned orchestration boundaries instead of blended desktop/runtime seams.

### Milestone `M2`

- `milestone_id`: `M2`
- `source_stage_ids`: `S2`
- `depends_on`: `M1`
- `structural_outcome_proved`: Persistence-owned continuity, snapshot, and translation concerns are structurally re-homed behind the accepted persistence boundary and Application-owned `session store` contract rather than remaining desktop-owned or blended into host/runtime seams.
- `acceptance_criteria`:
  - Durable continuity ownership is reviewably aligned with the persistence model from issue #45.
  - Snapshot storage access, snapshot translation, and legacy-shape normalization are structurally persistence concerns rather than presentation or host execution concerns.
  - Persistence completion preserves restart/continuity semantics without absorbing host execution, live session observation, observability ownership, or presentation state.
  - Persistence adapters remain inward-facing to Application and Domain and do not create reverse dependency paths.
  - The accepted target home for persistence-owned responsibilities is stable enough that later host-adapter draining work does not need to carry continuity ownership with it.
- `completion_evidence`:
  - Accepted architecture state shows continuity persistence, snapshot translation, and normalization responsibilities owned behind the persistence boundary defined by issues #43 and #45.
  - Reviewers can identify durable continuity responsibilities as persistence-owned without treating desktop-local files or mixed host/runtime seams as the long-term owner.
  - Host-related seams can be evaluated independently of persistence-owned continuity because the ownership boundary is no longer blended.
- `non_evidence`:
  - A storage engine was chosen, data classes were drafted, or migration chores were enumerated.
  - Partial extraction that still leaves continuity ownership split ambiguously across desktop and host seams.
  - Release notes, roadmap status, or implementation-task progress reports.
- `enables_after_acceptance`:
  - `M3` may rely on persistence-owned continuity having a stable home before host gateway and in-memory host responsibilities are judged complete.
  - `M5` may later rely on transitional seam retirement not needing to preserve desktop-local continuity ownership.

### Milestone `M3`

- `milestone_id`: `M3`
- `source_stage_ids`: `S3`
- `depends_on`: `M1`, `M2`
- `structural_outcome_proved`: Host gateway, session observation, and in-memory host adapter responsibilities are structurally separated from transitional `host_core` ownership in alignment with the accepted Application-port and host-adapter boundaries, while OpenCode-specific semantics remain confined to the accepted OpenCode adapter boundary.
- `acceptance_criteria`:
  - Host gateway and session observation are reviewably Application-owned contract concerns rather than transitional `host_core` ownership.
  - In-memory host execution lifecycle and runtime observation implementation are reviewably host-adapter responsibilities rather than persistence or desktop presentation ownership.
  - Transitional `host_core` ownership is drained as an architecture concept; it is not treated as a canonical target home.
  - Persistence-owned continuity responsibilities accepted in `M2` do not flow back into host seams.
  - OpenCode boundary integrity from issue #44 remains fixed; host separation does not leak OpenCode semantics upward or reinterpret the stale local ADR status label.
- `completion_evidence`:
  - Accepted architecture state shows clear separation between Application-owned host contracts and adapter-owned in-memory host implementation responsibilities.
  - Reviewers can identify `host_core` as transitional-only rather than as the enduring owner of gateway, observation, or bounded contract-failure ownership.
  - Host-related responsibility ownership can be judged without conflating it with persistence continuity or observability plumbing.
- `non_evidence`:
  - A new adapter package exists but responsibility ownership is still mixed.
  - `host_core` still acts as the de facto long-term contract home even if some files were moved.
  - Partial host refactors, bootstrap rewiring, or transport experiments that do not yet prove stable boundary ownership.
- `enables_after_acceptance`:
  - `M4` may rely on stabilized Application/host separation before judging observability re-home complete.
  - `M5` may rely on transitional host seams being drainable rather than architecturally required.

### Milestone `M4`

- `milestone_id`: `M4`
- `source_stage_ids`: `S4`
- `depends_on`: `M1`, `M2`, `M3`
- `structural_outcome_proved`: Observability and diagnostics responsibilities are structurally behind the accepted observability boundary and Application-owned observability / diagnostics contract rather than owned by desktop runtime seams.
- `acceptance_criteria`:
  - Concrete diagnostics sinks, records, and observability helpers are reviewably owned by the accepted observability boundary from issue #46.
  - Application remains the owner of the observability / diagnostics contract intent defined in issue #43.
  - Presentation-visible notices, loading/error states, and Notification semantics are not redefined as raw observability ownership.
  - Desktop-local diagnostics placement is no longer the architectural owner of reusable observability behavior.
  - Dependency direction remains intact and observability does not absorb host execution, persistence ownership, or presentation behavior.
- `completion_evidence`:
  - Accepted architecture state shows observability responsibilities behind the accepted observability boundary instead of threaded through desktop/runtime seams as their long-term owner.
  - Reviewers can distinguish Application-owned diagnostic intent from concrete observability adapter support and from presentation-facing result surfaces.
  - Final seam retirement can be judged without relying on desktop-local diagnostics ownership remaining in place.
- `non_evidence`:
  - Logging or telemetry libraries were added.
  - Diagnostic events are emitted somewhere, but ownership is still desktop-local or mixed with host/runtime seams.
  - Implementation notes, branch plans, or rollout plans claiming observability will be cleaned up later.
- `enables_after_acceptance`:
  - `M5` may rely on diagnostics and observability ownership no longer blocking retirement of transitional seams.
  - Later enforcement or implementation work may rely on the accepted observability boundary as the stable reusable home for diagnostics support.

### Milestone `M5`

- `milestone_id`: `M5`
- `source_stage_ids`: `S5`
- `depends_on`: `M1`, `M2`, `M3`, `M4`
- `structural_outcome_proved`: Transitional seams have been retired and `apps/common_code_desktop` remains only presentation and app-edge composition, consistent with the accepted target package map, dependency posture, and architecture boundaries.
- `acceptance_criteria`:
  - Transitional seams are no longer required as ownership homes because replacement responsibilities are stable in the accepted target homes.
  - `apps/common_code_desktop` is reviewably bounded to presentation and app-edge composition only.
  - `packages/host_core` is not normalized as a target package or enduring ownership concept.
  - The accepted target package set from issue #40 is sufficient to explain responsibility ownership without fallback to transitional seams.
  - Final architecture state remains aligned with issues #39 through #48, including dependency direction, persistence semantics, observability semantics, and OpenCode boundary rules.
- `completion_evidence`:
  - Accepted architecture state can be explained entirely through the accepted target homes and boundaries without relying on transitional seam ownership.
  - Reviewers can judge desktop as presentation/app-edge composition only, with reusable orchestration and adapter responsibilities already stably re-homed.
  - Transitional seam retirement is backed by the prior milestone outcomes rather than by file deletion alone.
- `non_evidence`:
  - A file or package was deleted, renamed, or marked deprecated without proving stable replacement ownership.
  - Transitional seams still carry required architecture responsibility even if usage is reduced.
  - Release readiness, branch cleanup, or implementation throughput metrics.
- `enables_after_acceptance`:
  - Later implementation, enforcement, and review work may rely on the accepted target architecture as the stable post-migration ownership model.
  - Future slices may treat transitional seam retirement as complete without reopening stage order, target homes, or contract boundaries from issues #39 through #48.

## What counts as completion evidence

Milestone completion evidence must stay milestone-level and structural. Valid evidence categories include:

- accepted responsibility ownership state aligned with the target homes and boundaries already accepted in issues #39 through #48
- accepted dependency posture showing the required inward direction and absence of reverse ownership assumptions
- accepted seam-retirement or seam-stabilization state proving that mixed seams are split, drained, or retired at the architecture level
- accepted boundary integrity showing that facade, port, persistence, host-adapter, OpenCode, and observability boundaries remain intact while a milestone is judged complete

Completion evidence is not the same thing as execution detail. The following do not count as milestone-completion evidence on their own:

- implementation to-do lists or task decomposition
- PR counts, branch counts, or batching strategy
- work started or partial refactors landed
- release notes, rollout state, or calendar progress
- companion evidence bundles outside this canonical document

## What milestone acceptance unlocks

Milestone acceptance unlocks only the reliance already implied by the accepted stage dependencies from issue #48.

- Acceptance of `M1` unlocks reliance for `M2` and `M3` on stable presentation/application split points.
- Acceptance of `M2` unlocks reliance for `M3` and `M5` on persistence-owned continuity no longer being blended into transitional host/runtime seams.
- Acceptance of `M3` unlocks reliance for `M4` and `M5` on stable Application/host-adapter separation and drained transitional host ownership.
- Acceptance of `M4` unlocks reliance for `M5` on observability ownership no longer being blended into desktop/runtime seams.
- Acceptance of `M5` unlocks reliance on the accepted target architecture as the stable post-migration ownership baseline.

These unlocks do not create a new migration sequence. They restate the accepted dependency backbone from issue #48 in milestone-acceptance terms.

## Non-goals

This artifact does not:

- define an alternate migration sequence
- turn milestones into implementation checklists
- prescribe PR batching, branch choreography, or release planning
- create new package-map, dependency-rule, contract, or boundary decisions
- create extra companion artifacts, appendices, inventories, or evidence files

The explicit acceptance comment on issue #49 remains required as a separate completion action outside this diff.
