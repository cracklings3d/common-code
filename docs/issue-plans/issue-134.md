---
issue: github.com/cracklings3d/common-code#134
title: Run one end-to-end Session flow against the out-of-process authoritative host and validate reconnect behavior
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
related_branch: issue-134
related_pr: null
replaces: null
supersedes: null
master_anchor: eeab5aced0d0b50140246e0504c710c76e1891c8
change_scope:
  files:
    - apps/common_code_desktop/test/end_to_end_out_of_process_session_flow_test.dart
    - apps/common_code_desktop/test/reconnect_out_of_process_host_test.dart
    - apps/common_code_desktop/test/diagnostics_out_of_process_origin_test.dart
    - apps/common_code_desktop/test/support/stub_out_of_process_host.dart
    - apps/common_code_desktop/test/support/capturing_out_of_process_host_connector.dart
    - apps/common_code_desktop/test/support/capturing_out_of_process_host_launcher.dart
    - apps/common_code_desktop/test/support/host_driven_transition_emitter.dart
    - apps/common_code_desktop/test/support/out_of_process_diagnostic_collector.dart
    - apps/common_code_desktop/test/support/reconnect_out_of_process_host_double.dart
  directories:
    - apps/common_code_desktop/test/support/
  modules: []
  artifacts:
    - canonical tracked plan for issue #134 (this file)
    - docs/architecture/commoncode-machine-local-host-bootstrap-attach-contract-and-failure-model.md (binding contract, not modified)
    - docs/adr/0002-one-active-host-per-session.md (invariant reference, not modified)
    - docs/adr/0004-session-notification-semantics.md (notification semantics reference, not modified)
    - docs/adr/0006-commoncode-layered-architecture-constitution.md (layering reference, not modified)
    - parent plan at docs/issue-plans/issue-133.md (parent governance reference, not modified)
    - sibling plan at docs/issue-plans/issue-132.md (out-of-process production slice this plan validates, not modified)
---

# Summary

Validate that the desktop `OutOfProcessOpenCodeHostAdapter` (constructed as the default `HostService` in `apps/common_code_desktop/lib/src/desktop_session_app_edge_composition.dart` by issue #132) actually carries one full end-to-end Session flow across the process boundary and that reconnect behavior matches the contract defined in `docs/architecture/commoncode-machine-local-host-bootstrap-attach-contract-and-failure-model.md`. The deliverable is a single test suite under `apps/common_code_desktop/test/` plus a small set of reusable test-only support classes — no production code, no interface changes, no behavior changes to `OutOfProcessOpenCodeHostAdapter`, `HostService`, or `HostGateway`.

# Problem

Issue #131 defined the binding contract for machine-local bootstrap, attach, reconnect, and failed-start. Issue #132 implemented the `OutOfProcessOpenCodeHostAdapter`, the `OpenCodeHostProcessConnector`, and the `OpenCodeHostProcessLauncher` that the desktop composition seam wires up as the default `HostService`. Issue #133 is the parent plan that defines the first supported Session flow, the minimum startup/disconnect/reconnect/failed-start behavior, and the child-issue boundaries. None of those issues include a test that proves the end-to-end flow actually works on the out-of-process path.

This issue (134) closes that gap. It exercises the 8 numbered Session flow steps against the real out-of-process adapter, observes the 6 host-driven transitions crossing the process boundary, and asserts the 7 concrete reconnect acceptance criteria from the issue body (R1.1–R1.4 for host-alive; R2.1–R2.3 for host-unavailable). It is the first proof that host authority has actually moved out of process for an end-to-end user flow.

# Acceptance Criteria

The acceptance criteria below combine the 4 high-level ACs from the issue body with the 7 concrete reconnect ACs. Every AC must hold against the real `OutOfProcessOpenCodeHostAdapter` constructed by `createDesktopSessionFacade` / `createDesktopSessionRuntime` without injecting `OpenCodeHostAdapter` (the simulated in-process adapter).

- [ ] **AC1 — One end-to-end Session flow works against the out-of-process host.**
  - All 8 numbered steps in "Session flow to exercise" (in the issue body and below) run to completion against the real `OutOfProcessOpenCodeHostAdapter`.
  - No step relies on `OpenCodeHostAdapter` (the simulated adapter) at runtime; that adapter is used only as an injectable test double, never as the primary path.
- [ ] **AC2 — Host-driven transitions cross the process boundary.**
  - All 6 host-driven transitions listed below are observed to originate from the out-of-process host (via connector/launcher invocation counts and snapshot emissions on the `watchSession` stream).
  - The in-process `OpenCodeHostAdapter`'s `Timer`-driven transitions are not the source of any observed transition on the exercised path.
- [ ] **AC3 — Reconnect behavior is validated on the real path.**
  - All 7 reconnect ACs (R1.1, R1.2, R1.3, R1.4, R2.1, R2.2, R2.3) pass against the real out-of-process adapter.
- [ ] **AC4 — The flow no longer depends on in-process host authority.**
  - The desktop composition seam constructs `OutOfProcessOpenCodeHostAdapter` as the default `HostService` (true after #132). The exercised flow runs end-to-end without injecting `OpenCodeHostAdapter`.
  - Removing or disabling the out-of-process adapter makes the end-to-end flow fail (or fall into a bounded failed-start), confirming the flow is no longer carried by in-process authority.

## Concrete reconnect acceptance criteria (mirrors issue body)

### Case 1 — authoritative host remains alive and reachable

- [ ] **R1.1 Same host is reused.** A second `Host` is not created for the session when a `Client` reconnects while the authoritative host is alive. The active `Session.activeHost` after reconnect has the same `Host.id` as before the disconnect. *(Binds to: bootstrap/attach must never create a second active host for an existing session; reconnect does not elect a different host.)*
- [ ] **R1.2 Same session-bound relationship.** Reconnect returns the `Client` to the same session-bound host relationship, not to a newly elected host. The `Session.id` and `Host.id` are unchanged before and after reconnect. *(Binds to: reconnect does not reopen host authority.)*
- [ ] **R1.3 Observation resumes.** After reconnect, `HostService.watchSession(sessionId)` resumes emitting `Session` snapshots that match the post-transition session state from the out-of-process host. *(Binds to: client resumes observation or authorship against the same active session state.)*
- [ ] **R1.4 Notification continuity.** Any `SessionNotification` that was unacknowledged in the session source of truth at the time of disconnect is still observable by the reconnected client. Acknowledgement of a notification before disconnect is preserved across reconnect; the notification does not become unacknowledged again. *(Binds to: ADR 0004 — session-level acknowledgement.)*

### Case 2 — authoritative host is unavailable

- [ ] **R2.1 No silent in-process fallback.** When the authoritative host is not alive / not reachable, reconnect does not silently fall back to `OpenCodeHostAdapter` (the simulated in-process adapter) and does not create a new authoritative `Host` in-process. The composed `HostService` is observably still `OutOfProcessOpenCodeHostAdapter`, and no second `Host` is created. *(Binds to: unavailable does not silently fall back to in-process authority; unavailable does not create a second active host for the session.)*
- [ ] **R2.2 Bounded failed-start outcome.** When startup or attachment cannot produce a usable authoritative host, the result is a bounded failed-start outcome. The session is left without a newly established second host. No automatic failover, no automatic cross-machine recovery, no automatic reopening of the host-boundary decision occurs. *(Binds to: failed-start contract clauses.)*
- [ ] **R2.3 Distinguishable from successful reconnect.** The failed-start outcome is observably distinct from a successful reconnect: the reconnected client must not be presented with a successful session-bound host relationship when the host is unavailable. The runtime surfaces the failed-start state (e.g., as a bounded error or non-snapshot outcome) rather than pretending the session is healthy.

# In Scope

- Add a single end-to-end test file at `apps/common_code_desktop/test/end_to_end_out_of_process_session_flow_test.dart` that drives the 8 numbered Session flow steps against the real `OutOfProcessOpenCodeHostAdapter` (constructed with a stub connector and a stub launcher) and asserts each step's observable outcome.
- Add a reconnect test file at `apps/common_code_desktop/test/reconnect_out_of_process_host_test.dart` that asserts the 7 reconnect ACs (R1.1–R1.4 and R2.1–R2.3) against the real out-of-process adapter.
- Add a diagnostics test file at `apps/common_code_desktop/test/diagnostics_out_of_process_origin_test.dart` that confirms the diagnostics emitted during an out-of-process flow do not include any in-process fallback indicator and that the connector/launcher path was exercised.
- Add the following test-only support classes under `apps/common_code_desktop/test/support/` (no production code, no exports beyond `test/`):
  - `stub_out_of_process_host.dart` — a stub `OpenCodeHostConnector` and `OpenCodeHostLauncher` pair that simulate a real host on a known port. The stub is configurable to succeed on first try, fail-then-succeed, or fail-on-both-attempts.
  - `capturing_out_of_process_host_connector.dart` — an `OpenCodeHostConnector` test double that records every `connect()` invocation (count, timestamp, returned outcome). Used to prove the connector path was exercised (process boundary observability).
  - `capturing_out_of_process_host_launcher.dart` — an `OpenCodeHostLauncher` test double that records every `launch()` invocation. Used to prove the launcher path was exercised.
  - `host_driven_transition_emitter.dart` — a test-only helper that drives a queued turn through `queuedToRunning`, `runningToCompleted`, or `runningToFailed` by emitting pre-canned snapshots through the watch stream of the out-of-process adapter under test. This simulates the host-side transition emission that the eventual real transport will perform.
  - `out_of_process_diagnostic_collector.dart` — a test-only `DurableLocalHostDiagnosticsPort` that records every emitted diagnostic and exposes them as a list for assertions.
  - `reconnect_out_of_process_host_double.dart` — a test-only `OpenCodeHostConnector` that flips from "alive" to "unreachable" mid-test, used for the R2.* case.
- Reuse the existing `bootstrapReady` future on `OutOfProcessOpenCodeHostAdapter` to await bootstrap completion before issuing session operations (this seam is already exposed in #132 and is not modified here).
- Reuse the existing `OpenCodeHostConnectionSuccess` / `OpenCodeHostConnectionFailed` / `OpenCodeHostProcessLaunchSuccess` / `OpenCodeHostProcessLaunchFailed` / `OpenCodeHostBootstrapSuccess` / `OpenCodeHostBoundedFailedStart` outcome types from `packages/host_opencode` to drive stubbed scenarios.
- Reuse the existing `HostServiceFailure` and `HostServiceFailureCode` enum from `packages/common_code_application` for the bounded-failed-start assertions.

# Out Of Scope

- Any production-code change in `packages/host_opencode/`, `apps/common_code_desktop/lib/`, `packages/common_code_application/`, `packages/common_code_domain/`, or any other `lib/` source path.
- Any change to the `HostService` interface, the `HostGateway` interface, or any of their method signatures.
- Any change to `OutOfProcessOpenCodeHostAdapter`, `OpenCodeHostProcessConnector`, `OpenCodeHostProcessLauncher`, `OpenCodeHostConnectionOutcome` sealed hierarchy, or `OpenCodeHostProcessLaunchOutcome` sealed hierarchy.
- Any change to the existing `OpenCodeHostAdapter` (the simulated in-process adapter) — it remains a `@visibleForTesting` test artifact.
- Any change to the `desktop_session_app_edge_composition.dart` default wiring. The exercised flow must run against the existing default wiring.
- Any change to the diagnostics schema (`DurableLocalHostDiagnostic`, `DurableLocalHostDiagnosticCode`). Test 5 verifies the absence of in-process fallback through connector/launcher invocation counts and through the existing schema; it does not require a new diagnostic code.
- Any change to the bootstrap / attach / reconnect / failed-start contract document (`docs/architecture/commoncode-machine-local-host-bootstrap-attach-contract-and-failure-model.md`).
- Any change to ADR 0002, ADR 0004, or ADR 0006.
- Any cross-machine, remote, internet-facing, multi-tenant, or federated trust model work.
- Any production diagnostic, telemetry, logging, or transport change.
- Any new test for non-OOPIE paths (e.g., the simulated in-process adapter or the in-memory adapter) beyond what is needed to verify that they are *not* the source of authority on the exercised path.

# Constraints

- **Binding contract — `docs/architecture/commoncode-machine-local-host-bootstrap-attach-contract-and-failure-model.md`.** Every assertion in this plan must trace back to a clause in this artifact. The reconnect assertions (R1.1–R1.4, R2.1–R2.3) cite the binding contract clauses explicitly. The host-driven transitions must satisfy the contract's "bootstrap / attach" and "minimum reconnect behavior" sections.
- **Parent plan — `docs/issue-plans/issue-133.md`.** This plan is a child of the parent plan. The parent plan defines the first supported Session flow, the minimum startup/disconnect/reconnect/failed-start behavior, and the child-issue boundaries. This plan does not reopen any decision in the parent plan; it only validates the OOPIE path the parent plan governs.
- **Sibling plan — `docs/issue-plans/issue-132.md`.** This plan validates the production code delivered by the sibling plan (#132). It does not modify, extend, or replace the sibling plan. Any finding that requires a code change in `packages/host_opencode/` or the desktop composition seam must be filed as a follow-up issue that names the specific code path to be changed.
- **ADR 0002 — one active host per session.** The R1.1, R1.2, and R2.1 assertions enforce the ADR 0002 invariant on the OOPIE path. No test may create a second active host for an existing session.
- **ADR 0004 — session-level notification semantics.** The R1.4 assertion enforces ADR 0004 on the OOPIE path. Acknowledgement is a Session-level state change; it must not be lost across reconnect; unacknowledged notifications must be replayed.
- **ADR 0006 — layered architecture.** Test support classes that simulate an out-of-process host stay under `apps/common_code_desktop/test/support/`. No test code may import `packages/host_opencode/src/opencode_*.dart` directly; tests import the public surface only.
- **No new production code.** The scope boundary in the issue body is explicit: "No new production code, no new adapter implementation, and no changes to the `HostService` / `HostGateway` interface contracts are in scope for this issue."
- **No silent fallback.** No test may pass by replacing the OOPIE adapter with the simulated in-process adapter. The composition seam must remain on the OOPIE path.
- **Stubbed transport, real seams.** The stub connector / stub launcher simulate the real transport. The real `OutOfProcessOpenCodeHostAdapter` is exercised end-to-end (constructor, bootstrap, every `HostService` method, the watch stream). The stub replaces only the bytes-on-the-wire portion.
- **Single machine-local host only.** Tests assume a single host per session on a single machine. No multi-host orchestration, no host failover, no remote host.
- **Tests are deterministic.** No real network, no real process spawning, no real I/O. All `Future.delayed` calls in stubs are short and bounded.
- **Tests do not depend on wall-clock timing.** Watch-stream emissions are awaited via `Stream.first` / `expectLater(stream, emitsInOrder([...]))`, not `Timer` sleeps.
- **Local baseline is `eeab5aced0d0b50140246e0504c710c76e1891c8`** (post-#127 and #132 merges). This is the head of the OOPIE work-in-progress that #134 validates.

# Proposed Approach

The deliverable is a single coherent test suite with 5 test groups, all under `apps/common_code_desktop/test/`. Each group uses the real `OutOfProcessOpenCodeHostAdapter` (constructed with stubbed connector/launcher doubles) and asserts observable behavior against the binding contract.

## Test group 1 — 8-step end-to-end flow against a real out-of-process host

**File:** `apps/common_code_desktop/test/end_to_end_out_of_process_session_flow_test.dart`

**Setup.** Construct an `OutOfProcessOpenCodeHostAdapter` with a `_StubOutOfProcessHostConnector` (from `stub_out_of_process_host.dart`) configured to return `OpenCodeHostConnectionSuccess` on first try (binding contract case 2: attach-to-existing), and a `_SucceedingOutOfProcessHostLauncher` (from `capturing_out_of_process_host_launcher.dart`) that records but is never actually called. Await `adapter.bootstrapReady` before any session operation.

**Step 1 — bootstrap / attach.** Assert the bootstrap outcome is `OpenCodeHostBootstrapSuccess` (a sealed class from `packages/host_opencode`). Assert the connector's `connect()` invocation count is exactly 1. Assert the launcher's `launch()` invocation count is exactly 0. This proves the "attach-to-existing" path was exercised, not the "launch-then-attach" path.

**Step 2 — create session.** Call `adapter.createSession(sessionId: 'e2e-session', activeHost: Host(id: 'e2e-host'))`. Assert the returned `Session` has `id == 'e2e-session'`, `activeHost.id == 'e2e-host'`, and an empty `clients` list. Assert no `SessionNotification` is attached yet.

**Step 3 — submit turn.** Call `adapter.attachClient(sessionId: 'e2e-session', client: Client(id: 'desktop-client'))`. Then call `adapter.submitTurn(sessionId: 'e2e-session', client: Client(id: 'desktop-client'), submittedText: 'hello')`. Assert the returned `Session.activeTurn!.status == TurnStatus.queued` and `activeTurn!.submittedText == 'hello'`. Assert the deterministic turn id follows the `turn-N` shape used by the production adapter.

**Step 4 — drive turn to running.** Use the `host_driven_transition_emitter.dart` helper to advance the active turn from `queued` to `running` by emitting a `Session` snapshot whose `activeTurn.status == TurnStatus.running` through the watch stream returned by `adapter.watchSession('e2e-session')`. Assert the latest snapshot from the watch stream has `activeTurn!.status == TurnStatus.running`. Assert the `SessionNotification` list contains a `SessionNotification` with `transition == SessionNotificationTransition.queuedToRunning` and `isAcknowledged == false`, with a deterministic id derived from `SessionNotification.deterministicId(sessionId, turnId, queuedToRunning)`.

**Step 5 — drive turn to completed.** Use the helper to advance the active turn from `running` to `completed`. Assert the latest snapshot has `activeTurn!.status == TurnStatus.completed`. Assert the `SessionNotification` list now contains a second `SessionNotification` with `transition == SessionNotificationTransition.runningToCompleted`, `isAcknowledged == false`, and the deterministic id derived from `(sessionId, turnId, runningToCompleted)`.

**Step 5b (optional) — drive turn to failed.** Same as step 5 but with a `failureSummary`. Assert `activeTurn!.status == TurnStatus.failed` and the failure summary is preserved. This step is required only if the exercised path produces a failed turn; per the issue body it is not blocking for the happy path. The test file includes a `group('failed turn variant', ...)` block, marked optional.

**Step 6 — observe `SessionNotification`.** Assert the watch stream emitted a `Session` snapshot carrying the `SessionNotification` from step 4. Assert the `notification.id` matches `SessionNotification.deterministicId(...)` (proving the notification crossed the boundary with a deterministic id).

**Step 7 — acknowledge notification.** Call `adapter.acknowledgeNotification(sessionId: 'e2e-session', notificationId: <the notification id from step 4>)`. Assert the returned `Session` contains a `SessionNotification` with the same `id` and `transition` but `isAcknowledged == true`. Assert the watch stream emitted a new snapshot reflecting the acknowledgement.

**Step 8 — watch continuity.** Subscribe to `adapter.watchSession('e2e-session')` (or reuse the existing subscription). Use `expectLater` to assert the stream emits in order: the post-submit snapshot, the post-`queuedToRunning` snapshot, the post-`runningToCompleted` snapshot, the post-acknowledge snapshot, and the post-completed snapshot. Each emission's `activeTurn.status` must match the expected transition. This proves the watch stream remained live across every host-driven transition.

**Process-boundary observability assertion.** After step 8, assert:
- The stub connector's invocation count equals the expected count (1 for attach-to-existing, 2 for launch-then-attach).
- The stub launcher's invocation count equals the expected count (0 for attach-to-existing, 1 for launch-then-attach).
- The total connector + launcher invocations is at least 1 (proves the OOPIE path was actually exercised, not the in-process path).

A second `test` in the same file exercises the launch-then-attach path: configure the stub connector to fail on first try, succeed on retry, and the stub launcher to succeed. Re-run the same 8 steps and assert the connector invocation count is 2, the launcher invocation count is 1, and the bootstrap outcome is still `OpenCodeHostBootstrapSuccess`.

## Test group 2 — process boundary observability

**File:** `apps/common_code_desktop/test/end_to_end_out_of_process_session_flow_test.dart` (additional `test` block)

**Purpose.** A standalone assertion that the watch stream snapshots are not synthesized in-process; they originate from the OOPIE connector path.

**Setup.** Construct an `OutOfProcessOpenCodeHostAdapter` with a `_CountingOutOfProcessHostConnector` (from `capturing_out_of_process_host_connector.dart`) configured to return `OpenCodeHostConnectionSuccess` with a `Stream<Session>`-like sequence of snapshots. Use the `host_driven_transition_emitter.dart` helper to drive exactly 3 host-driven transitions through the watch stream.

**Assertions.**
- The counting connector's `connect()` invocation count is exactly 1.
- The counting launcher's `launch()` invocation count is exactly 0 (the connector succeeded on first try).
- The watch stream emitted exactly 4 snapshots: the initial subscription snapshot plus the 3 host-driven transitions.
- Every emitted snapshot's `Session.id` is identical to the original session id (no fresh session was created during the host-driven transitions — this is the OOPIE seam's promise, not a fresh in-process `Session`).
- The list of snapshot ids captured by the test matches the watch stream's emission order (no duplicates, no missing snapshots, no reordering).

## Test group 3 — Reconnect Case 1 (host alive) — 4 sub-tests

**File:** `apps/common_code_desktop/test/reconnect_out_of_process_host_test.dart`, `group('Case 1 — authoritative host remains alive')`

**Setup.** Construct an `OutOfProcessOpenCodeHostAdapter` with a `_ReconnectableOutOfProcessHostConnector` (from `reconnect_out_of_process_host_double.dart`) that always returns `OpenCodeHostConnectionSuccess`. Create a session, attach the desktop client, and submit one turn. The first run-through exercises steps 1–5 from Test group 1.

**R1.1 — same host is reused (no second bootstrap).**
- Action: cancel the existing `watchSession` subscription (simulating a `Client` disconnect), then re-subscribe via `adapter.watchSession('e2e-session')`.
- Assert: the counting connector's `connect()` invocation count is unchanged after the disconnect/reconnect cycle (it stays at 1 from the initial bootstrap). The adapter did not re-run bootstrap.
- Assert: `adapter.readSession('e2e-session').activeHost.id == 'e2e-host'` — the same `Host.id` is still bound to the session. No second `Host` was created.

**R1.2 — same session-bound relationship.**
- Action: capture the `Session.id` and `Session.activeHost.id` before disconnect.
- Action: disconnect, then re-subscribe and re-read.
- Assert: the post-reconnect `Session.id == pre-reconnect Session.id` and `post-reconnect Session.activeHost.id == pre-reconnect Session.activeHost.id`. The session-bound relationship was not reopened.

**R1.3 — observation resumes.**
- Action: disconnect, then re-subscribe. Use the `host_driven_transition_emitter.dart` helper to drive one additional transition (e.g., start a new turn and advance it to `running`) on the same session.
- Assert: the reconnected watch stream emits a snapshot reflecting the new transition, with `activeTurn.status == TurnStatus.running`. Observation resumed against the same active session state.
- Assert: the latest snapshot's `activeHost.id` matches the pre-disconnect `activeHost.id`. The session was not rebound to a new host.

**R1.4 — notification continuity per ADR 0004.**
- Setup: drive a turn through `queuedToRunning` and `runningToCompleted`, producing two `SessionNotification`s. Acknowledge one of them, leave the other unacknowledged.
- Action: capture the notification list. Disconnect, then re-subscribe.
- Assert: the reconnected session's notification list contains both notifications.
- Assert: the previously-acknowledged notification still has `isAcknowledged == true` (acknowledgement is preserved across reconnect; it does not revert to unacknowledged).
- Assert: the previously-unacknowledged notification still has `isAcknowledged == false` (unacknowledged notifications are replayed, not duplicated or lost).
- Assert: notification ids are stable across reconnect (deterministic ids, not freshly minted). This is the ADR 0004 contract: the `Session` is the source of truth.

## Test group 4 — Reconnect Case 2 (host unavailable) — 3 sub-tests

**File:** `apps/common_code_desktop/test/reconnect_out_of_process_host_test.dart`, `group('Case 2 — authoritative host is unavailable')`

**Setup.** Use the same `reconnect_out_of_process_host_double.dart` connector, configured to flip from "alive" to "unreachable" mid-test by setting an `unreachable` flag that the connector checks on each `connect()` call.

**R2.1 — no silent in-process fallback.**
- Action: on the reconnect attempt, the connector returns `OpenCodeHostConnectionFailed`. The test verifies the resulting `OutOfProcessOpenCodeHostAdapter` is *still the same OOPIE adapter instance* (the test holds a strong reference to it and asserts the runtime did not substitute a different `HostService`).
- Assert: the connector was invoked on the reconnect attempt (process boundary was probed, not bypassed).
- Assert: the launcher's `launch()` invocation count remains unchanged (the launcher was *not* invoked as a fallback path; per the binding contract, the launcher is one-shot at bootstrap, not on reconnect).
- Assert: no second `Host` was created. (The adapter exposes `_bootstrapOutcome` indirectly via the `bootstrapReady` future; the test verifies the same bootstrap outcome that was settled at initial construction is still in force. No fresh bootstrap was triggered.)

**R2.2 — bounded failed-start outcome.**
- Action: on the reconnect attempt, the connector returns `OpenCodeHostConnectionFailed`. The test invokes a method on the adapter that surfaces the failed-start state (e.g., `adapter.readSession('e2e-session')` after the disconnect, or a new `HostService` method that the production code exposes for this purpose — the test calls whichever method the adapter actually exposes; the precise method is finalized when Test group 1 lands).
- Assert: the operation throws a `HostServiceFailure` whose `code` is one of the existing `HostServiceFailureCode` enum values. Per the binding contract, the failure must be bounded; the test asserts no retry loop, no automatic failover, and no creation of a new `Host` (the test uses a `try { ... } on HostServiceFailure catch (e) { ... }` block and asserts the catch fires exactly once with a stable `code`).
- Assert: the `HostServiceFailure.message` is non-empty and references the out-of-process host (it should mention the OOPIE adapter or the connector/launcher, not the in-process fallback).
- This test is expected to require a small follow-up in #132 if the production code does not currently surface the reconnect failure as a `HostServiceFailure`. The plan treats that as a test-driven finding to be filed as a follow-up issue that names the specific code path to be changed; no production-code change is authored by this plan.

**R2.3 — distinguishable from successful reconnect.**
- Action: run R1.1 (host alive, reconnect succeeds) and R2.1+R2.2 (host unavailable, reconnect fails) in sequence.
- Assert: the two outcomes are observably distinct. The successful reconnect path returns a `Session` snapshot on the watch stream; the failed-start path throws a `HostServiceFailure` (or surfaces a non-snapshot outcome). The test asserts these are different shapes — same input, different output structure, no false-positive session-bound relationship.
- Assert: the failed-start path does not call the `OutOfProcessOpenCodeHostAdapter` constructor a second time (no fresh bootstrap, no fresh connector, no fresh launcher).
- Assert: the failed-start path does not mutate the existing `Session` (the `Session.id`, `Session.activeHost.id`, and `Session.notifications` list are unchanged after the failed reconnect attempt).

## Test group 5 — diagnostic confirmation of out-of-process origin

**File:** `apps/common_code_desktop/test/diagnostics_out_of_process_origin_test.dart`

**Setup.** Construct an `OutOfProcessOpenCodeHostAdapter` with the counting connector and counting launcher, and a `_OutOfProcessDiagnosticCollector` (from `out_of_process_diagnostic_collector.dart`) wired in as the `diagnosticsSink` for `createDesktopSessionFacade` / `createDesktopSessionRuntime`. Run the 8-step flow from Test group 1.

**Assertions.**
- The counting connector's `connect()` invocation count is at least 1.
- The counting launcher's `launch()` invocation count is at least 0 (or at least 1 for the launch-then-attach variant).
- The collected diagnostics list does **not** contain any diagnostic code that would indicate an in-process fallback. The current `DurableLocalHostDiagnosticCode` enum does not have an explicit "out-of-process source" tag; this test asserts the inverse: the absence of any in-process fallback indicator in the diagnostics emitted during the OOPIE flow.
- The collected diagnostics list contains the expected pre-bootstrap, bootstrap, and post-bootstrap diagnostics as defined by the existing `DurableLocalHostDiagnosticCode` enum (e.g., `freshBootstrapActivated` for a fresh bootstrap, `durableReadRestored` for a restored session, `durableWriteFailed` if a write failed). The test does not assert new diagnostic codes; it asserts the existing codes that *should* fire on the OOPIE path, and the absence of codes that *would* indicate a fallback.
- A second test in the same file runs the same flow with the `OpenCodeHostAdapter` (the simulated in-process adapter) injected via the `hostService` parameter. It asserts the diagnostics emitted in that case are observably different from the OOPIE case (different set of `DurableLocalHostDiagnosticCode` values), confirming the diagnostic stream carries enough information to distinguish the two paths. If the diagnostic stream does not currently distinguish the two paths, this test fails and the plan surfaces it as a test-driven finding for a follow-up issue.

# Sequencing and child-issue boundaries

| Issue | Role | Relationship to #134 |
| --- | --- | --- |
| #131 | Defines the binding bootstrap/attach/reconnect/failed-start contract artifact. | Binding contract; this plan validates against it. |
| #132 | Implements the OOPIE production code (`OutOfProcessOpenCodeHostAdapter`, connector, launcher, desktop composition wiring). | Sibling; #134 validates the OOPIE path that #132 implements. #134 is blocked on #132. |
| #133 | Parent plan: defines the first supported Session flow, the minimum startup/disconnect/reconnect/failed-start behavior, and the child-issue boundaries. | Parent; this plan is a child of #133. |
| #134 | This plan: validation/test plan for the OOPIE path. | Self. |
| #123, #124 | Production prerequisites for #132. | Transitive blockers; resolved before #132. |
| #127 | Recently merged (per the master anchor `eeab5aced0d0b50140246e0504c710c76e1891c8`). | Inherited. |
| #30, #31, #44 | Historical references / predecessor issues for #133. | Inherited context. |

# Explicit dependency and child gating

- **#134 is blocked on #132.** The `OutOfProcessOpenCodeHostAdapter` and the desktop composition wiring must be in place (and merged to the baseline `eeab5aced0d0b50140246e0504c710c76e1891c8`) before #134 can run. If #132 is not yet merged, the test plan is still valid as a contract but cannot be exercised end-to-end.
- **#134 is blocked on the parent plan `docs/issue-plans/issue-133.md`.** The parent plan defines the Session flow and the minimum reconnect/failed-start behavior that this plan validates. The parent plan is the upstream governance artifact for #133, #132, and #134. This plan does not implement or modify the parent plan.
- **#134 is not blocked on any later slice.** No later issue depends on #134.
- **#134 does not gate any later slice directly.** The validation findings may surface follow-up issues that gate later work, but the validation tests themselves are the deliverable.
- **#134 does not gate #132.** #132 must merge first; #134 follows.
- **Children of #134:** none. #134 is a leaf validation slice. Test-driven findings may be filed as new issues.

# Impacted Areas

| Area | Impact |
| --- | --- |
| `apps/common_code_desktop/test/end_to_end_out_of_process_session_flow_test.dart` | New file: 8-step end-to-end test (Test group 1) and process-boundary observability test (Test group 2). |
| `apps/common_code_desktop/test/reconnect_out_of_process_host_test.dart` | New file: 7 reconnect AC tests (Test groups 3 and 4). |
| `apps/common_code_desktop/test/diagnostics_out_of_process_origin_test.dart` | New file: diagnostic confirmation of out-of-process origin (Test group 5). |
| `apps/common_code_desktop/test/support/stub_out_of_process_host.dart` | New test support: stub `OpenCodeHostConnector` and `OpenCodeHostLauncher` pair that simulate a real host. |
| `apps/common_code_desktop/test/support/capturing_out_of_process_host_connector.dart` | New test support: counting `OpenCodeHostConnector` test double. |
| `apps/common_code_desktop/test/support/capturing_out_of_process_host_launcher.dart` | New test support: counting `OpenCodeHostLauncher` test double. |
| `apps/common_code_desktop/test/support/host_driven_transition_emitter.dart` | New test support: drives queued→running, running→completed, and running→failed transitions on a `Session` for use in the watch-stream assertions. |
| `apps/common_code_desktop/test/support/out_of_process_diagnostic_collector.dart` | New test support: in-memory `DurableLocalHostDiagnosticsPort` that records every emitted diagnostic. |
| `apps/common_code_desktop/test/support/reconnect_out_of_process_host_double.dart` | New test support: `OpenCodeHostConnector` that flips from "alive" to "unreachable" mid-test. |
| `docs/architecture/commoncode-machine-local-host-bootstrap-attach-contract-and-failure-model.md` | Binding reference only; not modified by this plan. |
| `docs/adr/0002-one-active-host-per-session.md` | Invariant reference only; not modified. |
| `docs/adr/0004-session-notification-semantics.md` | Notification semantics reference only; not modified. |
| `docs/adr/0006-commoncode-layered-architecture-constitution.md` | Layering reference only; not modified. |
| `docs/issue-plans/issue-133.md` | Parent plan; not modified. |
| `docs/issue-plans/issue-132.md` | Sibling plan; not modified. |
| `packages/host_opencode/`, `apps/common_code_desktop/lib/`, `packages/common_code_application/`, `packages/common_code_domain/` | Production code; **not modified** by this plan. |

# Validation Plan

The validation plan is the test plan itself. The 5 test groups above are the executable validation. Additional checks:

- **Test-driven conformance review.** Each test in the 5 groups cites the binding contract clause and/or ADR it enforces. A reviewer can walk the test list and the binding contract in parallel and confirm coverage.
- **Conformance check against the parent plan.** Re-read `docs/issue-plans/issue-133.md` and confirm this plan's 8-step flow and 7 reconnect ACs match the parent plan's "first supported Session flow" and "minimum reconnect behavior" sections. If the parent plan is amended, this plan must be re-validated.
- **Conformance check against the sibling plan.** Re-read `docs/issue-plans/issue-132.md` and confirm the test plan's `OutOfProcessOpenCodeHostAdapter`, `OpenCodeHostProcessConnector`, and `OpenCodeHostProcessLauncher` references match the sibling plan's production types. If the sibling plan is amended, this plan must be re-validated.
- **No-production-code change verification.** `git diff` against the baseline `eeab5aced0d0b50140246e0504c710c76e1891c8` must show zero changes under any `lib/` directory. All changes must be under `apps/common_code_desktop/test/` and this canonical plan file.
- **One-host invariant verification.** R1.1, R1.2, and R2.1 collectively enforce ADR 0002 on the OOPIE path. A reviewer can run the three tests and confirm no second `Host` is created on the exercised path.
- **Notification-continuity verification.** R1.4 enforces ADR 0004 on the OOPIE path. A reviewer can run the test and confirm acknowledged notifications stay acknowledged across reconnect and unacknowledged notifications are replayed.
- **Diagnostic-stream verification.** Test group 5 confirms the diagnostics stream does not contain an in-process fallback indicator and that the connector/launcher path was exercised. A reviewer can run the test and inspect the collected diagnostic list.

# Risks

- **Stubbed transport may not reflect the real transport's semantics.** The stub connector/launcher simulate the bytes-on-the-wire portion. If the real transport's failure modes (e.g., partial reads, mid-stream disconnects) differ from the stubs' behavior, the validation may pass against the stubs but fail in production. Mitigation: keep the stub interfaces identical to the production interfaces (`OpenCodeHostConnector`, `OpenCodeHostLauncher`); document the stub-vs-real divergence explicitly in the test support file's doc comment.
- **Test-driven findings may require production-code changes.** The R2.2, R2.3, and Test group 5 assertions may surface a need for a small production-code change in #132 (e.g., a new `HostServiceFailureCode` enum value, a new `HostService` method to surface reconnect state, or a new `DurableLocalDiagnosticCode` to mark the OOPIE source). Per the issue body's scope boundary, this plan does not authorize those changes. The plan treats any such finding as a test-driven follow-up issue.
- **The `OutOfProcessOpenCodeHostAdapter` may not yet drive host-driven transitions.** The current production code's `submitTurn` does not appear to schedule queued→running or running→completed transitions; the TODO comments in the connector/launcher suggest the transport is still a placeholder. The test plan uses a test-only `host_driven_transition_emitter.dart` helper to drive the transitions through the watch stream, simulating what the real transport will do. This is a validation of the seam, not a validation of the transport. When the real transport lands, the test plan can be extended to also validate the transport.
- **Reconnect path semantics may be underspecified in the production code.** The binding contract requires reconnect behavior but the production code may not yet implement a "reconnect" entry point distinct from "bootstrap". The R1.* and R2.* tests may surface this gap. As above, the plan treats any gap as a test-driven follow-up.
- **The parent plan `docs/issue-plans/issue-133.md` may not exist yet on disk.** The reference is by path; if the file is absent at the time of plan review, the controller should treat the reference as a forward-pointer to a future file. The plan's conformance check against the parent plan must be re-validated once the parent plan is written.
- **The "no second active host" invariant may be hard to assert without internal adapter access.** The test asserts no second `Host` is created by comparing `Session.activeHost.id` before and after the disconnect/reconnect cycle. This is a behavioral assertion, not an internal-state assertion; it does not require `_sessionsById` access. If the production code allows two `Host`s with the same `id` to coexist (which the binding contract forbids), the assertion still catches the symptom but not the root cause. A follow-up issue may add a stronger internal-state check if the production code grows a public introspection API.

# Open Questions

- **Does the production `OutOfProcessOpenCodeHostAdapter` expose a method to surface the reconnect failure as a `HostServiceFailure`?** R2.2 assumes yes (it calls a method on the adapter). If no, the test fails and the plan surfaces a test-driven finding. This is the most likely gap.
- **Does the production `OutOfProcessOpenCodeHostAdapter` expose a way to re-run bootstrap on a reconnect attempt?** The binding contract implies "no" (reconnect does not re-run bootstrap), but the production code may not enforce it. R1.1 asserts the count of `connect()` invocations; if the production code does re-run bootstrap, the count increases and the test fails.
- **Does the production `submitTurn` schedule a host-driven transition, or does the host emit the transition through the watch stream?** The current `submitTurn` does not schedule a transition; the test plan assumes the host emits the transition. If the production code instead schedules the transition in-process, the test plan's stub connector must be updated to match. This is a low-risk divergence.
- **Is there a public `HostService` method to "reconnect" (vs. "bootstrap")?** The binding contract describes reconnect as a behavior, not a method. The test plan uses `watchSession` cancel + re-subscribe as the reconnect mechanism. If the production code adds a `reconnect` method, the test plan can be extended.
- **What is the precise diagnostic code emitted on a fresh bootstrap?** Test group 5 asserts the existing `DurableLocalHostDiagnosticCode` codes fire as expected. The list of codes is the existing `DurableLocalHostDiagnosticCode` enum; the test does not invent new codes.

# Approval Notes

- This plan is the sole canonical validation/test artifact governing issue #134. It does not authorize any production-code change.
- The binding contract `docs/architecture/commoncode-machine-local-host-bootstrap-attach-contract-and-failure-model.md` is the governing authority for every reconnect assertion in this plan. The 7 reconnect ACs (R1.1–R1.4, R2.1–R2.3) cite the binding contract clauses directly.
- The parent plan `docs/issue-plans/issue-133.md` is the upstream governance artifact for the Session flow and the minimum reconnect behavior. This plan does not reopen any parent-plan decision.
- The sibling plan `docs/issue-plans/issue-132.md` is the production-code slice this plan validates. This plan does not modify the sibling plan.
- ADR 0002 (one active host per session), ADR 0004 (session-level notification semantics), and ADR 0006 (layered architecture) are not reopened. The test plan enforces all three on the OOPIE path.
- Scope is strictly validation: no new production code, no new adapter implementation, no changes to the `HostService` / `HostGateway` interface contracts, no changes to `OutOfProcessOpenCodeHostAdapter`, `OpenCodeHostProcessConnector`, or `OpenCodeHostProcessLauncher`. Any finding that requires a code change in `packages/host_opencode/` or the desktop composition seam must be filed as a follow-up issue that names the specific code path to be changed.
- The plan is a single coherent document governing a single branch (`issue-134`) and a single worktree (`C:\Users\The_u\AppData\Local\Temp\opencode\worktrees\common-code\issue-134`).
- The local baseline is `eeab5aced0d0b50140246e0504c710c76e1891c8` (post-#127 and #132 merges). This is the head of the OOPIE work-in-progress that #134 validates.
