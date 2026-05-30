# CommonCode machine-local host bootstrap, attach, reconnect, and failed-start contract

## Status and scope

- Status: planning/specification only
- Change scope: docs-only
- Canonical artifact for issue #131
- Deliverable scope: define the first supported machine-local bootstrap / attach contract, minimum reconnect behavior, and minimum failed-start behavior for the same-machine out-of-process host path

This artifact defines contract boundaries only. It does not authorize interface implementation, adapter extraction, package creation, migration sequencing, concrete API signatures, transport choices, process-supervision choices, or code changes in `apps/**` or `packages/**`.

## Pinned prerequisite baseline

This artifact is a consequence of accepted prerequisites and does not replace them.

| Issue | Pinned prerequisite artifact | Inherited decision reused here |
| --- | --- | --- |
| #31 | `docs/adr/0005-external-host-path-after-durable-local-baseline.md` | Same-machine out-of-process Host is the first supported external Host boundary. The local `Status: Proposed` label does not block this slice; issue #31 is the accepted governing direction. |
| #131 | `docs/issue-plans/issue-131.md` | This artifact is the sole canonical output for issue #131. |
| ADR 0002 | `docs/adr/0002-one-active-host-per-session.md` | One-active-host-per-session is an invariant. Bootstrap, attach, and reconnect must never create a second active Host for a session. |

## Inherited decisions from accepted architecture

The following decisions are inherited from accepted prerequisites and are not newly decided by this artifact.

| Decision | Decision status | Source |
| --- | --- | --- |
| The first supported external Host boundary is a same-machine, out-of-process Host running on the current Host Machine. | Inherited from issue #31 / ADR 0005 | Issue #31 accepted direction, locally still proposed ADR label does not block |
| A Session has exactly one active Host at a time. | Inherited from ADR 0002 | One-active-host-per-session is invariant for all session lifetimes |
| Client process failure or disconnect does not transfer Host authority and does not create a second Host for the Session. | Inherited from issue #31 / ADR 0005 | Same-machine out-of-process failure model |
| Reconnection targets the existing Session / Active Host relationship, not a newly elected host. | Inherited from issue #31 / ADR 0005 | Same-machine reconnect expectations |

## New decisions introduced by issue #131

Issue #131 adds the bounded bootstrap / attach / reconnect / failed-start contract for the already-accepted same-machine out-of-process path.

| Decision | Decision status | Source |
| --- | --- | --- |
| The first supported bootstrap path may establish a machine-local authoritative Host when no usable authoritative Host exists for a session. | New in issue #131 | This artifact |
| An eligible same-machine Client may attach to the already-authoritative Host when that Host is reachable. | New in issue #131 | This artifact |
| Bootstrap / attach must never authorize a second active Host for the same session. | New in issue #131 | This artifact — realizes ADR 0002 invariant |
| Reconnect behavior distinguishes two cases: authoritative Host still alive versus authoritative Host unavailable. | New in issue #131 | This artifact |
| When startup or attachment cannot produce a usable authoritative Host, the result is a bounded failed-start outcome. | New in issue #131 | This artifact |
| Failed-start leaves the session without a newly established second Host and does not imply automatic failover or automatic cross-machine recovery. | New in issue #131 | This artifact |

## Why this contract is needed now

Issue #31 accepted the same-machine out-of-process Host direction but did not define the bootstrap / attach contract. Issue #131 closes that gap for the first machine-local path.

This artifact is intentionally minimal. It names required contract behaviors, actor responsibilities, and state distinctions without specifying:

- transport, socket, or wire-format choices
- IPC, RPC, or protocol design
- process-supervision, daemon, or service-manager integration
- concrete Dart API shapes, method signatures, DTOs, or error catalogs
- launch mechanism or executable packaging
- cross-machine, internet-facing, multi-tenant, or federated trust models

Downstream execution slices (including issue #132) will make those choices without reopening whether the first Host boundary is same-machine out-of-process.

## Actor roles

| Actor | Role in this contract |
| --- | --- |
| Client | Attaches to an authoritative Host for a session. May reconnect to the same Host while it remains alive. Must not elect a new Host. |
| Authoritative Host | The single active Host bound to a session. Runs out-of-process on the same Host Machine for the first supported path. |
| Session | Owns the one-active-host-per-session invariant. Represents the unit of work that has exactly one active Host at a time. |

## First supported bootstrap / attach flow

The first supported bootstrap / attach path proceeds as follows:

1. **No usable authoritative Host exists for the session.**
   The bootstrap path may establish a machine-local authoritative Host and then attach the Client to that same Host.
2. **A usable authoritative Host already exists for the session.**
   An eligible same-machine Client may attach directly to that already-authoritative Host.
3. **Bootstrap / attach must never authorize a second active Host for the same session.**
   This is the one-active-host-per-session invariant in force. No bootstrap or attach flow may create a second active Host for an existing session.

The bootstrap / attach flow is architectural only. This artifact does not specify how the Host is launched, how the Client discovers the Host, or which transport the attachment uses.

## Minimum reconnect behavior

Reconnect behavior distinguishes two cases:

### Case 1: Authoritative Host remains alive

If the authoritative Host remains alive and reachable, reconnect returns the Client to that same session-bound Host relationship.

- Reconnect does not elect a different Host.
- Reconnect does not reopen host authority.
- The Client resumes observation or authorship against the same active session state.

### Case 2: Authoritative Host is unavailable

If the authoritative Host is unavailable (not alive, not reachable, or otherwise not usable), the contract must distinguish that state from a successful reconnect.

- Unavailable does not silently fall back to in-process authority.
- Unavailable does not create a second active Host for the session.
- The session remains without a newly established second Host.

This artifact does not specify what the Client or Application may do when the Host is unavailable. Those choices belong to downstream execution slices.

## Minimum failed-start behavior

When startup or attachment cannot produce a usable authoritative Host:

- The result is a bounded failed-start outcome.
- Failed-start leaves the session without a newly established second Host.
- Failed-start does not imply automatic failover, automatic cross-machine recovery, or automatic reopening of host-boundary decisions.

This artifact does not specify the exact failed-start error surface, retry expectations, or user-facing UX. Those choices belong to downstream execution slices.

## Invariants in force

The following invariants hold for bootstrap, attach, reconnect, and failed-start:

| Invariant | Source |
| --- | --- |
| One active Host per session at all times. | ADR 0002 |
| Bootstrap / attach must never create a second active Host for an existing session. | ADR 0002 + issue #131 |
| Reconnect targets the existing session-bound Host relationship, not a newly elected Host. | Issue #31 / ADR 0005 |
| Host unavailability is distinguished from successful reconnect and does not silently fall back to in-process authority. | Issue #131 |
| Failed-start does not imply automatic failover or automatic cross-machine recovery. | Issue #31 / ADR 0005 |

## Non-goals

This artifact does not:

- implement interfaces, abstract classes, adapters, or concrete runtime components
- define exact Dart method signatures, DTOs, stream primitives, or error catalogs
- choose transport, protocol, IPC, RPC, socket, or wire-format details
- define process-supervision, daemon, or service-manager behavior
- choose OS packaging, installer behavior, or launch mechanism details
- reopen the same-machine out-of-process direction from issue #31
- change ADR 0002 or the one-active-host-per-session invariant
- define cross-machine, internet-facing, multi-tenant, or federated trust models
- define migration sequencing, extraction choreography, or execution steps

Issue #131 is planning/specification only. Implementation, adapter extraction, package creation, and migration remain later slices.
