---
issue: github.com/cracklings3d/common-code#123
title: Persist host-driven streamed Session transitions so restart cannot lose pending notifications
status: proposed
plan_status: drafted
review_status: pending
source:
  - github.com/cracklings3d/common-code#123
  - controller-stage-c-brief
owner: architect
created_at: 2026-05-29
updated_at: 2026-05-29
approved_by: null
approved_at: null
review_artifact: null
related_branch: issue-123-persist-host-driven-streamed-session-transitions-so-restart-cannot-lose-pending-notifications
related_pr: null
replaces: null
supersedes: []
change_scope:
  files:
    - apps/common_code_desktop/lib/src/desktop_session_facade_adapters.dart
    - apps/common_code_desktop/lib/src/desktop_session_app_edge_composition.dart
    - apps/common_code_desktop/lib/src/desktop_session_runtime.dart
    - packages/common_code_persistence/lib/src/durable_local_session_store.dart
    - apps/common_code_desktop/test/desktop_session_app_edge_composition_test.dart
    - apps/common_code_desktop/test/desktop_session_runtime_test.dart
    - apps/common_code_desktop/test/desktop_session_persistence_test.dart
  directories:
    - apps/common_code_desktop/lib/src
    - apps/common_code_desktop/test
    - packages/common_code_persistence/lib/src
  modules:
    - common_code_desktop app-edge session observation and mutation adapters
    - common_code_desktop desktop runtime watch/bootstrap seam
    - common_code_persistence durable local session persistence queue
  artifacts:
    - docs/issue-plans/issue-123.md
    - durable session payload updates driven by streamed host session snapshots
    - focused desktop regression coverage for streamed-transition persistence
---

# Summary

Close the persistence gap on the desktop streamed session-observation path so host-driven `Session` updates are durably written after they are emitted, preventing a restart from reopening a stale snapshot that is missing pending notifications.

# Problem

The current desktop app edge persists sessions when explicit mutation calls return updated snapshots, but host-driven transitions continue through the watch stream after those mutation calls complete. Those streamed updates can append or alter pending `Session.notifications` without triggering another durable write. If the app restarts after the live stream advanced but before another explicit persistence-triggering mutation occurs, bootstrap can restore stale durable state and lose pending notifications that already existed in memory.

# Acceptance Criteria

1. The desktop streamed observation path queues durable persistence from the latest emitted `Session` snapshot when host-driven transitions update the session after the initial mutation call.
2. Persisted streamed snapshots preserve existing `SessionNotification` data exactly as emitted, including deterministic notification ids and acknowledgement state; this slice must not re-synthesize or re-key notifications.
3. The change stays bounded to the streamed observation persistence seam and does not expand into the broader replay-after-restart umbrella tracked by #121.
4. Focused regression coverage demonstrates that streamed session transitions now reach durable storage; the broader restart/replay verification slice remains with issue #124.

# In Scope

- Desktop app-edge wiring that observes `HostService.watchSession(...)` / `CommonCodeSessionObservation.watchSession(...)` output.
- Reusing the existing durable session persistence queue from the desktop edge when streamed snapshots arrive.
- Keeping facade/runtime composition paths aligned so both desktop entry points persist host-driven streamed transitions.
- Focused regression tests for streamed-transition persistence at the desktop edge.

# Out Of Scope

- The full replay-after-restart behavior umbrella tracked by #121.
- Broad restart/replay verification coverage intended for #124.
- Changes to domain notification identity rules in `Session` or `SessionNotification`.
- New notification synthesis, backfill, deduplication, or non-desktop host behavior changes.

# Constraints

- Preserve deterministic `SessionNotification.id` semantics generated from `(sessionId, turnId, transition)`.
- Keep the change surface localized to the desktop observation/persistence seam and any persistence-store helper it directly requires.
- Do not change bootstrap source ordering beyond consuming a more up-to-date durable payload.
- Maintain existing non-fatal durable-write behavior and reporting patterns for persistence failures.
- Do not fold #124's replay-verification scope into this slice.

# Proposed Approach

1. Add or adapt a desktop app-edge observation wrapper so each forwarded `Session` snapshot from the host watch stream can also enqueue durable persistence with the attached desktop client context.
2. Use that shared streamed-persistence seam from both desktop composition paths (`createDesktopSessionFacade(...)` and `HostDesktopSessionRuntime`) so host-driven transitions are not missed by one entry point.
3. Keep explicit mutation persistence (`submitTurn`, `acknowledgeNotification`) intact, but treat streamed snapshots as the authority for subsequent host-driven state changes such as queued→running and running→completed/failed transitions.
4. Reuse the existing queued durable persistence infrastructure rather than introducing a second storage pathway, so duplicate writes remain serialized and bounded.
5. Add focused regression coverage that drives streamed host updates and asserts the durable payload reflects the latest emitted snapshot without expanding into the full restart/replay matrix reserved for #124.

# Impacted Areas

| Area | Why it is impacted |
| --- | --- |
| `apps/common_code_desktop/lib/src/desktop_session_facade_adapters.dart` | Likely home for the smallest shared observation/persistence adapter at the desktop app edge. |
| `apps/common_code_desktop/lib/src/desktop_session_app_edge_composition.dart` | Desktop facade composition must wire the streamed-persistence seam into the default app-edge graph. |
| `apps/common_code_desktop/lib/src/desktop_session_runtime.dart` | Runtime watch handling must persist streamed host updates, not just direct mutation results. |
| `packages/common_code_persistence/lib/src/durable_local_session_store.dart` | May need a small helper/interface adjustment if streamed observation persistence needs tighter reuse of the existing queued write path. |
| `apps/common_code_desktop/test/*.dart` persistence/runtime/app-edge tests | Regression coverage for streamed transition persistence belongs here. |

# Validation Plan

- Update desktop app-edge composition coverage to prove streamed snapshots trigger durable persistence through the default facade composition.
- Update runtime-focused coverage to prove host-driven watch updates persist even when no second explicit mutation occurs.
- Add or revise persistence-focused coverage to assert the durable payload contains the notification set emitted by the latest streamed snapshot.
- Keep validation centered on persistence of the streamed snapshot itself; leave broader restart/replay scenario coverage to issue #124.

# Risks

- Streamed snapshots may cause duplicate persistence requests after explicit mutation persistence; the implementation should rely on the existing queued write path rather than inventing a second scheduler.
- Wiring persistence in only one desktop entry point would leave behavior inconsistent between facade and runtime paths.
- Accidentally rebuilding notifications instead of forwarding streamed snapshots would violate deterministic notification identity semantics.

# Open Questions

- Should the final implementation use a dedicated persisting observation adapter or the smallest equivalent hook inside the existing desktop watch listeners? Prefer the option that covers both desktop entry points with the smallest localized change surface.
- If review requests a restart smoke assertion in this issue, it must stay narrowly scoped and not absorb the broader replay verification assigned to #124.

# Approval Notes

- This plan is intentionally limited to the persistence gap on the streamed session-observation path described by issue #123.
- Parent replay umbrella remains #121.
- Downstream coverage/replay verification remains #124.
- Approval pending planning review.
