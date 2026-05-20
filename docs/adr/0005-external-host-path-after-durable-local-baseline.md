# External host path after durable local baseline

## Status

Proposed

## Context and trigger

Issue #30 established durable local Host continuity as the authoritative baseline for restart continuity on the local desktop path. CommonCode now has a canonical local path that preserves Session state, Turn state, and Notification acknowledgement/replay state across app restarts without reopening the Session or changing the Active Host model.

The next decision is where the first external Host boundary should be drawn. That decision is needed now so later implementation slices can move beyond an in-process desktop runtime without reopening the core Session/Host contract each time transport or bootstrap work is discussed.

This ADR is the canonical decision artifact for that boundary. It remains consistent with:

- `contexts/session-orchestration/CONTEXT.md`
- `contexts/execution/CONTEXT.md`
- `docs/adr/0001-three-core-contexts.md`
- `docs/adr/0002-one-active-host-per-session.md`
- `docs/adr/0004-session-notification-semantics.md`
- issue #30 as the durable local precursor baseline

## Fixed invariants and governing artifacts

The following remain fixed for this decision:

- The three core contexts from ADR 0001 remain in force.
- Existing Session, Client, Prompt Thread, Turn, Notification, Host, Host Machine, and Active Host vocabulary remains in force.
- ADR 0002 remains in force: a Session has exactly one Active Host at a time unless a later ADR explicitly changes that rule.
- Issue #30 remains the completed durable local baseline rather than an open design variable.
- Notification semantics from ADR 0004 remain unchanged.

This ADR does not reconsider multi-host execution, host migration between machines, or moving authority away from the Session/Active Host model.

## Decision drivers and options considered

### Drivers

- Preserve the one-active-host-per-session model while introducing an external Host boundary.
- Keep the first external step close to the durable local baseline from issue #30.
- Make reconnection behavior explicit for attached Clients that outlive individual app processes.
- Keep trust and identity assumptions narrow enough for an initial external Host slice.
- Avoid turning this decision into a full remote/distributed roadmap.

### Option A: same-machine out-of-process Host on the current Host Machine

Move the Host out of the desktop client process into a dedicated Host process on the same Host Machine, while keeping the first external boundary local to that machine.

### Option B: directly adopt a network-addressable remote Host

Make the next step a remote or server-addressable Host reachable across a wider network boundary.

### Rejected alternative

Option B is rejected for the next slice. It adds a larger trust boundary, stronger identity/auth requirements, and broader failure cases before the process boundary itself has been stabilized. It would force the project to decide remote reachability, network transport expectations, and cross-machine authority too early.

## Decision

The next external Host direction is **a same-machine, out-of-process Host running on the current Host Machine**.

### Process boundary

The Host moves from an in-process desktop runtime to a dedicated external Host process. The desktop client remains a Client and no longer owns Host execution by sharing its own process. The Host still runs on the same Host Machine for the first external slice.

### Client-to-Host connection model

Attached Clients connect to the authoritative Host through a local machine-scoped connection to that dedicated Host process. The connection model is attach/re-attach to the same Session-bound Active Host rather than spawning a new Host per client attach. The connection is architectural only here: this ADR decides a local client-to-host attachment model, not transport or protocol wiring.

### Failure model

- Client process failure or disconnect does not transfer Host authority and does not create a second Host for the Session.
- If the Host process remains alive, attached Clients are expected to reconnect to that same authoritative Host and resume observing or authoring the same Session.
- If the Host process fails or becomes unavailable, the Session loses its available Active Host until that Host is restored or a later recovery path rebinds the Session explicitly.
- Host failure does not imply automatic failover, automatic migration to a different machine, or automatic resumption of in-flight execution beyond what the durable local baseline already preserves.

### Reconnection expectations

- Clients may detach and later reattach to the same Session while the same Active Host remains authoritative.
- Reconnection targets the existing Session/Active Host relationship, not a newly elected host.
- If the Host stayed alive, reconnection should restore client attachment to the live Host-owned Session state.
- If the Host was unavailable and later becomes available again on the same Host Machine, clients may reconnect to that restored authoritative Host without changing the Session's single-active-host invariant.

## Architectural trust boundary / identity / auth / security assumptions

The first external Host slice introduces a process boundary, not an internet-facing trust boundary.

- **Trust boundary**: the initial boundary is between local Clients and a dedicated Host process on the same Host Machine. The machine remains the outer trust environment for this slice.
- **Identity authority**: Session identity remains authoritative at the Session/Client layer; the Host does not redefine who the User or Identity is.
- **Host authority**: once a Session is bound to an Active Host, that Host remains authoritative for processing the Session's active Turn.
- **Authentication assumption**: only local clients acting within the same machine trust domain are assumed eligible to attach to the Host in this first slice.
- **Authorization assumption**: authorization remains bounded to attaching an eligible local Client to its Session's already-authoritative Host rather than arbitrating multi-tenant remote access.
- **Security assumption**: the first slice assumes same-machine controls are the primary protection boundary. Cross-user attachment, internet exposure, service-to-service federation, and remote tenant isolation are not solved by this ADR.

## Migration from durable local baseline

Migration proceeds conceptually by keeping the durable local continuity model from issue #30 authoritative while moving Host execution behind a same-machine process boundary.

- The durable local baseline remains the continuity anchor for Session, Turn, and Notification state.
- The first conceptual change is where the Host runtime lives: out of the desktop client process and into a dedicated Host process on the same Host Machine.
- Session semantics, one-active-host-per-session, and reconnectable-client behavior stay stable across that move.
- Later implementation slices may build on this boundary to define concrete bootstrap, attachment, and recovery mechanisms without reopening whether the next external Host step is same-machine out-of-process versus directly remote.

This ADR does not define rollout choreography, migration sequencing, or execution steps.

## First implementation-slice non-goals / out of scope

Out of scope for the first implementation slice under this ADR:

- network-addressable remote Host deployment
- transport selection or rollout
- RPC, IPC, or protocol message design
- daemon/process supervision implementation
- automatic failover or host migration to another Host Machine
- changing desktop or other client application behavior beyond what is required to attach to an external Host boundary
- revisiting Session, Notification, or one-active-host-per-session semantics

## Consequences / follow-up slices

- Later slices can implement an external Host boundary without re-deciding whether the first boundary is local out-of-process or directly remote.
- Later slices still need concrete attachment/bootstrap behavior, concrete recovery behavior, and protocol details.
- A later ADR would be required before broadening the Host boundary to cross-machine or network-addressable remote hosting, or before reconsidering ADR 0002.
