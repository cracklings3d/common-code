---
issue: github.com/cracklings3d/common-code#118
title: Finish placing the Application-owned port set for the current desktop/in-memory path
status: draft
plan_status: proposed
review_status: pending
source:
  - github.com/cracklings3d/common-code#118
  - docs/issue-plans/issue-119.md
  - docs/issue-plans/issue-122.md
  - github.com/cracklings3d/common-code#120
owner: architect
created_at: 2026-05-29
updated_at: 2026-05-31
approved_by: null
approved_at: null
review_artifact: null
related_branch: issue-118-finish-placing-the-application-owned-port-set-for-the-current-desktop-in-memory-path
related_pr: null
replaces: null
supersedes: []
change_scope:
  files:
    - docs/issue-plans/issue-118.md
    - apps/common_code_desktop/lib/src/desktop_session_runtime.dart
    - apps/common_code_desktop/lib/src/desktop_session_facade_adapters.dart
    - apps/common_code_desktop/lib/src/desktop_session_app_edge_composition.dart
  directories:
    - docs/issue-plans
    - apps/common_code_desktop/lib/src
  modules:
    - apps/common_code_desktop/lib/src/desktop_session_runtime.dart::HostDesktopSessionRuntime._bootstrapIfNeeded
    - apps/common_code_desktop/lib/src/desktop_session_runtime.dart::HostDesktopSessionRuntime._ensureSessionContext
    - apps/common_code_desktop/lib/src/desktop_session_facade_adapters.dart::DesktopSessionBootstrapDriver.ensureSession
    - apps/common_code_desktop/lib/src/desktop_session_app_edge_composition.dart::createDesktopSessionFacade
    - apps/common_code_desktop/lib/src/desktop_session_app_edge_composition.dart::createDesktopSessionRuntime
  artifacts:
    - docs/issue-plans/issue-118.md
    - current desktop/in-memory bootstrap-request authority cleanup before github.com/cracklings3d/common-code#120
---

# Summary

Issue #118 is now a residual parent plan, not a parent-wide umbrella. Child issue #119 has already moved the current in-memory `HostGateway` / `CommonCodeSessionObservation` ownership into `packages/host_in_memory`, and child issue #122 has already introduced the shared Application-owned identity/bootstrap carrier. The remaining parent-owned work is only to finish the current desktop/in-memory production path so both desktop entrypoints are governed by the same app-edge-composed `CommonCodeSessionBootstrapRequest`, with downstream issue #120 reserved for regression coverage only.

# Problem

The plan version from 2026-05-29 is now too broad for safe parallel dependency control. Since then, the two intended child slices have landed on current master:

- `docs/issue-plans/issue-119.md` is complete and merged via PR #141 / commit `a647cb409f19c3ca2df8f0f24157dcefa8b70e17`, so desktop-local ownership of the current in-memory `HostGateway` / `CommonCodeSessionObservation` implementations is no longer active parent work.
- `docs/issue-plans/issue-122.md` is complete and merged via PR #140 / commit `984ad0e83b84d3eb376d1daf50ceb271f98079a6`, so the shared `CommonCodeSessionBootstrapRequest` carrier for desktop identity plus attached-client context is no longer active parent work.

Current master already reflects those moves in production code: `desktop_session_app_edge_composition.dart` composes host_in_memory-owned adapters and a shared `CommonCodeSessionBootstrapRequest`, and `desktop_session_runtime.dart` now derives runtime session context from `_currentBootstrapRequest`. The remaining gap is narrower and is confined to the shared desktop hotspots:

- `apps/common_code_desktop/lib/src/desktop_session_runtime.dart` still carries fallback bootstrap-request construction and desktop default inputs inside `HostDesktopSessionRuntime`, including fallback request assembly in `_bootstrapIfNeeded()`.
- `apps/common_code_desktop/lib/src/desktop_session_facade_adapters.dart` still allows `DesktopSessionBootstrapDriver.ensureSession()` to synthesize its own `CommonCodeSessionBootstrapRequest` from per-field defaults when no shared request is supplied.
- `apps/common_code_desktop/lib/src/desktop_session_app_edge_composition.dart` is already the right composition seam, but this parent plan must now make that seam the exclusive current-path owner instead of leaving alternate request-construction paths in the runtime/driver hotspots.

If that residual production cleanup is not isolated clearly, issue #120 cannot be scheduled safely because it would overlap the same files while trying to add regression coverage.

# Acceptance Criteria

1. `docs/issue-plans/issue-119.md` and `docs/issue-plans/issue-122.md` are treated as completed child authority; this plan no longer re-plans their already-landed work.
2. The remaining #118 scope is limited to the current desktop/in-memory production path in `desktop_session_runtime.dart`, `desktop_session_facade_adapters.dart`, and `desktop_session_app_edge_composition.dart`.
3. For the current desktop/in-memory path, the app-edge-composed `CommonCodeSessionBootstrapRequest` is the authoritative bootstrap/identity input for both `createDesktopSessionRuntime(...)` and `DesktopSessionBootstrapDriver.ensureSession()`, with no parallel desktop-local request-construction path governing that flow.
4. Shared hotspots are partitioned for dependency analysis with exclusive ownership: #118 owns residual production cleanup in the three desktop production files above, while #120 owns regression coverage only and does not modify those production files.
5. Existing current-path behavior still works after the residual ownership cleanup, and issue #120 remains the only slice allowed to add the drift-prevention regression coverage required by the parent issue.

# In Scope

- Finish the residual parent-owned production cleanup for the current desktop/in-memory path only.
- Make `desktop_session_app_edge_composition.dart` the explicit, authoritative source of the shared `CommonCodeSessionBootstrapRequest` used by both desktop entrypoints.
- Remove or isolate current-path bootstrap-request synthesis in `HostDesktopSessionRuntime` and `DesktopSessionBootstrapDriver` so the runtime/driver hotspots no longer own a competing desktop-local input path.
- Record artifact-level ownership boundaries between completed child work (#119, #122), residual parent work (#118), and downstream regression-only work (#120).

# Out Of Scope

- Reopening the completed #119 move of concrete in-memory `HostGateway` / `CommonCodeSessionObservation` ownership into `packages/host_in_memory`.
- Reopening the completed #122 extension of `CommonCodeSessionBootstrapRequest` or its initial identity-context threading through the current desktop path.
- Any new regression test additions or ownership-drift assertions; those belong exclusively to #120.
- Changes to `packages/host_in_memory`, `packages/common_code_application`, or desktop test files unless a later approved revision explicitly re-scopes them.
- OpenCode host work, out-of-process host paths, or broader desktop presentation/runtime redesign.

# Constraints

- ADR 0006 (`docs/adr/0006-commoncode-layered-architecture-constitution.md`) is the governing architecture baseline.
- `docs/architecture/commoncode-application-port-contract-set.md` is the binding contract baseline for the Application-owned port set used by this plan.
- `docs/architecture/commoncode-current-to-target-architecture-mapping.md` is the binding current-to-target mapping for ownership expectations in the affected desktop/runtime seams.
- `docs/architecture/commoncode-dependency-matrix-and-allowed-imports.md` is the binding dependency-direction rule set.
- Treat `docs/issue-plans/issue-119.md` and `docs/issue-plans/issue-122.md` as authoritative completed child-boundary references for this parent revision.
- #119 is dependency-satisfied by PR #141 / commit `a647cb409f19c3ca2df8f0f24157dcefa8b70e17`; #122 is dependency-satisfied by PR #140 / commit `984ad0e83b84d3eb376d1daf50ceb271f98079a6`.
- Follow the current dependency-planner rule exactly: implement residual #118 first, then open #120; do not parallelize them.
- Exclusive shared-hotspot ownership for this plan revision is:
  - `apps/common_code_desktop/lib/src/desktop_session_runtime.dart` → #118 residual production cleanup only.
  - `apps/common_code_desktop/lib/src/desktop_session_facade_adapters.dart` → #118 residual production cleanup only.
  - `apps/common_code_desktop/lib/src/desktop_session_app_edge_composition.dart` → #118 residual production cleanup only.
  - `apps/common_code_desktop/test/**` and `packages/host_in_memory/test/**` → #120 regression coverage only.
- Keep scope bounded to the current desktop/in-memory path; do not broaden into later adapter work or broader API redesign.

# Proposed Approach

1. **Lock the completed child boundaries as exclusions, not open work.**
   - #119 already owns and closes the concrete in-memory adapter relocation into `packages/host_in_memory`, including the remaining thin `HostGatewayDesktopSessionMutationPort` bridge left in desktop-local code.
   - #122 already owns and closes the shared `CommonCodeSessionBootstrapRequest` carrier extension for desktop identity plus attached-client context.
   - This parent revision must not re-plan, re-scope, or duplicate either merged child slice.

2. **Finish the residual parent-owned production cleanup in the shared desktop hotspots.**
   - In `apps/common_code_desktop/lib/src/desktop_session_runtime.dart`, remove or isolate the current-path fallback request construction so `_bootstrapIfNeeded()` and `_ensureSessionContext()` are governed by the app-edge-supplied `CommonCodeSessionBootstrapRequest` rather than a second desktop-local request assembly path.
   - In `apps/common_code_desktop/lib/src/desktop_session_facade_adapters.dart`, keep `DesktopSessionBootstrapDriver.ensureSession()` aligned to that same supplied request and stop letting the current path derive a parallel request from `defaultSessionId`, `hostId`, `attachedClientId`, and `desktopIdentityId`.
   - Keep the end state narrow: these files remain current-path runtime/bootstrap orchestration only, not alternate ownership homes for Application input values.

3. **Preserve app-edge composition as the exclusive current-path owner.**
   - `apps/common_code_desktop/lib/src/desktop_session_app_edge_composition.dart` remains the one authoritative place that composes the current desktop/in-memory `HostService`, bootstrap port, persistence continuation, host_in_memory-owned adapters, and shared `CommonCodeSessionBootstrapRequest`.
   - Both `createDesktopSessionFacade(...)` and `createDesktopSessionRuntime(...)` must continue to consume that same composed request so the runtime path and default facade bootstrap path cannot drift apart.

4. **Hand off coverage hardening to #120 only after this residual production cleanup lands.**
   - #120 owns the regression coverage for the moved in-memory gateway/observation path and the explicit identity-context path.
   - #118 should rely on existing focused current-path tests staying green after the residual production cleanup, rather than reopening test ownership here.

# Impacted Areas

| Area | Ownership in this revision | Notes |
| --- | --- | --- |
| `docs/issue-plans/issue-119.md` | Completed child reference only | Authoritative record for the already-landed `host_in_memory` ownership move; do not reopen in #118. |
| `docs/issue-plans/issue-122.md` | Completed child reference only | Authoritative record for the already-landed identity/bootstrap carrier move; do not reopen in #118. |
| `apps/common_code_desktop/lib/src/desktop_session_runtime.dart` | Residual #118 exclusive production hotspot | Parent-owned cleanup is limited to removing/isolation of current-path bootstrap-request fallback ownership in `HostDesktopSessionRuntime`. |
| `apps/common_code_desktop/lib/src/desktop_session_facade_adapters.dart` | Residual #118 exclusive production hotspot | Parent-owned cleanup is limited to aligning `DesktopSessionBootstrapDriver.ensureSession()` on the shared app-edge request and avoiding a second current-path request-construction path. |
| `apps/common_code_desktop/lib/src/desktop_session_app_edge_composition.dart` | Residual #118 exclusive production hotspot | Remains the sole current-path composition seam for runtime and facade bootstrap wiring. |
| `apps/common_code_desktop/test/**` | #120 exclusive hotspot | Regression coverage belongs to downstream issue #120, not to residual parent #118. |
| `packages/host_in_memory/test/**` | #120 exclusive hotspot | Use only for regression coverage of the moved in-memory adapter path after residual parent cleanup lands. |

# Validation Plan

- Run the focused current-path desktop tests already on master — especially `apps/common_code_desktop/test/desktop_session_runtime_test.dart`, `apps/common_code_desktop/test/desktop_session_app_edge_composition_test.dart`, and `apps/common_code_desktop/test/desktop_session_controller_test.dart` — and keep them green after the residual production cleanup.
- Confirm that the current default desktop/in-memory call graph composes one shared `CommonCodeSessionBootstrapRequest` in `desktop_session_app_edge_composition.dart` and that both runtime/bootstrap entrypoints consume that same request.
- Confirm that no current-path logic in `HostDesktopSessionRuntime` or `DesktopSessionBootstrapDriver` reconstructs desktop identity or attached-client context from desktop-local fallback values once the shared request is present.
- Leave new ownership-drift assertions and broader regression hardening to #120.

# Risks

- If the residual parent cleanup reopens `packages/host_in_memory` or `packages/common_code_application`, the child/parent partition becomes non-deterministic again.
- If fallback request construction is removed too broadly, non-current-path or injected-callsite behavior could regress instead of only narrowing the current desktop/in-memory path.
- If #120 starts before this residual production cleanup lands, regression tests could encode a temporary boundary and immediately conflict with parent-owned hotspots.

# Open Questions

- None. The residual parent work is now intentionally small and fully bounded by the merged child plans plus the downstream #120 issue body.

# Approval Notes

- This revision replaces the earlier parent-wide draft with a residual-parent-only artifact after merged child issues #119 and #122.
- `docs/issue-plans/TEMPLATE.md` now exists and governs this artifact.
- Child completion references for this revision are fixed: #119 was satisfied by PR #141 / commit `a647cb409f19c3ca2df8f0f24157dcefa8b70e17`, and #122 was satisfied by PR #140 / commit `984ad0e83b84d3eb376d1daf50ceb271f98079a6`.
- Planning review is still required before implementation starts, and the expected sequence after approval is residual #118 production cleanup first, then #120 regression coverage.
