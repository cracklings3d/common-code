---
issue: github.com/cracklings3d/common-code#122
title: Pass desktop identity context through Application-owned inputs instead of hardcoded runtime identity
status: draft
plan_status: proposed
review_status: pending
source:
  - github.com/cracklings3d/common-code#122
  - controller-stage-c-brief
owner: architect
created_at: 2026-05-30
updated_at: 2026-05-30
approved_by: null
approved_at: null
review_artifact: null
related_branch: issue-122
related_pr: null
replaces: null
supersedes: []
change_scope:
  files:
    - docs/issue-plans/issue-122.md
    - apps/common_code_desktop/lib/src/desktop_session_runtime.dart
    - apps/common_code_desktop/lib/src/desktop_session_facade_adapters.dart
    - apps/common_code_desktop/lib/src/desktop_session_app_edge_composition.dart
    - packages/common_code_application/lib/src/common_code_session_bootstrap.dart
    - apps/common_code_desktop/test/desktop_session_runtime_test.dart
    - apps/common_code_desktop/test/desktop_session_app_edge_composition_test.dart
    - apps/common_code_desktop/test/desktop_session_controller_test.dart
  directories:
    - docs/issue-plans
    - apps/common_code_desktop/lib/src
    - apps/common_code_desktop/test
    - packages/common_code_application/lib/src
  modules:
    - common_code_application CommonCodeSessionBootstrapRequest carrier extension for desktop identity plus attached-client context
    - common_code_desktop runtime and default facade bootstrap alignment on the shared bootstrap request path
    - focused desktop regression coverage for initialize refresh watch bootstrap and submit-turn delegation
  artifacts:
    - docs/issue-plans/issue-122.md
    - shared CommonCodeSessionBootstrapRequest-based desktop identity-context wiring for runtime and default facade bootstrap
    - focused regression checks for initialize refresh _startSessionWatch _performStartSessionWatch _ensureSessionContext _bootstrapIfNeeded and submitTurn
---

# Summary

Issue #122 is the identity-context sub-slice of parent #118. The current desktop path still hardcodes runtime identity in `HostDesktopSessionRuntime`, so this revision fixes the plan on the smallest existing Application-owned carrier: extend `CommonCodeSessionBootstrapRequest` to carry desktop identity plus attached-client context, then reuse that carrier across the live runtime bootstrap/watch path and the default facade bootstrap path. This slice remains serialized ahead of #119 and does not reopen the broader desktop port-placement work.

# Problem

The current desktop runtime constructs a fixed `Identity(id: desktopSessionRuntimeIdentityId)` inside `apps/common_code_desktop/lib/src/desktop_session_runtime.dart` and then reuses that cached value during bootstrap/watch setup and command submission. That violates the accepted direction that identity context is an Application-owned contract concern supplied from the outer desktop edge, and it leaves the current desktop flow coupled to a hardcoded runtime identity instead of an explicit input path.

# Acceptance Criteria

1. `CommonCodeSessionBootstrapRequest` is the explicit Application-owned carrier extended for this slice, and it carries the desktop identity plus attached-client context needed by the live desktop runtime/bootstrap path.
2. `HostDesktopSessionRuntime` stops constructing `const Identity(id: desktopSessionRuntimeIdentityId)` inside `_ensureSessionContext()` and instead consumes the carrier-provided identity/context only within the in-scope runtime methods: `initialize()`, `refresh()`, `_startSessionWatch()`, `_performStartSessionWatch()`, `_ensureSessionContext()`, `_bootstrapIfNeeded()`, and `submitTurn()`.
3. `DesktopSessionBootstrapDriver.ensureSession()` and the default desktop composition path use the same extended `CommonCodeSessionBootstrapRequest` so the live runtime path and default facade bootstrap path stay aligned.
4. `CommonCodeSessionFacade` and `HostGateway` public surfaces stay fixed for #122; submit-turn continues to use the existing facade/gateway contracts, with desktop composition sourcing the attached-client value from the same carrier rather than broadening the application API.
5. Focused regression coverage proves the desktop initialize/refresh/watch path and submit-turn path still work after the identity-input change, without reopening parent #118 placement work or #119 package-move work.

# In Scope

- `packages/common_code_application/lib/src/common_code_session_bootstrap.dart` to extend `CommonCodeSessionBootstrapRequest` as the single Application-owned carrier for desktop identity plus attached-client context.
- `apps/common_code_desktop/lib/src/desktop_session_runtime.dart` only for the hardcoded identity removal and the cached session-context path used by `initialize()`, `refresh()`, `_startSessionWatch()`, `_performStartSessionWatch()`, `_ensureSessionContext()`, `_bootstrapIfNeeded()`, and `submitTurn()`.
- `apps/common_code_desktop/lib/src/desktop_session_facade_adapters.dart` only for keeping `DesktopSessionBootstrapDriver.ensureSession()` aligned with the same extended bootstrap request used by the runtime path.
- `apps/common_code_desktop/lib/src/desktop_session_app_edge_composition.dart` only for constructing and threading the shared bootstrap request through the existing desktop runtime and default facade bootstrap entry points.
- Focused updates to `apps/common_code_desktop/test/desktop_session_runtime_test.dart`, `apps/common_code_desktop/test/desktop_session_app_edge_composition_test.dart`, and `apps/common_code_desktop/test/desktop_session_controller_test.dart` to verify the in-scope runtime/bootstrap and submit-turn paths.

# Out Of Scope

- The broader parent #118 desktop port-placement/package-ownership effort.
- Issue #119's in-memory host or package-move work.
- Authentication, authorization, user-model expansion, or any broader identity-system redesign.
- OpenCode-specific identity remapping, transport/IPC/trust-boundary work, or package-map changes.
- New runtime flows beyond the current desktop bootstrap/watch path and current submit-turn command path.
- Any public-surface redesign of `CommonCodeSessionFacade` or `HostGateway` for this slice.

# Constraints

- Keep the slice aligned with ADR 0006 and ADR 0007: Application owns the contract/input concern, and the desktop edge provides the concrete context without leaking infrastructure vocabulary upward.
- Treat issue #122 as the identity-context sub-slice under #118 only; do not use this plan to reopen the full parent refactor.
- Prefer the smallest extension of existing Application-owned inputs over introducing a new subsystem, package, or architecture artifact; for this revision that carrier is `CommonCodeSessionBootstrapRequest`.
- Keep hotspot overlap conservative: serialize implementation of #122 away from #118 and #119 because they touch the same desktop runtime/application bootstrap area.
- Use current master as the planning baseline and keep the final implementation change surface inside the listed files unless plan review explicitly approves a narrow expansion.
- Keep `CommonCodeSessionFacade` and `HostGateway` contract surfaces fixed for #122; any change to those application APIs is out of scope unless a later issue explicitly authorizes it.
- Keep implementation explicitly bounded to the current live methods `initialize()`, `refresh()`, `_startSessionWatch()`, `_performStartSessionWatch()`, `_ensureSessionContext()`, `_bootstrapIfNeeded()`, and `submitTurn()`, plus the matching default facade bootstrap entrypoint `DesktopSessionBootstrapDriver.ensureSession()`.

# Proposed Approach

1. Extend `CommonCodeSessionBootstrapRequest` in `common_code_session_bootstrap.dart` to remain the smallest existing Application-owned carrier, adding the desktop identity alongside the existing attached-client context instead of inventing a new request type or subsystem.
2. Thread that exact bootstrap request through `createDesktopSessionRuntime(...)` and the default facade bootstrap composition in `createDesktopSessionFacade(...)`, so the desktop app edge owns the concrete identity-context value and both live entry points consume the same carrier.
3. Update `HostDesktopSessionRuntime` to cache its session context from the extended bootstrap request, replacing the runtime-local `desktopSessionRuntimeIdentityId` construction while leaving the implementation bounded to `initialize()`, `refresh()`, `_startSessionWatch()`, `_performStartSessionWatch()`, `_ensureSessionContext()`, `_bootstrapIfNeeded()`, and `submitTurn()`.
4. Update `DesktopSessionBootstrapDriver.ensureSession()` to construct/bootstrap from the same extended request so the default facade path does not drift from the runtime bootstrap path.
5. Keep `CommonCodeSessionFacade` and `HostGateway` unchanged for #122; the existing facade submit-turn and gateway submission contracts stay fixed, with desktop composition reusing `request.attachedClientId` for the already-existing submit-turn wiring.
6. Update focused desktop regression tests to prove initialize/refresh/watch bootstrap and submit-turn now consume the injected carrier-derived identity/client path and no longer depend on runtime-local identity construction.

# Impacted Areas

| Area | Why it is impacted |
| --- | --- |
| `packages/common_code_application/lib/src/common_code_session_bootstrap.dart` | `CommonCodeSessionBootstrapRequest` is the chosen Application-owned carrier and must gain the desktop identity field while preserving the attached-client bootstrap data already used by both live desktop entry points. |
| `apps/common_code_desktop/lib/src/desktop_session_runtime.dart` | Current hardcoded runtime identity lives here, and this file owns the cached session context used by bootstrap/watch and submit-turn. |
| `apps/common_code_desktop/lib/src/desktop_session_facade_adapters.dart` | `DesktopSessionBootstrapDriver.ensureSession()` currently constructs its own bootstrap request and must stay aligned with the runtime path. |
| `apps/common_code_desktop/lib/src/desktop_session_app_edge_composition.dart` | Desktop composition must become the concrete source of the shared bootstrap request for both runtime and default facade bootstrap wiring. |
| `apps/common_code_desktop/test/desktop_session_runtime_test.dart` | Primary proof that initialize/refresh/watch and submit-turn use the injected identity-context path instead of the runtime hardcode. |
| `apps/common_code_desktop/test/desktop_session_app_edge_composition_test.dart` | Proves default desktop composition wires the same identity-context input through the live app-edge path. |
| `apps/common_code_desktop/test/desktop_session_controller_test.dart` | Guards the current submit-turn delegation path so the identity-context refactor does not break the existing desktop controller flow. |

# Validation Plan

- Update runtime-focused tests to assert the cached session context used before watch subscription and during submit-turn comes from the extended `CommonCodeSessionBootstrapRequest` path rather than a runtime-local constant.
- Update app-edge composition coverage to verify the default desktop composition supplies the same shared bootstrap request to the live runtime path and `DesktopSessionBootstrapDriver.ensureSession()`.
- Update controller/runtime regression coverage to verify the current submit-turn delegation path still works while `CommonCodeSessionFacade` and `HostGateway` remain unchanged.
- Keep validation bounded to observable desktop runtime behavior; do not absorb broader parent #118 placement checks or #119 package-move validation.

# Risks

- If the plan widens into broader facade or package redesign, it will duplicate parent #118 scope and create unnecessary hotspot overlap.
- If only one desktop composition path is updated, runtime and facade behavior could diverge around identity-context handling.
- If tests continue asserting the old hardcoded constant path instead of the shared bootstrap-request path, the refactor could appear complete while preserving the wrong ownership boundary.

# Open Questions

- None for this slice; this revision fixes the carrier decision on `CommonCodeSessionBootstrapRequest` and keeps `CommonCodeSessionFacade` / `HostGateway` unchanged.

# Approval Notes

- Stage B review passed this as a narrow, planner-safe refactor slice aligned with ADR 0006 / ADR 0007 and the Application-owned identity-context contract.
- This plan makes the parent relationship explicit: #122 is the identity-context sub-slice that should land before #119 resumes; it is not authority to reopen the rest of #118.
- Serial scheduling is intentional: do not run #122 concurrently with #118 or #119 because of shared hotspots in desktop runtime/app-edge/application bootstrap files.
- This revision resolves the Stage D blockers by preserving the live canonical artifact at `docs/issue-plans/issue-122.md`, adding `apps/common_code_desktop/lib/src/desktop_session_facade_adapters.dart` to change scope, fixing the carrier decision on `CommonCodeSessionBootstrapRequest`, and explicitly keeping `CommonCodeSessionFacade` / `HostGateway` contract surfaces unchanged.
