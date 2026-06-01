---
issue: github.com/cracklings3d/common-code#125
title: Remove the remaining live `host_core` seam from the active desktop/in-memory path
status: approved
plan_status: approved
review_status: passed
source:
  - github.com/cracklings3d/common-code#125
  - controller-stage-c-brief
owner: architect
created_at: 2026-06-01
updated_at: 2026-06-01
approved_by: public-aqua-catshark
approved_at: 2026-05-29T00-00:00Z
review_artifact: 'C:\Users\The_u\.opencode\projects\github-com-cracklings3d-common-code\runs\canonical-issue-resolver-parallel\2026-05-29T00-00-00Z-run-01\reviews\issue-125\loop-1-stage-D.json'
related_branch: issue-125
related_pr: null
replaces: null
supersedes: []
change_scope:
  files:
    - docs/issue-plans/issue-125.md
    - packages/common_code_application/lib/common_code_application.dart
    - packages/common_code_application/lib/src/host_service.dart
    - packages/host_in_memory/pubspec.yaml
    - packages/host_in_memory/lib/src/in_memory_host_adapter.dart
    - packages/host_in_memory/lib/src/in_memory_host_gateway.dart
    - packages/host_in_memory/lib/src/in_memory_host_service.dart
    - packages/host_in_memory/lib/src/in_memory_session_observation.dart
    - apps/common_code_desktop/pubspec.yaml
    - apps/common_code_desktop/lib/src/desktop_session_runtime.dart
    - apps/common_code_desktop/lib/src/desktop_session_facade_adapters.dart
    - apps/common_code_desktop/lib/src/desktop_session_app_edge_composition.dart
    - apps/common_code_desktop/test/desktop_session_runtime_test.dart
    - apps/common_code_desktop/test/desktop_session_persistence_test.dart
    - apps/common_code_desktop/test/desktop_session_app_edge_composition_test.dart
    - packages/host_core/lib/host_core.dart
    - packages/host_core/lib/src/host_service.dart
    - packages/host_core/test/host_core_test.dart
  directories:
    - packages/common_code_application/lib
    - packages/host_in_memory
    - apps/common_code_desktop
    - packages/host_core
  modules:
    - packages/common_code_application/lib/src/host_service.dart::Application-owned HostService contract for create restore read submit acknowledge and watch operations used by the active desktop/in-memory path
    - packages/host_in_memory/lib/src/in_memory_host_adapter.dart::in-memory adapter implements the Application-owned host contract directly with no host_core import
    - packages/host_in_memory/lib/src/in_memory_host_service.dart::factory-backed in-memory host service implements the same Application-owned contract directly with no host_core import
    - packages/host_in_memory/lib/src/in_memory_host_gateway.dart::mutation adapter depends on the Application-owned host contract rather than host_core
    - packages/host_in_memory/lib/src/in_memory_session_observation.dart::observation adapters depend on the Application-owned host contract rather than host_core
    - apps/common_code_desktop/lib/src/desktop_session_runtime.dart::desktop runtime accepts only Application-owned or adapter-owned host contracts on the active desktop/in-memory path
    - apps/common_code_desktop/lib/src/desktop_session_facade_adapters.dart::desktop bootstrap driver bridge and mutation port remain below presentation without importing host_core
    - apps/common_code_desktop/lib/src/desktop_session_app_edge_composition.dart::default desktop/in-memory composition wires InMemoryHostAdapter through Application-owned contracts with no host_core dependency
    - apps/common_code_desktop/test/desktop_session_app_edge_composition_test.dart::source-structure regression guard for the live desktop/in-memory path and its direct dependency declarations
    - apps/common_code_desktop/test/desktop_session_runtime_test.dart::runtime regression coverage continues to prove current durable bootstrap and watch behavior after the contract ownership move
    - apps/common_code_desktop/test/desktop_session_persistence_test.dart::restart and persistence regression coverage continues to prove the same desktop/in-memory behavior after host_core removal
    - packages/host_core/lib/host_core.dart::passive compatibility re-export only if required for non-live callers, never the active desktop/in-memory path
  artifacts:
    - authoritative canonical tracked plan artifact at docs/issue-plans/issue-125.md on branch issue-125
    - active desktop/in-memory source path on master baseline 0ca94fa79636eebf5f29cb03b34b1711121dfe07 with no package:host_core/host_core.dart imports
    - dependency declarations for apps/common_code_desktop and packages/host_in_memory with no live host_core dependency
    - source-structure regression guard that fails if host_core is reintroduced into the active desktop/in-memory path
---

# Summary

This plan governs branch/worktree `issue-125` on top of `master` baseline `0ca94fa79636eebf5f29cb03b34b1711121dfe07`. On current master, the remaining live `host_core` seam in the active desktop/in-memory path is not presentation code from #126; it is the continued ownership of the `HostService` contract and the resulting `host_core` imports and dependency declarations in the desktop runtime/composition layer and `packages/host_in_memory`. The intended outcome is to make the live desktop/in-memory path depend only on Application-owned contracts and adapter implementations, while preserving current durable bootstrap, watch, submit, acknowledge, and restart behavior.

# Problem

Current master still routes the active desktop/in-memory path through `host_core` for the `HostService` contract:

- `apps/common_code_desktop/lib/src/desktop_session_runtime.dart`
- `apps/common_code_desktop/lib/src/desktop_session_facade_adapters.dart`
- `apps/common_code_desktop/lib/src/desktop_session_app_edge_composition.dart`
- `packages/host_in_memory/lib/src/in_memory_host_adapter.dart`
- `packages/host_in_memory/lib/src/in_memory_host_gateway.dart`
- `packages/host_in_memory/lib/src/in_memory_host_service.dart`
- `packages/host_in_memory/lib/src/in_memory_session_observation.dart`

The seam is now narrow and concrete: `packages/host_core/lib/host_core.dart` exports `src/host_service.dart` plus `HostServiceFailure` aliases, while `common_code_application` already owns adjacent application-facing seams such as `HostGateway`, `CommonCodeSessionObservation`, `CommonCodeSessionBootstrapPort`, and `HostServiceFailure`. `apps/common_code_desktop/pubspec.yaml` and `packages/host_in_memory/pubspec.yaml` still declare `host_core` as a direct dependency, so the active desktop/in-memory path remains live on the transitional package even though the default runtime is already `InMemoryHostAdapter`. That leaves a residual architecture gap under ADR 0006 and a clear reintroduction risk unless the active path and its dependency manifests stop referencing `host_core` altogether.

# Acceptance Criteria

- The active desktop/in-memory production path no longer imports `package:host_core/host_core.dart` in `desktop_session_runtime.dart`, `desktop_session_facade_adapters.dart`, `desktop_session_app_edge_composition.dart`, or the `packages/host_in_memory` sources they compose.
- `apps/common_code_desktop/pubspec.yaml` and `packages/host_in_memory/pubspec.yaml` no longer declare `host_core` as a direct dependency for the live desktop/in-memory path.
- The host contract used by the active desktop/in-memory path is owned by `common_code_application`, and `host_in_memory` implements that contract directly.
- No new compatibility seam or renamed package recreates `host_core` ownership under another name; if `packages/host_core` remains for dormant compatibility, it is passive only and not part of the active desktop/in-memory path.
- Current desktop runtime, persistence, and app-edge composition behavior remains intact for initialize, refresh/watch, submit, acknowledge, and durable restart continuity.
- Regression coverage includes a source-structure or manifest guard that fails if `host_core` is reintroduced into the active desktop/in-memory path.

# In Scope

- Introduce the Application-owned `HostService` contract in `packages/common_code_application` and export it from the package’s public surface.
- Rewire `packages/host_in_memory` implementations to depend on that Application-owned contract directly rather than importing `host_core`.
- Rewire `apps/common_code_desktop` runtime/composition files and dependency declarations so the default desktop/in-memory path no longer depends on `host_core`.
- Keep `packages/host_core` only as a passive compatibility surface if compile-safe repository continuity still requires it after the live path has moved off the seam.
- Update the existing desktop tests named in `change_scope` to preserve current behavior and add a concrete regression guard against reintroducing `host_core` into the active path.

# Out Of Scope

- Reopening #126’s broader facade-first presentation cleanup, including `apps/common_code_desktop/lib/main.dart` and `apps/common_code_desktop/lib/src/desktop_session_controller.dart`.
- New desktop features, presentation redesign, or any change to current user-visible desktop behavior beyond what is required to remove the live seam.
- Redesigning durable persistence semantics, turn execution behavior, or notification semantics.
- Broader package-boundary cleanup across unrelated packages or deletion of the `host_core` package from the repository if dormant compatibility still exists outside the active path.
- Reopening ADR 0006, #118, #119, #120, #122, or #126 decisions.

# Constraints

- Follow ADR 0006 exactly: the active desktop path must stay on Application-facing APIs and must not regain lower-layer ownership in presentation.
- Keep this slice limited to residual `host_core` seam removal on the active desktop/in-memory path; do not broaden into already-landed presentation-boundary work from #126.
- Do not duplicate `HostService` into competing interfaces. The contract must have one real owner in `common_code_application`; any remaining `host_core` surface must only forward to that owner.
- Do not introduce a new compatibility package, alias layer, or renamed seam that merely recreates `host_core` under another name.
- Preserve current default composition through `InMemoryHostAdapter`, `CommonCodeSessionBootstrapPortAdapter`, runtime watch behavior, persistence continuation, and durable restart coverage.
- Keep revalidation explicit: this plan is written against `master` at `0ca94fa79636eebf5f29cb03b34b1711121dfe07` and must be revalidated immediately before implementation if `master` moves.

# Proposed Approach

1. Make `common_code_application` the real owner of the host-service contract by adding/exporting `HostService` alongside the already-Application-owned `HostGateway`, `CommonCodeSessionObservation`, bootstrap port, and failure types.
2. Update `packages/host_in_memory` so `InMemoryHostAdapter`, the factory-backed in-memory host service, the mutation adapter, and the observation adapters import the Application-owned `HostService` directly and no longer depend on `host_core` in code or `pubspec.yaml`.
3. Update `apps/common_code_desktop/lib/src/desktop_session_runtime.dart`, `desktop_session_facade_adapters.dart`, and `desktop_session_app_edge_composition.dart` plus `apps/common_code_desktop/pubspec.yaml` so the live desktop/in-memory composition uses the Application-owned contract directly while preserving the current `InMemoryHostAdapter` wiring and durable-local bootstrap flow.
4. If repository continuity requires `packages/host_core` to remain, reduce it to a passive compatibility export of the Application-owned contract only; it must not remain a live dependency of the active desktop/in-memory path and it must not grow a replacement compatibility seam.
5. Strengthen the existing desktop regression assets so behavior stays green and so at least one source-structure/manifests check fails if `package:host_core/host_core.dart` or a direct `host_core:` dependency entry returns to the active desktop/in-memory files.

# Impacted Areas

| Area | Why it is impacted |
| --- | --- |
| `packages/common_code_application/lib/src/host_service.dart` | This is the narrow missing owner for the remaining live seam; `HostService` must become Application-owned here. |
| `packages/common_code_application/lib/common_code_application.dart` | The Application package must publicly export the moved contract so the active path stops importing `host_core`. |
| `packages/host_in_memory/pubspec.yaml` | The adapter package currently declares `host_core`; that direct dependency must leave the live path. |
| `packages/host_in_memory/lib/src/in_memory_host_adapter.dart` | Default in-memory adapter currently imports `host_core` for `HostService`; the live contract import must move. |
| `packages/host_in_memory/lib/src/in_memory_host_service.dart` | The factory-backed in-memory service uses the same contract and must move with it. |
| `packages/host_in_memory/lib/src/in_memory_host_gateway.dart` | The gateway adapter currently depends on `HostService` through `host_core`; it must depend on the Application-owned contract directly. |
| `packages/host_in_memory/lib/src/in_memory_session_observation.dart` | The observation adapters still import `host_core`; they are part of the active path and must move off it. |
| `apps/common_code_desktop/pubspec.yaml` | The active desktop app currently declares `host_core` directly; that live dependency must be removed. |
| `apps/common_code_desktop/lib/src/desktop_session_runtime.dart` | Runtime still types its injected service through `host_core`; this is a live remaining seam in the active desktop/in-memory path. |
| `apps/common_code_desktop/lib/src/desktop_session_facade_adapters.dart` | The desktop bootstrap driver bridge still imports `host_core`; it must remain below presentation but stop depending on the transitional package. |
| `apps/common_code_desktop/lib/src/desktop_session_app_edge_composition.dart` | The default desktop/in-memory composition still imports `host_core` for `HostService` typing while wiring `InMemoryHostAdapter`; this is the live path to fix. |
| `apps/common_code_desktop/test/desktop_session_runtime_test.dart` | Current runtime regression asset must keep proving durable bootstrap and watch behavior after the contract ownership move. |
| `apps/common_code_desktop/test/desktop_session_persistence_test.dart` | Current persistence/restart regression asset must keep proving restart continuity after the seam removal. |
| `apps/common_code_desktop/test/desktop_session_app_edge_composition_test.dart` | Best existing location for a source-structure and manifest guard proving the default desktop/in-memory path no longer depends on `host_core`. |
| `packages/host_core/lib/host_core.dart` and `packages/host_core/lib/src/host_service.dart` | Only impacted if needed to keep dormant compatibility compiling after ownership moves; they are not allowed to remain part of the active path. |

# Validation Plan

- From `apps/common_code_desktop/`, run `flutter test test/desktop_session_runtime_test.dart` and keep the current initialize, refresh/watch, submit, acknowledge, and durable bootstrap behavior green.
- From `apps/common_code_desktop/`, run `flutter test test/desktop_session_persistence_test.dart` and keep the current durable restore, notification replay, acknowledgement persistence, and restart continuity behavior green.
- From `apps/common_code_desktop/`, run `flutter test test/desktop_session_app_edge_composition_test.dart` and extend the existing source-structure coverage so it checks the live desktop/in-memory files and their direct `pubspec.yaml` manifests for the absence of `package:host_core/host_core.dart` imports and `host_core:` dependency entries.
- Reviewer source check: confirm `desktop_session_runtime.dart`, `desktop_session_facade_adapters.dart`, `desktop_session_app_edge_composition.dart`, `packages/host_in_memory/lib/src/*.dart`, `apps/common_code_desktop/pubspec.yaml`, and `packages/host_in_memory/pubspec.yaml` no longer reference `host_core`.
- If `packages/host_core` is touched for passive compatibility only, run `dart test packages/host_core/test/host_core_test.dart` to verify compatibility still resolves without restoring active desktop/in-memory callers.

# Risks

- If `HostService` is copied instead of moved to a single Application-owned contract, the codebase can end up with incompatible parallel interfaces even if imports compile locally.
- If code imports are removed but `pubspec.yaml` entries are left behind, the active path still depends on `host_core` and the issue is only cosmetically fixed.
- If the change drifts into `main.dart`, `desktop_session_controller.dart`, or other broader facade-first work, it reopens #126 instead of finishing the residual seam.
- If compatibility is preserved by inventing a renamed shim rather than by making `common_code_application` the owner, the implementation will fail the issue contract.

# Open Questions

- None. The current code scan already identifies the remaining live seam as `HostService` ownership/import flow through the desktop runtime/composition files and `packages/host_in_memory`, not unresolved presentation-boundary work.

# Approval Notes

- This plan is intentionally narrower than #126: it does not authorize new presentation-surface work.
- The current master scan shows the remaining live `host_core` seam only in app-edge/runtime and `host_in_memory` files plus direct dependency manifests; that is the full target of this slice.
- `docs/issue-plans/issue-125.md` is the canonical tracked plan artifact for issue #125 on branch/worktree `issue-125`.
- Downstream implementation and review should reject any solution that merely renames the seam, leaves `host_core` in the active path’s dependency manifests, or broadens into unrelated cleanup.
