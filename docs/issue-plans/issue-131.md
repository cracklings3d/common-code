---
issue: github.com/cracklings3d/common-code#131
title: Define the minimal machine-local host bootstrap / attach contract and failure model
status: draft
plan_status: proposed
review_status: not_reviewed
source:
  - https://github.com/cracklings3d/common-code/issues/131
  - https://github.com/cracklings3d/common-code/issues/31
  - docs/adr/0005-external-host-path-after-durable-local-baseline.md
  - docs/adr/0002-one-active-host-per-session.md
  - docs/architecture/commoncode-application-port-contract-set.md
owner: architect
created_at: 2026-05-29
updated_at: 2026-05-30
approved_by: null
approved_at: null
review_artifact: null
related_branch: issue-131-minimal-machine-local-host-bootstrap-attach-contract-and-failure-model
related_pr: null
replaces: null
supersedes: []
change_scope:
  files:
    - docs/issue-plans/issue-131.md
    - docs/architecture/commoncode-machine-local-host-bootstrap-attach-contract-and-failure-model.md
  directories: []
  modules: []
  artifacts:
    - canonical tracked plan for issue #131
    - canonical definition artifact for the machine-local host bootstrap, attach, reconnect, and failed-start contract
---

# Summary

Create a docs-only canonical plan for issue #131 that directs one bounded follow-on definition artifact: `docs/architecture/commoncode-machine-local-host-bootstrap-attach-contract-and-failure-model.md`. That artifact is the sole canonical output for this issue's implementation slice and must define the first supported same-machine bootstrap, attach, reconnect, and failed-start contract without reopening the already accepted same-machine out-of-process host direction.

# Problem

Issue #31 accepted the same-machine, out-of-process host direction, but the minimal bootstrap / attach contract for that direction is still undefined. Issue #131 closes that gap for the first machine-local path by specifying:

- the first supported bootstrap / attach flow
- minimum viable reconnect behavior
- minimum viable failed-start behavior
- how those behaviors preserve the one-active-host-per-session invariant

This slice must stay definition-only. It should be strong enough to unblock downstream implementation planning, including later issue #132, without turning into transport, protocol, supervision, or adapter API design.

# Acceptance Criteria

- [ ] `docs/architecture/commoncode-machine-local-host-bootstrap-attach-contract-and-failure-model.md` exists and is named as the sole canonical output artifact for issue #131.
- [ ] The artifact explicitly defines the first supported same-machine bootstrap / attach flow for the authoritative out-of-process host path.
- [ ] The artifact explicitly defines minimum reconnect behavior for the cases where the authoritative host is still alive versus unavailable.
- [ ] The artifact explicitly defines minimum failed-start behavior for the case where no usable authoritative host can be attached and startup of the required machine-local host does not succeed.
- [ ] The artifact explicitly preserves the one-active-host-per-session invariant and does not reopen issue #31 direction.
- [ ] The artifact remains minimal enough to guide downstream execution without specifying transport, IPC/RPC, process supervision, or concrete Dart API shapes.

# In Scope

- Resolve the canonical output artifact path for this issue.
- Define the first supported machine-local bootstrap / attach contract at the architecture/spec level.
- Define the minimum reconnect contract for an already-authoritative same-machine host.
- Define the minimum failed-start contract when startup or attachment cannot establish a usable authoritative host.
- State the one-active-host-per-session invariant as a governing rule for bootstrap, attach, and reconnect.
- Bound the contract so later execution slices can implement it without reopening ADR direction.

# Out Of Scope

- Creating a new ADR or reopening the accepted same-machine out-of-process host direction from issue #31.
- Transport, IPC, RPC, protocol, socket, port, or wire-format design.
- Process supervision, daemon/service-manager integration, installer behavior, or OS packaging.
- Production code, tests, package creation, adapter extraction, or runtime implementation work.
- Cross-machine, internet-facing, multi-tenant, or federated trust/auth models.
- Detailed error catalogs, concrete method signatures, or DTO/class design.

# Constraints

- Treat issue #31 as the accepted architectural authority for the same-machine out-of-process host direction even though the local `docs/adr/0005-external-host-path-after-durable-local-baseline.md` file still shows `Status: Proposed`.
- Preserve the one-active-host-per-session invariant from `docs/adr/0002-one-active-host-per-session.md`.
- Keep the slice minimal: bootstrap, attach, reconnect, failed-start behavior, and the one-active-host-per-session invariant only.
- Keep the output docs-only and avoid normalizing current transitional seams as final API design.
- Align with the application-port boundaries already defined for host gateway, session observation, and identity context without redefining those port sets.
- The current local worktree branch ref resolves to `fd5665b7b2ef5750eecc044229d7d3c2cb7303e6`; this plan makes no claim about remote freshness beyond that local verification.

# Proposed Approach

1. Create `docs/architecture/commoncode-machine-local-host-bootstrap-attach-contract-and-failure-model.md` as the sole canonical definition artifact for issue #131.
2. In that artifact, explicitly inherit the already accepted direction from issue #31 and the one-active-host-per-session invariant from ADR 0002 as fixed inputs rather than open decisions.
3. Define one minimal first-supported bootstrap / attach flow for the machine-local out-of-process path:
   - an eligible same-machine client may attach to the already-authoritative host for its session when that host is reachable
   - if no usable authoritative host is available for that session, the first supported bootstrap path may establish one machine-local authoritative host and then attach the client to that same host
   - bootstrap / attach must never authorize a second active host for the same session
4. Define reconnect behavior narrowly:
   - if the authoritative host remains alive, reconnect returns the client to that same session-bound host relationship
   - reconnect does not elect a different host or reopen host authority
   - if the authoritative host is unavailable, the contract must distinguish that state from successful reconnect and must not silently fall back to in-process authority
5. Define failed-start behavior narrowly:
   - when startup or attachment cannot produce a usable authoritative host, the result is a bounded failed-start outcome
   - failed-start leaves the session without a newly established second host
   - failed-start behavior must not imply automatic failover, automatic cross-machine recovery, or automatic reopening of host-boundary decisions
6. Keep the artifact implementation-facing but not implementation-prescriptive by naming required contract behaviors, invariants, and actor responsibilities while deferring transport, protocol, launch mechanism, and exact API shape decisions to downstream execution work.

# Impacted Areas

| Area | Impact |
| --- | --- |
| `docs/architecture/commoncode-machine-local-host-bootstrap-attach-contract-and-failure-model.md` | New canonical issue output artifact for the definition slice. |
| `docs/adr/0005-external-host-path-after-durable-local-baseline.md` | Governing direction reference only; not revised by this issue. |
| `docs/adr/0002-one-active-host-per-session.md` | Governing invariant reference only; not revised by this issue. |
| `docs/architecture/commoncode-application-port-contract-set.md` | Existing port-boundary reference for host gateway, session observation, and identity context alignment. |
| `apps/common_code_desktop` | Downstream consumer at the app-edge bootstrap/composition boundary; no code changes authorized by this plan. |
| `packages/common_code_application` | Downstream home of contract-facing orchestration concerns informed by this definition slice; no code changes authorized by this plan. |
| `packages/host_opencode` | Downstream host-adapter implementation path expected to consume the contract later; no code changes authorized by this plan. |

# Validation Plan

- Review the resulting artifact against the issue #131 acceptance criteria and this tracked plan.
- Verify the artifact explicitly names `docs/architecture/commoncode-machine-local-host-bootstrap-attach-contract-and-failure-model.md` as the canonical output for this slice.
- Verify the artifact defines bootstrap, attach, reconnect, and failed-start behavior separately and minimally.
- Verify the artifact preserves the one-active-host-per-session invariant and treats issue #31 direction as inherited authority rather than an open decision.
- Verify the artifact does not specify transport, IPC/RPC, protocol, process supervision, or concrete API/class details.
- Verify the artifact is precise enough for downstream dependency analysis across `apps/common_code_desktop`, `packages/common_code_application`, and `packages/host_opencode` without prescribing implementation choreography.

# Risks

- Scope drift into transport/protocol/process-supervision design would make this slice larger than authorized.
- Treating the local ADR 0005 status label as blocking could incorrectly stall the slice despite issue #31 already being accepted.
- Over-specifying concrete APIs or recovery mechanics here could constrain downstream execution work unnecessarily.

# Open Questions

- No additional question blocks plan creation.
- Downstream execution questions such as launch mechanism, IPC shape, concrete error types, and retry UX remain intentionally deferred beyond this slice.

# Approval Notes

- This plan resolves the missing canonical output artifact explicitly: `docs/architecture/commoncode-machine-local-host-bootstrap-attach-contract-and-failure-model.md` is the sole definition artifact for issue #131.
- The accepted decision from issue #31 is treated as the governing same-machine out-of-process direction for this plan; the locally still-proposed ADR label is not blocking authority.
- Local baseline commit verification is limited to the current worktree branch ref at `fd5665b7b2ef5750eecc044229d7d3c2cb7303e6`; remote freshness was not revalidated.
