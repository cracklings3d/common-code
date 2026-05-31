---
issue: github.com/cracklings3d/common-code#119
title: Move the current in-memory HostGateway and SessionObservation implementations into `packages/host_in_memory`
status: draft
plan_status: proposed
review_status: pending
source:
  - github.com/cracklings3d/common-code#119
  - controller-stage-c-brief
owner: architect
created_at: 2026-05-31
updated_at: 2026-05-31
approved_by: null
approved_at: null
review_artifact: null
related_branch: issue-119-move-the-current-in-memory-hostgateway-and-sessionobservation-implementations-into-packages-host_in_memory
related_pr: null
replaces: null
supersedes: []
change_scope:
  files:
    - docs/issue-plans/issue-119.md
    - apps/common_code_desktop/lib/src/desktop_session_facade_adapters.dart
    - apps/common_code_desktop/lib/src/desktop_session_app_edge_composition.dart
    - apps/common_code_desktop/test/desktop_session_app_edge_composition_test.dart
    - packages/host_in_memory/pubspec.yaml
    - packages/host_in_memory/lib/host_in_memory.dart
    - packages/host_in_memory/lib/src/in_memory_session_observation.dart
    - packages/host_in_memory/lib/src/in_memory_host_gateway.dart
  directories:
    - docs/issue-plans
    - apps/common_code_desktop/lib/src
    - apps/common_code_desktop/test
    - packages/host_in_memory
    - packages/host_in_memory/lib
    - packages/host_in_memory/lib/src
  modules:
    - apps/common_code_desktop/lib/src/desktop_session_facade_adapters.dart::DesktopSessionMutationPort
    - apps/common_code_desktop/lib/src/desktop_session_facade_adapters.dart::HostGatewayDesktopSessionMutationPort
    - apps/common_code_desktop/lib/src/desktop_session_facade_adapters.dart::DesktopSessionBootstrapDriver
    - apps/common_code_desktop/lib/src/desktop_session_app_edge_composition.dart::createDesktopSessionFacade
    - packages/host_in_memory/lib/src/in_memory_session_observation.dart::HostServiceSessionObservation
    - packages/host_in_memory/lib/src/in_memory_session_observation.dart::PersistingHostServiceSessionObservation
    - packages/host_in_memory/lib/src/in_memory_host_gateway.dart::PersistingHostServiceSessionMutations
  artifacts:
    - docs/issue-plans/issue-119.md
    - package:host_in_memory/host_in_memory.dart::HostServiceSessionObservation
    - package:host_in_memory/host_in_memory.dart::PersistingHostServiceSessionObservation
    - package:host_in_memory/host_in_memory.dart::PersistingHostServiceSessionMutations
    - apps/common_code_desktop/test/desktop_session_app_edge_composition_test.dart::createDesktopSessionFacade default-path regression coverage
---

# Summary

Issue #119 is a bounded refactor slice under parent #118: move the current in-memory `HostGateway` and `CommonCodeSessionObservation` concrete behaviors out of desktop-local adapter code and into `packages/host_in_memory`, while preserving the current desktop/in-memory default behavior. The governing bridge decision for this slice is now fixed: keep `DesktopSessionBootstrapDriver` on `DesktopSessionMutationPort` and satisfy that port with a thin desktop-local `HostGatewayDesktopSessionMutationPort` delegator, so `packages/host_in_memory` becomes the sole owner of the moved concrete behaviors without widening contract changes.

# Problem

The current in-memory observation and gateway behavior is still owned by desktop-local code even though the default concrete host implementation already lives in `packages/host_in_memory`. Specifically, `apps/common_code_desktop/lib/src/desktop_session_facade_adapters.dart` currently defines:

- `HostServiceSessionObservation` for direct `HostService.watchSession(...)` observation.
- `PersistingHostServiceSessionObservation` for watch-driven persistence side effects.
- `PersistingHostServiceSessionMutations` for `HostGateway` turn submission plus persistence continuation, while also bridging the desktop-local `DesktopSessionMutationPort`.

That keeps concrete in-memory behavior coupled to the desktop adapter layer and obscures the intended package ownership boundary. `DesktopSessionBootstrapDriver` currently depends materially on the desktop-local `DesktopSessionMutationPort`, so this plan must explicitly govern how the move completes without reopening contract design: relocate the concrete in-memory behavior into `packages/host_in_memory`, keep the driver contract as-is for #119, and leave behind only a delegation-only bridge in desktop-local code. The move must stay narrow and must not broaden into parent #118 boundary work, downstream issue #120, or any OpenCode adapter-chain redesign.

# Acceptance Criteria

1. The behavior currently implemented by `PersistingHostServiceSessionMutations` as the default in-memory `HostGateway` is owned by `packages/host_in_memory`.
2. The behaviors currently implemented by `HostServiceSessionObservation` and `PersistingHostServiceSessionObservation` as the default in-memory `CommonCodeSessionObservation` adapters are owned by `packages/host_in_memory`.
3. `apps/common_code_desktop/lib/src/desktop_session_facade_adapters.dart` retains only `DesktopSessionMutationPort`, `HostGatewayDesktopSessionMutationPort`, and `DesktopSessionBootstrapDriver`; `HostServiceSessionObservation`, `PersistingHostServiceSessionObservation`, and `PersistingHostServiceSessionMutations` no longer live in that file.
4. `createDesktopSessionFacade(...)` preserves the current restore/watch/persist/submit/acknowledge behavior for the desktop in-memory default path.

# In Scope

- Add the minimal `host_in_memory` package-owned adapters needed to house the current in-memory `CommonCodeSessionObservation` and `HostGateway` behavior.
- Add the package dependency/export wiring required for `host_in_memory` to implement `CommonCodeSessionObservation` and `HostGateway`.
- Rewire the desktop default composition path to consume the package-owned adapters instead of the current desktop-local concrete classes.
- Leave `DesktopSessionBootstrapDriver` on `DesktopSessionMutationPort` and add only a thin desktop-local `HostGatewayDesktopSessionMutationPort` delegator for that bridge.
- Update focused desktop composition coverage to prove observable behavior is preserved after the ownership move.

# Out Of Scope

- The broader parent #118 package-boundary cleanup beyond this specific move.
- Issue #120 or any downstream OpenCode/external-host adapter-chain work.
- Changes to `CommonCodeSessionFacade`, `HostGateway`, `CommonCodeSessionObservation`, `HostService`, or identity-context contracts.
- Replacing `InMemoryHostAdapter` or redesigning durable persistence semantics.
- Moving `DesktopSessionBootstrapDriver` itself out of desktop-local code.
- Rewriting `DesktopSessionBootstrapDriver` to depend directly on `HostGateway` for this slice.

# Constraints

- Keep #119 serialized alone even though #122 is complete; do not widen the hotspot beyond the files listed in this plan without review approval.
- Preserve current public behavior and current desktop/in-memory defaults.
- Minimize change surface: prefer extraction/rewiring over redesign.
- The bridge decision is authoritative for #119: `DesktopSessionBootstrapDriver` stays on `DesktopSessionMutationPort`; desktop-local code may satisfy that interface only through a thin `HostGatewayDesktopSessionMutationPort` delegator and must not continue to own the in-memory business behavior.
- `packages/host_in_memory` currently depends on `common_code_domain` and `host_core`; implementation must add only the minimal additional dependency needed for the moved application-port adapters.

# Proposed Approach

1. Move `HostServiceSessionObservation` and `PersistingHostServiceSessionObservation` out of `apps/common_code_desktop/lib/src/desktop_session_facade_adapters.dart` into `packages/host_in_memory/lib/src/in_memory_session_observation.dart`, keeping the direct `HostService.watchSession(...)` wrapper and the persistence-decorating observation behavior together under package ownership.
2. Move `PersistingHostServiceSessionMutations` out of `apps/common_code_desktop/lib/src/desktop_session_facade_adapters.dart` into `packages/host_in_memory/lib/src/in_memory_host_gateway.dart` as the package-owned default `HostGateway` implementation, preserving the current persistence continuation behavior and dropping the desktop-local `DesktopSessionMutationPort` implementation from that moved class.
3. Leave `apps/common_code_desktop/lib/src/desktop_session_facade_adapters.dart` with exactly three desktop-local types: `DesktopSessionMutationPort`, `HostGatewayDesktopSessionMutationPort`, and `DesktopSessionBootstrapDriver`. The new bridge is delegation-only: `acknowledgeNotification(...)` forwards directly, and `submitTurnForClient(...)` translates `attachedClientId` into `Client(id: attachedClientId)` before forwarding to the package-owned `HostGateway`.
4. Update `packages/host_in_memory/pubspec.yaml` and `packages/host_in_memory/lib/host_in_memory.dart` so the moved adapters can implement/export the `common_code_application` ports cleanly.
5. Update `apps/common_code_desktop/lib/src/desktop_session_app_edge_composition.dart` so the default path instantiates the host_in_memory-owned observation and gateway adapters, then wraps the gateway in `HostGatewayDesktopSessionMutationPort` only for `DesktopSessionBootstrapDriver` construction.
6. Update focused composition tests in `apps/common_code_desktop/test/desktop_session_app_edge_composition_test.dart` so the default desktop path still proves restore, watch-triggered persistence, submit, and acknowledge behavior after the ownership move.

# Impacted Areas

| Area | Why it is impacted |
| --- | --- |
| `apps/common_code_desktop/lib/src/desktop_session_facade_adapters.dart` | Current concrete implementations live here today. The end-state for this file is explicit: only `DesktopSessionMutationPort`, `HostGatewayDesktopSessionMutationPort`, and `DesktopSessionBootstrapDriver` remain; `HostServiceSessionObservation`, `PersistingHostServiceSessionObservation`, and `PersistingHostServiceSessionMutations` leave the file. |
| `apps/common_code_desktop/lib/src/desktop_session_app_edge_composition.dart` | The default facade composition currently constructs the desktop-local concrete observation/gateway adapters and must be rewired to construct package-owned adapters plus the thin `HostGatewayDesktopSessionMutationPort` bridge for the driver. |
| `packages/host_in_memory/pubspec.yaml` | The package needs the minimal dependency wiring required to implement `CommonCodeSessionObservation` and `HostGateway`. |
| `packages/host_in_memory/lib/src/in_memory_session_observation.dart` | Becomes the concrete home of `HostServiceSessionObservation` and `PersistingHostServiceSessionObservation`. |
| `packages/host_in_memory/lib/src/in_memory_host_gateway.dart` | Becomes the concrete home of `PersistingHostServiceSessionMutations` as the package-owned default `HostGateway`. |
| `packages/host_in_memory/lib/host_in_memory.dart` | Must export `HostServiceSessionObservation`, `PersistingHostServiceSessionObservation`, and `PersistingHostServiceSessionMutations` for desktop default composition. |
| `apps/common_code_desktop/test/desktop_session_app_edge_composition_test.dart` | Existing coverage already exercises the default desktop composition path and should remain the focused regression proof for preserved default behavior after the ownership move. |

# Validation Plan

- Run the focused desktop composition tests in `apps/common_code_desktop/test/desktop_session_app_edge_composition_test.dart` and keep them green for the default restore/watch/persist/submit/acknowledge path.
- Confirm the default `createDesktopSessionFacade(...)` path now composes the package-owned `HostServiceSessionObservation`, `PersistingHostServiceSessionObservation`, and `PersistingHostServiceSessionMutations`, with `HostGatewayDesktopSessionMutationPort` used only as the thin driver bridge.
- Keep the validation claim narrow: this slice proves preserved default desktop/in-memory behavior only, not every custom `driver` / `observation` / `hostGateway` override combination unless a targeted override-path test is added separately.
- Keep validation scoped to this ownership move only; do not absorb parent #118 or downstream adapter-chain testing.

# Risks

- If `HostGatewayDesktopSessionMutationPort` grows beyond argument translation/delegation, issue #119 will not actually complete the ownership move.
- If the watch-persistence decorator and mutation-persistence behavior diverge during extraction, desktop in-memory behavior could change even if compilation still succeeds.
- If `host_in_memory` export/dependency wiring is incomplete, the desktop composition path could compile against stale desktop-local classes or fail to build.

# Open Questions

- None. The current concrete implementation points requiring the move are now identified in the synced workspace.

# Approval Notes

- Stage B review passed this issue as a narrow, traceable refactor slice ready for planning, with one explicit planner task: confirm the current concrete implementation points before writing the plan.
- That confirmation is now complete: the concrete implementations live in `apps/common_code_desktop/lib/src/desktop_session_facade_adapters.dart`, and the default desktop composition that consumes them lives in `apps/common_code_desktop/lib/src/desktop_session_app_edge_composition.dart`.
- This revision resolves the previously open bridge choice authoritatively: keep `DesktopSessionBootstrapDriver` on `DesktopSessionMutationPort` and use a thin `HostGatewayDesktopSessionMutationPort` delegator rather than rewriting the driver against `HostGateway` in #119.
- This plan intentionally stays bounded to the ownership move into `packages/host_in_memory`; it is not authority to reopen the broader #118 boundary-placement work, issue #120, or the OpenCode adapter chain.
