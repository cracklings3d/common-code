---
issue: github.com/cracklings3d/common-code#126
title: Reconcile master with the accepted facade-first desktop boundary
status: approved
plan_status: approved
review_status: passed
source:
  - github.com/cracklings3d/common-code#126
  - controller-stage-c-brief
owner: architect
created_at: 2026-05-31
updated_at: 2026-05-31
approved_by: icy-green-cockroach
approved_at: 2026-05-29T00-00:00Z
review_artifact: 'C:\Users\The_u\.opencode\projects\github-com-cracklings3d-common-code\runs\canonical-issue-resolver-parallel\2026-05-29T00-00-00Z-run-01\reviews\issue-126\loop-2-stage-D.json'
related_branch: issue-126
related_pr: null
replaces: null
supersedes: []
change_scope:
  files:
    - docs/issue-plans/issue-126.md
    - apps/common_code_desktop/lib/main.dart
    - apps/common_code_desktop/lib/src/desktop_session_controller.dart
    - apps/common_code_desktop/lib/src/desktop_session_app_edge_composition.dart
    - apps/common_code_desktop/lib/src/desktop_session_runtime.dart
    - apps/common_code_desktop/lib/src/desktop_session_facade_adapters.dart
    - apps/common_code_desktop/test/widget_test.dart
    - apps/common_code_desktop/test/desktop_session_controller_test.dart
    - apps/common_code_desktop/test/desktop_session_app_edge_composition_test.dart
    - apps/common_code_desktop/test/desktop_session_runtime_test.dart
  directories:
    - apps/common_code_desktop/lib/src
    - apps/common_code_desktop/test
  modules:
    - apps/common_code_desktop/lib/main.dart::production bootstrap render path reads only controller-exposed presentation state
    - apps/common_code_desktop/lib/src/desktop_session_controller.dart::initialize refresh acknowledge and submit delegate through the application-facing desktop session facade path
    - apps/common_code_desktop/lib/src/desktop_session_app_edge_composition.dart::the only allowed concrete desktop composition seam for host persistence runtime and adapter wiring
    - apps/common_code_desktop/lib/src/desktop_session_runtime.dart::supporting lower-boundary runtime alignment only when required by the thinned controller path
    - apps/common_code_desktop/lib/src/desktop_session_facade_adapters.dart::supporting lower-boundary facade adapter alignment only when required by the thinned controller path
    - apps/common_code_desktop/test/widget_test.dart::current desktop production asset for bootstrap render refresh and submit behavior
    - apps/common_code_desktop/test/desktop_session_controller_test.dart::current desktop controller asset for thin delegation and presentation-state assertions
    - apps/common_code_desktop/test/desktop_session_app_edge_composition_test.dart::current desktop composition asset proving the seam remains the only concrete wiring location
    - apps/common_code_desktop/test/desktop_session_runtime_test.dart::current desktop lower-boundary regression asset kept aligned only if supporting seams move
  artifacts:
    - authoritative canonical tracked plan artifact at docs/issue-plans/issue-126.md on branch issue-126
    - thin desktop presentation surface that uses application-facing orchestration only
    - desktop composition seam retained as the only implementation-aware wiring path for this slice
    - focused desktop regression proof for bootstrap render refresh and submit behavior using the current desktop test assets
---

# Summary

Issue #126 is a narrow desktop-boundary reconciliation slice against current master, and this file at `docs/issue-plans/issue-126.md` is the authoritative canonical plan artifact for the branch/worktree `issue-126`. The current presentation-facing surface is still coupled to lower-layer runtime and model details: `desktop_session_controller.dart` imports `package:host_core/host_core.dart` and `package:common_code_persistence/common_code_persistence.dart`, while `main.dart` still walks session and turn structures directly to render the desktop flow. The intended outcome is to make `main.dart` and `desktop_session_controller.dart` consume only Application-facing orchestration/state for the current desktop client, while keeping concrete host/persistence/runtime wiring in `desktop_session_app_edge_composition.dart` and only the minimum necessary supporting lower-boundary files.

# Problem

Accepted ADR 0006 fixes the dependency direction as `Presentation -> Application -> Domain` and states that Presentation may depend only on Application-facing APIs and models needed to render and interact with a Client on a Platform. Current master does not yet match that boundary for this desktop slice:

- `apps/common_code_desktop/lib/src/desktop_session_controller.dart` still constructs its default path from `createDesktopSessionRuntime(...)` and directly imports `host_core`, `common_code_persistence`, and runtime-level desktop wiring.
- `apps/common_code_desktop/lib/main.dart` still renders by traversing session, turn, and notification structures directly in the presentation file instead of consuming a thinner controller-owned presentation shape.
- The lower-boundary runtime and composition files already exist, but reusable orchestration and concrete implementation wiring are not yet fully kept below the presentation-facing surface.

That leaves the accepted facade-first boundary only partially realized on current master and risks reopening the same desktop hotspot area unless this slice is kept precise.

# Acceptance Criteria

1. The in-scope presentation-facing desktop surface for this issue remains limited to `apps/common_code_desktop/lib/main.dart` and `apps/common_code_desktop/lib/src/desktop_session_controller.dart`.
2. Those two presentation-facing files consume only Application-facing orchestration and presentation state needed to render and interact with the current desktop client, consistent with ADR 0006.
3. `apps/common_code_desktop/lib/main.dart` and `apps/common_code_desktop/lib/src/desktop_session_controller.dart` no longer import `package:host_core/host_core.dart`.
4. `apps/common_code_desktop/lib/main.dart` and `apps/common_code_desktop/lib/src/desktop_session_controller.dart` no longer import `package:common_code_persistence/common_code_persistence.dart` implementation types for feature behavior.
5. Reusable orchestration and implementation-aware wiring for the current desktop flow live below the presentation boundary, with `apps/common_code_desktop/lib/src/desktop_session_app_edge_composition.dart` remaining the narrow concrete composition seam for this slice.
6. The minimum preserved-behavior verification still passes for the current desktop flow:
   - production bootstrap path renders a prompt thread conversation
   - refresh updates the rendered session through the controller
   - submitting text updates the rendered session snapshot

# In Scope

- Refactor `apps/common_code_desktop/lib/src/desktop_session_controller.dart` so its default desktop path is driven by Application-facing orchestration rather than direct runtime/host/persistence dependencies.
- Refactor `apps/common_code_desktop/lib/main.dart` so it renders controller-exposed presentation state instead of directly owning lower-layer session/turn/notification traversal.
- Keep or adjust `apps/common_code_desktop/lib/src/desktop_session_app_edge_composition.dart` as the only implementation-aware seam that assembles the default desktop facade/runtime wiring for this slice.
- Make only the narrow supporting changes in `desktop_session_runtime.dart` and `desktop_session_facade_adapters.dart` needed to keep lower-boundary wiring aligned after the surface is thinned.
- Update only the current desktop test assets already named in `change_scope` so they prove bootstrap/render, refresh, submit, controller delegation, and lower-boundary seam alignment.

# Out Of Scope

- Reopening ADR 0006 itself or relitigating the accepted layered constitution.
- Reopening already-landed work governed by #118, #119, #120, or #122.
- Broad package remapping, new package-boundary rules, or general cleanup beyond the desktop files listed in `change_scope`.
- New desktop features, new user-visible behavior, or redesign of the current desktop flow beyond what is necessary to satisfy the boundary.
- Any production change outside the listed desktop files unless plan review approves a narrow revision.
- Replacing the current desktop test assets with a broader regression matrix when the existing assets can prove the required behavior.

# Constraints

- Follow ADR 0006 exactly for this slice: the governing direction remains `Presentation -> Application -> Domain`.
- Treat ADR 0006 and the already-landed slices from #118, #119, #120, and #122 as fixed context for this plan; implementation may align to them but must not reopen, revise, or relitigate them.
- Keep the presentation-facing surface bounded to `main.dart` and `desktop_session_controller.dart`; do not spread new orchestration responsibilities into additional presentation files.
- Keep `desktop_session_app_edge_composition.dart` as the only allowed concrete composition seam for this slice; do not move host or persistence wiring back into the presentation-facing surface.
- Do not reintroduce `host_core` or `common_code_persistence` imports into `main.dart` or `desktop_session_controller.dart`.
- Keep the solution conservative: prefer the smallest refactor that routes the desktop surface through existing Application-facing behavior instead of widening into unrelated API redesign.
- Preserve the current desktop bootstrap render, refresh-driven session update, submit-driven session update, and acknowledgement behavior while moving orchestration below the boundary.

# Proposed Approach

1. Thin `DesktopSessionController` into the presentation bridge for the desktop slice by delegating initialize, refresh, acknowledge, and submit through the existing Application-facing desktop session facade path instead of directly constructing or importing host, persistence, or runtime implementation types.
2. Keep the default concrete wiring for that controller path inside `desktop_session_app_edge_composition.dart`, so production bootstrap still starts from the current desktop composition seam and that seam remains the only implementation-aware location.
3. Move any session-to-render shaping still owned by `main.dart` below the presentation boundary so the production bootstrap render path reads controller-exposed presentation state only.
4. Verify the same controller-owned presentation state updates on both refresh-driven and submit-driven session changes, without reintroducing lower-layer imports into the presentation-facing files.
5. Touch `desktop_session_runtime.dart` and `desktop_session_facade_adapters.dart` only if required to keep the lower-boundary facade/runtime path aligned, then update only the current desktop test assets named in `change_scope` to prove bootstrap render, refresh, submit, controller delegation, and composition-seam continuity.

# Impacted Areas

| Area | Why it is impacted |
| --- | --- |
| `apps/common_code_desktop/lib/main.dart` | The presentation file must stop owning lower-layer session rendering logic directly and instead render controller-exposed desktop presentation state. |
| `apps/common_code_desktop/lib/src/desktop_session_controller.dart` | This is the primary boundary fix: it must stop importing host/persistence/runtime implementation types and become a thin Application-facing presentation bridge. |
| `apps/common_code_desktop/lib/src/desktop_session_app_edge_composition.dart` | This file is the accepted narrow composition seam and must own the default concrete desktop wiring after the surface is thinned. |
| `apps/common_code_desktop/lib/src/desktop_session_runtime.dart` | It stays below the presentation boundary and may require narrow alignment changes if the controller no longer constructs/consumes it directly. |
| `apps/common_code_desktop/lib/src/desktop_session_facade_adapters.dart` | It stays below the presentation boundary and may require narrow alignment changes to preserve the existing desktop facade path under the composition seam. |
 | `apps/common_code_desktop/test/widget_test.dart` | Current production desktop test asset; it must keep proving bootstrap render plus refresh-driven and submit-driven session updates after the boundary refactor. |
 | `apps/common_code_desktop/test/desktop_session_controller_test.dart` | Current controller test asset; it must prove the controller remains thin and delegates through the Application-facing path instead of lower-layer runtime ownership. |
 | `apps/common_code_desktop/test/desktop_session_app_edge_composition_test.dart` | Current composition test asset; it must stay aligned with the accepted role of the composition seam as the only concrete wiring location. |
 | `apps/common_code_desktop/test/desktop_session_runtime_test.dart` | Current lower-boundary runtime asset; it must stay aligned only if runtime entrypoints or supporting wiring signatures change while preserving behavior. |

# Validation Plan

- `apps/common_code_desktop/test/widget_test.dart` remains the production behavior proof. From `apps/common_code_desktop/`, run `flutter test test/widget_test.dart` and keep these named checks passing:
  - `production bootstrap path renders a prompt thread conversation`
  - `refresh updates the rendered session through the controller`
  - `submitting text updates the rendered session snapshot`
- `apps/common_code_desktop/test/desktop_session_controller_test.dart` remains the controller-boundary proof. From `apps/common_code_desktop/`, run `flutter test test/desktop_session_controller_test.dart` and keep assertions concrete for initialize, refresh, acknowledge, and submit delegation through the Application-facing path.
- `apps/common_code_desktop/test/desktop_session_app_edge_composition_test.dart` remains the composition-seam proof. From `apps/common_code_desktop/`, run `flutter test test/desktop_session_app_edge_composition_test.dart` and verify the default composition seam still owns the concrete host/persistence/runtime wiring.
- `apps/common_code_desktop/test/desktop_session_runtime_test.dart` remains the supporting lower-boundary proof when touched. From `apps/common_code_desktop/`, run `flutter test test/desktop_session_runtime_test.dart` to verify any necessary runtime alignment change preserves current behavior.
- Reviewer source check for acceptance criteria 1 through 5: confirm `main.dart` and `desktop_session_controller.dart` no longer import `package:host_core/host_core.dart` or `package:common_code_persistence/common_code_persistence.dart`, and confirm reusable orchestration stays below the presentation boundary with `desktop_session_app_edge_composition.dart` as the only concrete composition seam.

# Risks

- If the refactor stops at `desktop_session_controller.dart` but leaves `main.dart` directly coupled to lower-layer session structures, the accepted boundary is still not fully satisfied.
- If the controller is thinned by adding new concrete wiring in the presentation surface instead of routing through `desktop_session_app_edge_composition.dart`, this slice will fail Acceptance Criterion 5.
- If the implementation widens into broader package or architecture work, it will reopen already-landed decisions from #118, #119, #120, or #122.

# Open Questions

- None. This plan intentionally chooses the narrowest path: thin the presentation-facing surface onto existing Application-facing desktop orchestration and keep concrete wiring in the accepted composition seam.

# Approval Notes

- This plan is bounded to the issue contract that already passed Stage B and uses current master as the baseline.
- It does not reopen ADR 0006 or previously landed work from #118, #119, #120, or #122.
- `docs/issue-plans/issue-126.md` is the canonical tracked plan artifact governing implementation and Stage D review for issue #126 on branch `issue-126` in this worktree.
- The implementation reviewer should reject any solution that removes the forbidden imports but leaves reusable orchestration or concrete desktop wiring inside the presentation-facing surface.
