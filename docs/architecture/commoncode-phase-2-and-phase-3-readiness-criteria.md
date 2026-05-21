# CommonCode Phase 2 and Phase 3 readiness criteria

## Status and scope

- Status: planning/specification only
- Change scope: docs-only
- Sole canonical artifact for issue #53: `docs/architecture/commoncode-phase-2-and-phase-3-readiness-criteria.md`
- Required completion action outside this diff: an explicit acceptance comment on issue #53 linking this document as the approved readiness artifact

This document defines Phase 2 and Phase 3 as planner-safe readiness overlays on top of the already accepted CommonCode stage and milestone backbone. It derives from, and does not reopen, the accepted architecture baseline from issues #39 through #49. It does not authorize implementation work, redefine stage order, change package ownership, change dependency rules, approve a migration plan, or design remote-host, identity, authentication, trust, protocol, IPC, transport, or security architecture details.

## Alignment with accepted architecture and milestone baseline

This document is a consequence of accepted issues #39 through #49 rather than a replacement for them.

| Accepted prerequisite | Governing reuse in this readiness artifact |
| --- | --- |
| Issue #39 / `docs/adr/0006-commoncode-layered-architecture-constitution.md` | Keeps the governing `Presentation -> Application Facade -> Domain` direction, keeps Domain pure, and keeps adapter concerns behind inward-facing seams. |
| Issue #40 / `docs/architecture/commoncode-target-module-package-map.md` | Keeps the accepted target package and app-shell ownership set fixed. |
| Issue #41 / `docs/architecture/commoncode-dependency-matrix-and-allowed-imports.md` | Keeps dependency direction and import-surface discipline fixed while readiness is judged. |
| Issue #42 / `docs/architecture/commoncode-application-facade-contract.md` | Keeps the Application Facade as the only stable presentation-facing boundary. |
| Issue #43 / `docs/architecture/commoncode-application-port-contract-set.md` | Keeps host gateway, session store, session observation, identity context, and observability / diagnostics as Application-owned contract concerns. |
| Issue #44 / `docs/adr/0007-opencode-host-adapter-boundary-and-mapping-rules.md` | Keeps OpenCode-specific runtime translation isolated behind the accepted host-adapter boundary even though the local ADR status text is stale. |
| Issue #45 / `docs/architecture/commoncode-persistence-model-and-adapter-contract.md` | Keeps durable continuity, snapshot translation, and persistence normalization behind the accepted persistence boundary. |
| Issue #46 / `docs/architecture/commoncode-observability-model-and-diagnostics-boundary.md` | Keeps observability and diagnostics behind the accepted Application-owned boundary and observability adapter home. |
| Issue #47 / accepted comment + canonical blob URL | Supplies the current-to-target mapping baseline; transitional seams such as `packages/host_core` remain transitional only and must not be normalized as target ownership. |
| Issue #48 / accepted comment + canonical blob URL | Supplies the fixed stage backbone `S1 -> S2 -> S3 -> S4 -> S5`. |
| Issue #49 / accepted comment + canonical blob URL | Supplies the fixed milestone backbone `M1 -> M2 -> M3 -> M4 -> M5` and the structural outcomes each milestone proves. |

Because issues #47, #48, and #49 are accepted but their canonical files are absent from the current checkout, their accepted GitHub comments and canonical blob URLs remain authoritative for this document. Because issue #44 is accepted even if `docs/adr/0007-opencode-host-adapter-boundary-and-mapping-rules.md` still shows `Status: Proposed` locally, issue acceptance plus artifact content remain authoritative here.

## Backbone mapping from S1-S5 / M1-M5 to phase readiness

Phase 2 and Phase 3 are readiness labels layered onto the accepted migration backbone. They are not competing stage models, not replacements for milestone completion, and not synonyms for implementation completion.

| Readiness level | Hard backbone prerequisites | Advisory / not-yet-assumed backbone context | Planner-safe backbone meaning |
| --- | --- | --- | --- |
| Phase 2 | `M1`, `M2`, `M3` | `M4`, `M5` | Later planning may rely on the structural outcomes proved by `M1` through `M3`, while `M4` and `M5` remain future context and must not be assumed complete. |
| Phase 3 | `M1`, `M2`, `M3`, `M4` | `M5` | Later planning may rely on the structural outcomes proved by `M1` through `M4` and on `S5` / `M5` remaining the fixed retirement destination, but must not assume `M5` is already complete unless later work separately proves it. |

## How Phase 2 and Phase 3 are interpreted in this program

- Phase readiness is a planner-safe reliance label layered onto the accepted milestone backbone.
- Milestone completion and phase readiness are related but not interchangeable.
- Phase 2 readiness means later planning may rely on the accepted structural outcomes of `M1`, `M2`, and `M3` without reopening those baseline decisions.
- Phase 3 readiness inherits all Phase 2 hard prerequisites and adds the accepted structural outcome of `M4`.
- Neither readiness level redefines the accepted order `S1 -> S2 -> S3 -> S4 -> S5` or `M1 -> M2 -> M3 -> M4 -> M5`.
- Neither readiness level authorizes implementation or pre-decides remote-host, identity, authentication, trust, protocol, IPC, transport, or security solution details.

## Inherited decisions from accepted prerequisites

- Presentation remains thin and depends on the Application Facade rather than directly on persistence, host, or observability implementations.
- `packages/common_code_application` remains the owner of stable application-facing orchestration and Application-owned ports.
- `packages/common_code_persistence` remains the accepted home of persistence adapters and durable continuity translation.
- `packages/host_in_memory` and `packages/host_opencode` remain host-adapter homes beneath Application-owned contracts.
- `packages/common_code_observability` remains the accepted concrete observability support home.
- `apps/common_code_desktop` remains a presentation/app-edge composition host rather than a reusable long-term owner of orchestration, persistence, host, or observability responsibilities.
- `packages/host_core` remains transitional current-state context only and must not be treated as a canonical target home.

## Canonical readiness criteria

### Phase 2

- `readiness_level`: `Phase 2`
- `backing_stage_or_milestone_context`:
  - readiness overlay on accepted stages `S1`, `S2`, and `S3`
  - hard milestone prerequisites: `M1` stabilized presentation-to-application boundary, `M2` persistence boundary stabilization, `M3` host gateway and in-memory host separation
  - advisory / not-yet-assumed context: `M4` observability boundary stabilization and `M5` transitional seam retirement
- `structural_conditions`:
  - the Application Facade from issue #42 is stable enough to remain the only presentation-facing contract boundary for later planning
  - the Application-owned port seams from issue #43 are clear enough that later work can plan against host gateway, session store, session observation, identity context, and observability / diagnostics as distinct Application-owned concerns
  - persistence-owned continuity, snapshot translation, and normalization responsibilities are structurally behind the accepted persistence boundary from issue #45 rather than desktop-local mixed seams
  - host gateway, session observation, and in-memory host responsibilities are structurally separated enough that later planning is not forced to treat `packages/host_core` or desktop-local mixed runtime seams as canonical ownership homes
  - desktop direction is stabilized toward presentation/app-edge-only ownership rather than reusable orchestration or persistence ownership
  - the current-to-target mapping from issue #47 and the stage / milestone backbone from issues #48 and #49 remain the governing interpretation of target ownership and sequencing
- `hard_prerequisites`:
  - `M1` is satisfied as the structural proof that Presentation no longer defines reusable orchestration ownership and instead depends on the stable Application Facade boundary
  - `M2` is satisfied as the structural proof that persistence-owned continuity, snapshot storage, translation, and normalization belong behind the accepted persistence boundary
  - `M3` is satisfied as the structural proof that host gateway and session observation are Application-owned contract concerns, in-memory host behavior is adapter-side, and `packages/host_core` is transitional-only rather than a target home
- `advisory_quality_of_readiness_criteria`:
  - observability boundaries from issue #46 are already framed in later planning terms even though `M4` is not assumed complete
  - desktop app-edge composition language is already used consistently in planning rather than slipping back toward desktop-owned orchestration language
  - future work proposals already reference accepted target homes and Application-owned ports instead of transitional file names as if they were final architecture
  - future host-facing planning already treats OpenCode-specific concerns as adapter-contained rather than as reusable product semantics
- `traceability_to_accepted_baseline`:
  - issue #39: layered constitution and inward dependency direction
  - issue #40: target package map and desktop-as-app-shell posture
  - issue #41: dependency and import policy that prevents reverse adapter coupling
  - issue #42: stable presentation-facing Application Facade
  - issue #43: Application-owned port contract set
  - issue #45: persistence model and adapter contract
  - issue #47: current-to-target mapping, especially the transitional-only treatment of `packages/host_core`
  - issue #48: stage backbone `S1` through `S5`
  - issue #49: milestone proofs for `M1`, `M2`, and `M3`
- `planner_safe_reliance_after_satisfaction`:
  - later planning may assume the accepted structural outcomes of `M1`, `M2`, and `M3` are satisfied and stable enough to rely on
  - later planning may assume desktop is not the canonical long-term owner of reusable orchestration, persistence continuity, host gateway contracts, or session observation contracts
  - later planning may assume `packages/host_core` is transitional-only and must not be treated as a target ownership home
  - later planning may assume future work should consume the existing Application Facade and Application-owned port seams rather than reopen them
  - later planning may assume persistence, host gateway, and session observation ownership questions are structurally settled enough to plan additional work without re-litigating those prerequisites
- `explicit_non_assumptions`:
  - do not assume `M4` observability completion or `M5` transitional seam retirement is already complete
  - do not assume any remote-host protocol, IPC, or transport decision has been made
  - do not assume any remote identity model, principal model, session trust model, or authentication flow has been selected
  - do not assume trust establishment, credential exchange, key management, token handling, or cross-machine authorization semantics have been designed
  - do not assume future work may bypass the accepted Application Facade or Application-owned ports merely because current transitional seams still exist in code

### Phase 3

- `readiness_level`: `Phase 3`
- `backing_stage_or_milestone_context`:
  - inherits all Phase 2 readiness meaning and adds accepted stage `S4`
  - hard milestone prerequisites: inherited `M1`, `M2`, `M3`, plus `M4` observability boundary stabilization
  - advisory / post-retirement context: `M5` as the fixed retirement destination for transitional seams and desktop-as-app-edge-only posture
- `structural_conditions`:
  - all Phase 2 structural conditions remain true
  - observability and diagnostics are structurally behind the accepted observability boundary from issue #46 rather than being treated as desktop-runtime ownership
  - OpenCode-specific host semantics remain isolated behind the accepted issue #44 host-adapter boundary and are not treated as product-semantic or presentation-facing concepts
  - desktop end-state direction is stable enough that later planning can rely on desktop remaining presentation/app-edge composition only, even if final retirement work captured by `M5` is not yet complete
  - future remote-host, identity, authentication, and trust work can proceed only on the basis of stabilized seams and ownership boundaries rather than on implied security, protocol, or transport decisions already being made
- `hard_prerequisites`:
  - all Phase 2 hard prerequisites remain required
  - `M4` is satisfied as the structural proof that observability and diagnostics responsibilities are behind the accepted Application-owned observability boundary and observability adapter home
  - accepted issue #44 boundary integrity is preserved so OpenCode-specific translation remains adapter-contained and does not leak vocabulary or authority upward into Application, Domain, or Presentation
- `advisory_quality_of_readiness_criteria`:
  - later planning language already treats `M5` as a fixed destination posture rather than as a reopened architecture question
  - future-facing planning already frames remote-host, identity, authentication, and trust topics as deferred solution design constrained by stabilized seams, not as reopened ownership debates
  - observability-facing planning already distinguishes Application-owned diagnostic intent, concrete observability adapters, and presentation-facing result surfaces without collapsing them together
  - planning already avoids treating current desktop-local or transitional diagnostics plumbing as a long-term reusable home
- `traceability_to_accepted_baseline`:
  - inherits all Phase 2 traceability
  - issue #44: OpenCode host-adapter boundary and mapping rules remain authoritative despite stale local ADR status text
  - issue #46: observability model and diagnostics boundary
  - issue #49: `M4` as the observability boundary stabilization proof and `M5` as the retirement destination context
- `planner_safe_reliance_after_satisfaction`:
  - later planning may assume all Phase 2 planner-safe assumptions remain true
  - later planning may assume observability and diagnostics ownership is stabilized behind the accepted Application / observability boundary represented by `M4`
  - later planning may assume OpenCode-specific host semantics remain isolated behind the accepted issue #44 boundary and are not to be reopened
  - later planning may assume the accepted `S5` / `M5` retirement destination remains fixed: desktop ends as presentation/app-edge composition only and transitional seams remain slated for retirement even if that retirement is not yet complete
  - later planning may proceed on advanced adapter and future-remote prerequisites without re-litigating facade ownership, port ownership, persistence ownership, host separation, observability ownership, or OpenCode boundary discipline
- `explicit_non_assumptions`:
  - do not assume `M5` is already complete unless a later slice separately proves post-retirement completion
  - do not assume remote-host transport, handshake, protocol framing, or IPC details are already decided
  - do not assume identity, authentication, authorization, trust establishment, trust policy, credential, token, or key-management architecture is already decided
  - do not assume remote-host work may bypass the accepted Application Facade, Application-owned ports, OpenCode adapter boundary, or observability boundary
  - do not assume this readiness document approves release sequencing, implementation batching, or concrete security architecture

## Planner-safe reliance after readiness is satisfied

### Phase 2 reliance summary

- safe to plan against stable Application-facade and Application-port ownership
- safe to plan against accepted persistence ownership and host separation outcomes through `M3`
- safe to treat desktop and `host_core` as non-canonical homes for reusable long-term ownership
- not safe to assume observability completion or transitional seam retirement completion

### Phase 3 reliance summary

- safe to plan against all Phase 2 reliance assumptions
- safe to plan against observability ownership being stabilized behind the accepted boundary
- safe to plan against OpenCode isolation behind the accepted host-adapter boundary
- safe to treat the `M5` retirement destination as fixed, but not as already complete

## Explicit non-assumptions and deferred future concerns

- This document does not define remote-host protocol design.
- This document does not define identity model design.
- This document does not define authentication flows.
- This document does not define trust establishment, trust policy, credential exchange, token handling, key management, or cross-machine authorization semantics.
- This document does not define transport, IPC, or security architecture.
- This document defines only the prerequisite seam and boundary readiness that later work must preserve when those topics are eventually designed.

## Non-goals

This artifact does not:

- create a competing migration sequence
- redefine milestone order or dependency posture
- change accepted package ownership, dependency rules, or contract ownership
- normalize current desktop-local mixed seams or `packages/host_core` as canonical target architecture
- approve implementation work, release scheduling, PR choreography, or branch sequencing
- replace the separately required acceptance comment on issue #53
