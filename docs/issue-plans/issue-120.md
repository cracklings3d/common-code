---
issue: github.com/cracklings3d/common-code#120
title: Add regression coverage for Application-owned port placement in the desktop/in-memory path
status: approved
plan_status: approved
review_status: passed
source:
  - github.com/cracklings3d/common-code#120
  - docs/issue-plans/issue-118.md
  - docs/issue-plans/issue-119.md
  - docs/issue-plans/issue-122.md
owner: architect
created_at: 2026-05-31
updated_at: 2026-05-31
approved_by: subjective-rose-python
approved_at: 2026-05-29T00-00:00Z
review_artifact: 'C:\Users\The_u\.opencode\projects\github-com-cracklings3d-common-code\runs\canonical-issue-resolver-parallel\2026-05-29T00-00-00Z-run-01\reviews\issue-120\loop-2-stage-D.json'
related_branch: issue-120
related_pr: null
replaces: null
supersedes: []
change_scope:
  files:
    - docs/issue-plans/issue-120.md
    - apps/common_code_desktop/test/desktop_session_app_edge_composition_test.dart
    - apps/common_code_desktop/test/desktop_session_runtime_test.dart
  directories:
    - docs/issue-plans
    - apps/common_code_desktop/test
  modules:
    - apps/common_code_desktop/test/desktop_session_app_edge_composition_test.dart::createDesktopSessionFacade current desktop/in-memory regression coverage
    - apps/common_code_desktop/test/desktop_session_runtime_test.dart::HostDesktopSessionRuntime current desktop/in-memory regression coverage
    - apps/common_code_desktop/test/desktop_session_runtime_test.dart::createDesktopSessionRuntime factory-path regression coverage
  artifacts:
    - docs/issue-plans/issue-120.md
    - desktop regression guards for host_in_memory-owned in-memory gateway and session observation placement
    - desktop regression guards for explicit app-edge identity-context threading
---

# Summary

Issue #120 is a regression-coverage-only child slice after the production ownership and identity-placement work from #118, #119, and #122 has already landed. The intended outcome is narrow desktop test coverage that proves the current desktop/in-memory path still uses the completed Application-owned bootstrap inputs and the `packages/host_in_memory` in-memory adapters, without reopening any production placement decisions. Because pure behavior-only coverage may not distinguish ownership drift, this plan authorizes one narrow read-only source-structure regression guard from the scoped test surface and otherwise requires an early replan instead of widening scope.

# Problem

Current master already contains grounding tests for the completed identity-threading work: `apps/common_code_desktop/test/desktop_session_app_edge_composition_test.dart` includes `facade threads non-default desktopIdentityId and attachedClientId from app edge`, and `apps/common_code_desktop/test/desktop_session_runtime_test.dart` includes `createDesktopSessionRuntime threads non-default app-edge identity through bootstrap to context`. Issue #120 still needs its own narrow governing plan because the remaining work is not production refactoring; it is regression hardening around the already-landed desktop/in-memory ownership boundary so later changes cannot silently move the concrete in-memory gateway/observation back into desktop-local code or fall back to the hardcoded desktop runtime identity path. The plan therefore needs one concrete, reviewer-verifiable ownership-boundary assertion that can be expressed from the authorized public/test surface; if that cannot be done with read-only evidence, Stage D must stop and request replanning.

# Acceptance Criteria

1. `apps/common_code_desktop/test/desktop_session_app_edge_composition_test.dart` preserves facade-path regression coverage for the default desktop/in-memory composition while exercising explicit non-default `desktopIdentityId` / `attachedClientId` input from the app edge.
2. `apps/common_code_desktop/test/desktop_session_runtime_test.dart` preserves runtime/factory-path regression coverage proving explicit non-default app-edge identity/client input reaches runtime session context instead of falling back to `desktopSessionRuntimeIdentityId` / `desktopSessionRuntimeAttachedClientId`.
3. `apps/common_code_desktop/test/desktop_session_app_edge_composition_test.dart` adds one concrete read-only source-structure regression guard that fails if the default `createDesktopSessionFacade(...)` path no longer imports `package:host_in_memory/host_in_memory.dart`, no longer composes `PersistingHostServiceSessionMutations`, `PersistingHostServiceSessionObservation`, and `HostServiceSessionObservation`, or if `apps/common_code_desktop/lib/src/desktop_session_facade_adapters.dart` regains those moved concrete types.
4. Focused reviewer validation for AC1-AC4 is fully reproducible from this plan plus the two scoped desktop test files, with exact commands or equivalent reviewer steps and explicit permitted/prohibited evidence.
5. Scope stays regression-coverage-only and does not reopen production ownership, placement, adapter, or identity work from #118, #119, or #122.

# In Scope

- Extend `apps/common_code_desktop/test/desktop_session_app_edge_composition_test.dart` for the current default desktop/in-memory facade composition path.
- Extend `apps/common_code_desktop/test/desktop_session_runtime_test.dart` for the current runtime/factory bootstrap path.
- Add only the smallest co-located test helpers inside those test files if needed to express non-default identity/client inputs or current-path regression assertions.
- Use the already-landed `package:host_in_memory/host_in_memory.dart` exports and the current desktop app-edge/runtime entrypoints as the fixed baseline under test.

# Out Of Scope

- Any production-file edits in `apps/common_code_desktop/lib/src/**`, `packages/host_in_memory/lib/**`, or `packages/common_code_application/lib/**`.
- Reopening the merged production decisions from #118 (PR #142 / `beda6a633d317087ac3f438d2b7ed8c2cbfcce10`), #119 (PR #141 / `a647cb409f19c3ca2df8f0f24157dcefa8b70e17`), or #122 (PR #140 / `984ad0e83b84d3eb376d1daf50ceb271f98079a6`).
- Broadening into new runtime, controller, adapter, package-boundary, or identity-system redesign work.
- Adding new architectural seams just to inspect internals; any need for production-side test seams requires a plan revision rather than silent scope growth.
- `apps/common_code_desktop/test/desktop_session_controller_test.dart` unless a later approved revision explicitly adds a narrow delegation-only assertion there.

# Constraints

- Treat this issue as regression coverage only; production ownership authority remains with the already-completed #118 / #119 / #122 work.
- Keep the editable hotspot set exclusive to the two desktop test files listed in `change_scope.files` plus this plan artifact.
- Reuse the current public/default desktop entrypoints: `createDesktopSessionFacade(...)`, `HostDesktopSessionRuntime(...)`, and `createDesktopSessionRuntime(...)`.
- `packages/host_in_memory/lib/host_in_memory.dart` is a reference baseline showing the approved export location for `in_memory_session_observation.dart` and `in_memory_host_gateway.dart`; no edit is authorized here.
- The existing named tests in the two scoped desktop test files are baseline coverage to strengthen, not authority to widen the slice.
- Permitted evidence is limited to: (a) behavioral assertions in the two scoped desktop test files and (b) read-only source-structure assertions from `desktop_session_app_edge_composition_test.dart` against `apps/common_code_desktop/lib/src/desktop_session_app_edge_composition.dart`, `apps/common_code_desktop/lib/src/desktop_session_facade_adapters.dart`, and `packages/host_in_memory/lib/host_in_memory.dart`.
- Prohibited evidence includes production edits, reflective/runtime hacks, debug-only seams, new exported diagnostics, or widening assertions beyond the named files just to prove ownership.
- If Acceptance Criterion 3 cannot be expressed with that permitted read-only evidence, stop and request a plan revision instead of widening implementation scope during Stage D.

# Proposed Approach

1. **Harden facade-path regression coverage in `desktop_session_app_edge_composition_test.dart`.**
   - Keep the test subject on the current default desktop/in-memory composition path.
   - Strengthen or add assertions around explicit non-default `desktopIdentityId` / `attachedClientId` threading from the app edge.
   - Add one read-only source-structure regression guard that inspects the current source text of `desktop_session_app_edge_composition.dart`, `desktop_session_facade_adapters.dart`, and `packages/host_in_memory/lib/host_in_memory.dart` to verify the default facade path still depends on the package-owned `PersistingHostServiceSessionMutations`, `PersistingHostServiceSessionObservation`, and `HostServiceSessionObservation` composition and that the desktop-local adapter file has not regained those concrete types.

2. **Harden runtime-path regression coverage in `desktop_session_runtime_test.dart`.**
   - Keep coverage focused on the current bootstrap/context flow used by `HostDesktopSessionRuntime` and `createDesktopSessionRuntime(...)`.
   - Add or strengthen assertions so the runtime/factory path fails if it reverts to `desktopSessionRuntimeIdentityId` instead of honoring the explicit app-edge-supplied identity/client inputs.

3. **Keep helpers local and non-authoritative.**
   - Any new fixtures should stay inside the scoped test files and exist only to make the regression assertions readable and deterministic.
   - Do not add new production helpers, exported diagnostics, or composition seams under this plan.

4. **Use an explicit infeasible-proof branch if needed.**
   - If the ownership-boundary guard cannot be implemented with the permitted read-only assertions above, Stage D must stop, record that AC3 is unprovable from the current surface, and request a plan revision instead of introducing broader source inspection or production seams.

# Impacted Areas

| Area | Why it is impacted |
| --- | --- |
| `docs/issue-plans/issue-120.md` | Canonical governing artifact for this regression-only slice. |
| `apps/common_code_desktop/test/desktop_session_app_edge_composition_test.dart` | Primary facade-path hotspot for default desktop/in-memory composition and explicit app-edge identity/client threading checks. |
| `apps/common_code_desktop/test/desktop_session_runtime_test.dart` | Primary runtime/factory hotspot for bootstrap-request identity-context and cached session-context regression checks. |
| `packages/host_in_memory/lib/host_in_memory.dart` | Reference-only ownership baseline for the exported in-memory gateway/observation implementations; no edit planned. |
| `apps/common_code_desktop/lib/src/desktop_session_app_edge_composition.dart` | Reference-only current production composition seam; no edit authorized by this plan. |
| `apps/common_code_desktop/lib/src/desktop_session_facade_adapters.dart` | Reference-only ownership-boundary seam used only for read-only regression assertions that the moved concrete types do not reappear in desktop-local adapters. |
| `apps/common_code_desktop/lib/src/desktop_session_runtime.dart` | Reference-only current production runtime seam; no edit authorized by this plan. |

# Validation Plan

- From the workspace root, run `flutter test apps/common_code_desktop/test/desktop_session_app_edge_composition_test.dart` to validate AC1 and AC3.
- From the workspace root, run `flutter test apps/common_code_desktop/test/desktop_session_runtime_test.dart` to validate AC2 and the identity-fallback half of AC4.
- Reviewer step for AC3 and the evidence-policy half of AC4: inspect `apps/common_code_desktop/test/desktop_session_app_edge_composition_test.dart` and confirm the ownership-boundary guard is implemented as read-only source-structure assertions only against `packages/host_in_memory/lib/host_in_memory.dart`, `apps/common_code_desktop/lib/src/desktop_session_app_edge_composition.dart`, and `apps/common_code_desktop/lib/src/desktop_session_facade_adapters.dart`, with no production edits or new test-only seams.
- Reviewer step for AC5: inspect the final diff and confirm edits are limited to `docs/issue-plans/issue-120.md`, `apps/common_code_desktop/test/desktop_session_app_edge_composition_test.dart`, and `apps/common_code_desktop/test/desktop_session_runtime_test.dart`.
- If the AC3 guard cannot be implemented with those read-only assertions, stop validation, record the infeasible-proof condition, and return for replanning instead of accepting broader changes.

# Risks

- The current public test surface may still prove insufficient for the ownership-boundary assertion even with read-only source checks; the mitigation is the explicit stop-and-replan branch rather than slipping in production seams.
- Tests could become vacuous if they only reassert non-default values without exercising the current default desktop/in-memory composition path.
- Any attempt to edit production files during implementation would violate this plan's scope guard and blur the completed ownership boundary from #118 / #119 / #122.

# Open Questions

- None for plan revision. If later implementation review finds that Acceptance Criterion 3 still cannot be proven from the permitted read-only surface, that is a re-planning trigger, not pre-authorized scope.

# Approval Notes

- This plan intentionally makes #120 a regression-only child artifact under the already-completed production baseline from #118, #119, and #122.
- The current code/test grounding for this plan is fixed to the existing desktop tests and the current `packages/host_in_memory` export surface described in the issue brief.
- No production-file changes are authorized by this Stage C artifact.
