---
issue: github.com/cracklings3d/common-code#124
title: Add restart replay coverage for unacknowledged Session notifications
status: draft
plan_status: proposed
review_status: pending
source:
  - github.com/cracklings3d/common-code#124
  - controller-stage-c-brief
owner: architect
created_at: 2026-05-30
updated_at: 2026-05-30
approved_by: null
approved_at: null
review_artifact: null
related_branch: issue-124-replay-unacknowledged-session-notifications
related_pr: null
replaces: null
supersedes: []
change_scope:
  files:
    - apps/common_code_desktop/test/desktop_session_persistence_test.dart
  directories:
    - apps/common_code_desktop/test
  modules:
    - common_code_desktop durable restart replay regression coverage for host-driven Session notifications
  artifacts:
    - docs/issue-plans/issue-124.md
    - restart replay validation for acknowledged versus unacknowledged Session notifications after durable restore
---

# Summary

Now that issue #123 / PR #138 has landed the durable streamed-transition prerequisite, this slice adds the narrowly scoped restart regression coverage for host-driven `Session` notifications. The intended outcome is proof that streamed notifications emitted before shutdown survive restart and replay only when they remain unacknowledged.

# Problem

Issue #123 addressed durable persistence for host-driven streamed `Session` transitions, but issue #124 still needs explicit restart coverage for the case where those transitions were emitted and not yet acknowledged before shutdown. Without this validation slice, regressions could silently lose streamed notifications across restart or replay notifications that were already acknowledged.

# Acceptance Criteria

- Coverage exercises a full restart after host-driven streamed transitions emit notification-bearing `Session` updates that have not yet been acknowledged.
- Coverage proves still-unacknowledged notifications replay after restart from durable state.
- Coverage proves a notification acknowledged before restart does not replay again after the next restart.
- Coverage fails if streamed transitions emitted before restart are missing from restored state.

# In Scope

- Extend existing desktop restart/persistence regression coverage to stage host-driven streamed transitions, persist them, and restart from durable state.
- Reuse or minimally extend existing in-test host adapters and restart helpers only where necessary to express the streamed-before-restart scenario.
- Assert replay behavior separately for still-unacknowledged versus acknowledged notifications after restart.

# Out Of Scope

- Re-implementing or broadening the durable streamed-transition persistence behavior delivered by issue #123.
- New production notification semantics, transport behavior, or host lifecycle changes.
- Broader out-of-process host work or umbrella scope from issue #121.
- Reconnect-only coverage that does not exercise a full restart.

# Dependencies

- Issue #123, merged via PR #138, is a hard prerequisite; this slice assumes durable persistence of host-driven streamed session transitions is already available.
- `docs/adr/0004-session-notification-semantics.md` remains the governing semantic authority for replay and acknowledgement behavior after restart.
- Historical references #26, #28, #30, and #75 provide restart-continuity context only and are not reopened by this slice.

# Constraints

- Keep the change surface bounded to restart-focused validation artifacts, preferring `apps/common_code_desktop/test/desktop_session_persistence_test.dart` over broader cross-layer scaffolding.
- Do not absorb production persistence implementation, broader restart architecture work, or parent/tracker scope from issue #121.
- Any supporting seam must be the smallest extension of existing desktop test fixtures required to drive streamed emission, acknowledgement, shutdown, and restart deterministically.
- If independence is uncertain, narrow toward fewer stronger restart assertions instead of adding a wide regression matrix.

# Proposed Approach

1. Use the existing desktop durable-runtime/persistence harness to initialize a session backed by durable storage and a host test adapter that can emit host-driven streamed `Session` snapshots with notification data.
2. Emit a streamed transition that produces a non-vacuous notification set, wait for the durable write path introduced by issue #123, then restart from storage without acknowledging those notifications and assert the restored session still exposes the streamed notification set as replayable.
3. In the same bounded harness, acknowledge one of the restored notifications, persist that acknowledgement, restart again, and assert the acknowledged notification does not replay while any remaining unacknowledged notification still does.
4. Compare restored state against the streamed snapshot so the regression fails if streamed transitions are silently lost between emission and restart.

# Impacted Areas

| Area | Why it is impacted |
| --- | --- |
| `apps/common_code_desktop/test/desktop_session_persistence_test.dart` | Primary restart regression file; it already owns durable restore and acknowledgement continuity coverage closest to this scenario. |
| Co-located desktop test fixtures inside that file | Smallest acceptable place to extend stream-emission or restart helpers if the current harness cannot express the scenario without duplication. |
| `docs/adr/0004-session-notification-semantics.md` | Governing semantic reference only; no edit planned. |

# Validation Plan

- Run the new or revised restart regression coverage in `apps/common_code_desktop/test/desktop_session_persistence_test.dart`.
- Verify one scenario covers streamed-but-unacknowledged notifications surviving restart.
- Verify one scenario covers acknowledgement before restart suppressing replay on the subsequent restart.
- Verify the assertion set would fail if the streamed snapshot persisted by issue #123 were not restored.

# Risks

- Test drift into reconnect or UI rendering concerns would broaden the slice beyond restart replay validation.
- If assertions check only acknowledgement flags after restart but not the streamed-origin notification set itself, silent-loss regressions could slip through.
- Over-building new test infrastructure would increase coupling where the existing persistence harness should be sufficient.

# Open Questions

- None required for plan creation. If review later requires a rendered replay assertion, it should stay as a single additional restart-focused regression in existing desktop test coverage and not expand into broader UI scenarios.

# Approval Notes

- Parent/tracker #121 remains umbrella-only and is not implementation scope for this plan.
- This plan is intentionally gated on prerequisite issue #123 / PR #138 being merged.
- The scope is limited to replay-after-restart validation and coverage only; it does not absorb persistence implementation or broader host work.
