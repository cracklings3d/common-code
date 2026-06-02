---
issue: github.com/cracklings3d/common-code#132
title: Implement desktop launch / connect for one machine-local OpenCode host process
status: draft
plan_status: proposed
review_status: pending
source: issue
owner: architect
created_at: 2026-06-02
updated_at: 2026-06-02
approved_by: null
approved_at: null
review_artifact: null
related_branch: issue-132
related_pr: null
replaces: null
supersedes: null
change_scope:
  files:
    - packages/host_opencode/lib/src/opencode_out_of_process_host_adapter.dart
    - packages/host_opencode/lib/src/opencode_host_process_launcher.dart
    - packages/host_opencode/lib/src/opencode_host_process_connector.dart
    - packages/host_opencode/lib/host_opencode.dart
    - packages/host_opencode/lib/src/opencode_host_adapter.dart
    - apps/common_code_desktop/lib/src/desktop_session_app_edge_composition.dart
  directories:
    - packages/host_opencode/test/
  modules:
    - packages/host_opencode
    - apps/common_code_desktop
  artifacts:
    - canonical tracked plan for issue #132 (this file)
    - docs/architecture/commoncode-machine-local-host-bootstrap-attach-contract-and-failure-model.md (binding reference, not modified)
    - docs/adr/0006-commoncode-layered-architecture-constitution.md (binding reference, not modified)
    - docs/adr/0002-one-active-host-per-session.md (invariant reference, not modified)
---

# Summary

Replace the simulated in-process `OpenCodeHostAdapter()` default in the desktop app-edge composition with a real out-of-process adapter that launches or attaches to one machine-local OpenCode host process, implementing the bootstrap/attach/failed-start contract defined by issue #131's canonical artifact.

# Problem

The desktop application currently creates `OpenCodeHostAdapter()` (line 40 and line 141 in `desktop_session_app_edge_composition.dart`) as the default `HostService`. This adapter is purely simulated — it holds sessions in memory and fakes turn execution with `Timer`-driven state transitions. The desktop app needs to route session operations to a real out-of-process OpenCode host binary running on the same machine, following the bootstrap/attach contract from `docs/architecture/commoncode-machine-local-host-bootstrap-attach-contract-and-failure-model.md`.

The specific code path being replaced/demoted is the `OpenCodeHostAdapter()` default construction in `desktop_session_app_edge_composition.dart` (lines 40 and 141).

# Acceptance Criteria

- [ ] **AC1a — Attach to already-running host:** When an authoritative machine-local OpenCode host process is already running and reachable, the desktop attaches to it without launching a second host process.
- [ ] **AC1b — Launch then attach:** When no usable authoritative host is available, the desktop launches one machine-local OpenCode host process and then attaches to it.
- [ ] **AC2 — Failed-start handling:** When host launch or attachment cannot produce a usable authoritative host, the desktop produces a bounded failed-start outcome. The session is left without a second active Host. No silent fallback to the in-process simulated adapter occurs.
- [ ] **AC3 — No in-process fallback at runtime:** The default composition path no longer treats the simulated `OpenCodeHostAdapter()` as authoritative. The simulated adapter may remain available for testing (injectable via the optional `hostService` parameter) but the primary runtime path goes through the out-of-process adapter exclusively.
- [ ] **AC4 — No OpenCode vocabulary leak above the adapter boundary:** OpenCode-specific identifiers (process handles, IPC identifiers, host binary paths, OpenCode-specific naming) stay entirely within `packages/host_opencode`. No OpenCode concepts appear in `apps/` or in `packages/common_code_application/` (the `HostService` and `HostGateway` interfaces carry no OpenCode vocabulary).
- [ ] **AC5 — One-host invariant preserved:** The implementation preserves the one-active-host-per-session invariant from ADR 0002. At no point is a second active Host created for the same session during bootstrap, attach, or reconnect.

# In Scope

- Create `OutOfProcessOpenCodeHostAdapter` implementing `HostService` in `packages/host_opencode` that delegates all session operations to a machine-local OpenCode host process.
- Implement host process discovery: detect an already-running authoritative host on the local machine (`OpenCodeHostProcessConnector`).
- Implement host process launch: spawn the OpenCode host binary when no running host is found (`OpenCodeHostProcessLauncher`).
- Implement bounded failed-start handling per the #131 contract: no second active host created, no silent in-process fallback, no automatic failover.
- Wire the out-of-process adapter as the default `HostService` in `desktop_session_app_edge_composition.dart` (lines 40 and 141).
- Preserve the existing `OpenCodeHostAdapter` as a testing artifact (annotate with `@visibleForTesting`).
- Update `packages/host_opencode/lib/host_opencode.dart` public exports.
- Add unit tests under `packages/host_opencode/test/` covering the attach, launch-then-attach, and failed-start paths.
- Keep scope strictly to one machine-local host: no multi-machine, remote, cross-session, or network-facing concerns.

# Out Of Scope

- Transport, wire protocol, IPC mechanism, or RPC design choices (internal implementation detail of `packages/host_opencode`).
- Cross-machine, remote, internet-facing, multi-tenant, or federated host connections.
- Multi-host orchestration or host-failover beyond the single machine-local host.
- Cross-session host sharing or session migration.
- Host binary packaging, distribution, installation, or version management.
- Process supervision beyond basic launch/kill (no watchdog daemon, no auto-restart, no service manager integration).
- The `desktop_session_runtime.dart` runtime composition path (line 123-182 of the same file; explicitly out of scope).
- Changing the `HostService` or `HostGateway` interface contracts in `packages/common_code_application/`.

# Constraints

- **Governing authority — #131 contract:** The bootstrap/attach/reconnect/failed-start contract from `docs/architecture/commoncode-machine-local-host-bootstrap-attach-contract-and-failure-model.md` (the canonical output artifact of issue #131) is binding. All launch, attach, and failure behavior must conform to every clause in that contract.
- **ADR 0006 — Layered architecture:** OpenCode-specific code stays in `packages/host_opencode`. The application layer (`packages/common_code_application`) and domain layer (`packages/common_code_domain`) receive no OpenCode vocabulary or implementation details.
- **ADR 0002 — One active host:** The one-active-host-per-session invariant must be preserved in all code paths (bootstrap, attach, reconnect, failed-start).
- **Accepted issues #40/#41/#42/#43:** The adapter boundary and port contracts defined by these issues are not reopened or modified.
- **Specific code path replaced:** The simulated `OpenCodeHostAdapter()` default construction at `desktop_session_app_edge_composition.dart` line 40 (`createDesktopSessionFacade`) and line 141 (`createDesktopSessionRuntime`) is the named code path being replaced.
- **Single machine-local host only:** The first supported external host is same-machine, out-of-process only (per issue #31 / ADR 0005 accepted direction). No multi-machine or remote paths.
- **No silent fallback:** On launch failure or connection failure, the outcome is a bounded failed-start. The simulated adapter is never silently substituted at runtime.

# Proposed Approach

Major implementation steps:

1. **Create `OutOfProcessOpenCodeHostAdapter`** — New class in `packages/host_opencode/lib/src/opencode_out_of_process_host_adapter.dart` implementing `HostService`. Accepts `OpenCodeHostProcessConnector` and `OpenCodeHostProcessLauncher` as constructor dependencies. On first session operation: (a) attempts to connect to an already-running host via the connector; (b) if no host found, launches the host via the launcher then connects; (c) if both fail, produces a bounded failed-start outcome. Delegates all `HostService` operations across the out-of-process boundary.

2. **Create `OpenCodeHostProcessLauncher`** — Encapsulates logic to locate and spawn the machine-local OpenCode host binary. Returns a process handle or connection endpoint on success. Returns a structured failure when the binary is not found, permission is denied, or the process exits immediately.

3. **Create `OpenCodeHostProcessConnector`** — Encapsulates logic to discover and connect to an already-running machine-local OpenCode host process. Returns a connection handle on success. Returns a structured failure when no host is running or the host is unreachable.

4. **Wire into desktop composition** — Modify `desktop_session_app_edge_composition.dart`: replace `OpenCodeHostAdapter()` default on line 40 with `OutOfProcessOpenCodeHostAdapter(...)`; replace `OpenCodeHostAdapter()` default on line 141 with `OutOfProcessOpenCodeHostAdapter(...)`. The optional `hostService` parameter overrides remain usable for testing injection.

5. **Demote simulated adapter** — Annotate the existing `OpenCodeHostAdapter` in `opencode_host_adapter.dart` with `@visibleForTesting`. It is not removed; tests that need deterministic simulation may still inject it via the `hostService` parameter.

6. **Update public exports** — Modify `packages/host_opencode/lib/host_opencode.dart` to export the new types while keeping OpenCode-internal mapping helpers (`opencode_mapping.dart`) unexported.

7. **Add tests** — Under `packages/host_opencode/test/`: test attach-to-already-running-host path; test launch-then-attach path; test failed-start when host binary is unavailable; test failed-start when process launches but connection fails; test that no second active host is created during bootstrap/attach; test that OpenCode vocabulary does not leak above the `HostService` boundary.

# Impacted Areas

| Area | Impact |
| --- | --- |
| `packages/host_opencode/lib/src/opencode_out_of_process_host_adapter.dart` | New file: out-of-process `HostService` implementation. |
| `packages/host_opencode/lib/src/opencode_host_process_launcher.dart` | New file: process launch abstraction. |
| `packages/host_opencode/lib/src/opencode_host_process_connector.dart` | New file: process connection/discovery abstraction. |
| `packages/host_opencode/lib/host_opencode.dart` | Modified: export new types; optionally restrict simulated adapter visibility. |
| `packages/host_opencode/lib/src/opencode_host_adapter.dart` | Annotated only: `@visibleForTesting` added to existing class. |
| `apps/common_code_desktop/lib/src/desktop_session_app_edge_composition.dart` | Modified: default `HostService` changed from simulated `OpenCodeHostAdapter()` to `OutOfProcessOpenCodeHostAdapter(...)` at lines 40 and 141. |
| `packages/host_opencode/test/` | New and modified test files for attach, launch, and failed-start paths. |
| `docs/architecture/commoncode-machine-local-host-bootstrap-attach-contract-and-failure-model.md` | Binding reference only; not modified by this issue. |
| `docs/adr/0006-commoncode-layered-architecture-constitution.md` | Binding reference only; not modified. |
| `docs/adr/0002-one-active-host-per-session.md` | Invariant reference only; not modified. |

# Validation Plan

- **Unit tests for `OutOfProcessOpenCodeHostAdapter`:** Verify attach-to-existing, launch-then-attach, and failed-start code paths with mocked connector and launcher. Verify all `HostService` operations are delegated correctly.
- **Unit tests for `OpenCodeHostProcessLauncher`:** Verify launch failure modes (binary not found, permission denied, immediate exit) produce structured, well-defined error outcomes without leaking OpenCode vocabulary.
- **Unit tests for `OpenCodeHostProcessConnector`:** Verify discovery failure modes produce structured error outcomes.
- **Contract conformance review:** Verify the implementation's bootstrap/attach/failed-start behavior matches every clause in the #131 contract artifact (`docs/architecture/commoncode-machine-local-host-bootstrap-attach-contract-and-failure-model.md`).
- **Non-regression vocabulary scan:** Grep for OpenCode-specific identifiers (opencode, OpenCodeHost, process handles, IPC identifiers) above the `host_opencode` package boundary in `apps/common_code_desktop/` and `packages/common_code_application/`. Must find zero matches.
- **ADR conformance check:** Verify ADR 0006 layering is preserved (no OpenCode types in application or domain layers). Verify ADR 0002 one-active-host invariant holds through all code paths.

# Risks

- **IPC/transport choice not yet decided by architecture:** This plan scopes transport choice to the implementer within `packages/host_opencode`. The choice (stdio, socket, named pipe, etc.) is internal to the adapter. If architecture later mandates a specific transport, adapter internals may need revision. Mitigation: keep the connector and launcher abstractions small and replaceable.
- **Host binary not yet packaged:** `OutOfProcessOpenCodeHostAdapter` needs a host binary to launch. If no binary is available at a known location, the failed-start path will be the only exercised path until packaging work (outside this issue's scope) catches up. Mitigation: the failed-start path is the primary testable path in the absence of a binary; it must be robust.
- **Scope creep into process supervision:** The launcher starts a process. It is tempting to add watchdog, auto-restart, or daemon behavior. This plan explicitly excludes these. Mitigation: the launcher contract is one-shot launch only; review must enforce this boundary.

# Open Questions

- None block plan creation. IPC transport choice, binary path resolution, and platform-specific process-launch details are implementation decisions deferred to the developer slice within the `packages/host_opencode` boundary.

# Approval Notes

- This plan is the sole canonical artifact governing implementation of issue #132.
- The #131 contract artifact (`docs/architecture/commoncode-machine-local-host-bootstrap-attach-contract-and-failure-model.md`) is binding authority for all bootstrap, attach, reconnect, and failed-start behavior.
- The simulated `OpenCodeHostAdapter()` default at `desktop_session_app_edge_composition.dart` lines 40 and 141 is the named code path being replaced/demoted.
- ADR 0006 layering, ADR 0002 one-active-host invariant, and accepted issues #40/#41/#42/#43 are not reopened.
- Scope is strictly one machine-local host: multi-machine, remote, and cross-session concerns are out of scope.
