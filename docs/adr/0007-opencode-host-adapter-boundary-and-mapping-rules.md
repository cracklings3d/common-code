# OpenCode host adapter boundary and mapping rules

## Status

Proposed

## Context and trigger

Issue #44 requires one canonical architecture decision that defines the OpenCode host adapter boundary and mapping rules without collapsing CommonCode semantics into OpenCode semantics.

This ADR stays inside the already accepted same-machine external-host direction and exists to make later adapter work reviewable without reopening product semantics, package ownership, or dependency direction.

## Fixed invariants and governing artifacts

The following remain in force and are not reopened here:

- `CONTEXT-MAP.md`, `GLOSSARY.md`, `contexts/session-orchestration/CONTEXT.md`, `contexts/execution/CONTEXT.md`, and `contexts/presentation/CONTEXT.md` remain the governing vocabulary and context inputs for Session, User, Identity, Client, Prompt Thread, Turn, Notification, Host, Active Host, Host Machine, Platform, and Presentation terms.
- Issue #30 remains the durable-local continuity baseline and is not reopened.
- ADR 0004 remains in force: Notification semantics are Session-owned and Presentation owns rendering behavior.
- ADR 0005 remains the governing same-machine, machine-local, out-of-process external-host boundary.
- ADR 0006 remains in force: OpenCode is infrastructure behind an adapter seam and the governing inward direction remains `Presentation -> Application Facade -> Domain`.
- Issue #40 remains in force: OpenCode-specific host code belongs in `packages/host_opencode` and not in Domain, Application, persistence, observability, or Flutter presentation code.
- Issue #41 remains in force: Application depends on stable ports rather than concrete adapters, and Presentation feature behavior does not depend directly on adapter internals.
- Issue #42 remains in force: Presentation depends on the Application Facade as the only stable presentation-facing boundary.
- Issue #43 remains in force: host gateway, session observation, identity context, and observability / diagnostics are Application-owned contract concerns implemented by adapters beneath the facade boundary.

## Inherited decisions from accepted architecture

The following decisions are inherited and are not newly decided by issue #44.

| Decision | Decision status | Source |
| --- | --- | --- |
| Durable local continuity remains the completed baseline for restart behavior. | Inherited from accepted prerequisites | Issue #30 |
| Notification semantics remain Session-owned and are not owned by a host runtime or presentation surface. | Inherited from accepted prerequisites | ADR 0004 |
| The first external-host step remains same-machine, out-of-process, and machine-local. | Inherited from accepted prerequisites | ADR 0005 |
| OpenCode belongs to infrastructure behind an adapter seam rather than to the product model. | Inherited from accepted prerequisites | ADR 0006 |
| OpenCode-specific host code belongs in `packages/host_opencode`. | Inherited from accepted prerequisites | Issue #40 |
| Application defines stable ports and must not depend on concrete adapters; adapters depend inward on Application and Domain. | Inherited from accepted prerequisites | Issue #41 |
| Presentation depends on the Application Facade rather than on OpenCode concepts or adapter types. | Inherited from accepted prerequisites | Issue #42 |
| Host gateway, session observation, identity context, and observability / diagnostics remain Application-owned contract concerns. | Inherited from accepted prerequisites | Issue #43 |

## New decisions introduced by issue #44

The following decisions are new in issue #44.

| Decision | Decision status | Source |
| --- | --- | --- |
| The OpenCode adapter owns infrastructure translation only and does not own product semantics. | New in issue #44 | This ADR |
| Allowed 1:1 mapping is limited to adapter-local infrastructure handles or identifiers whose semantics are fully preserved across the boundary. | New in issue #44 | This ADR |
| Thin-alias treatment of CommonCode product semantics across the OpenCode boundary is explicitly forbidden. | New in issue #44 | This ADR |
| OpenCode-backed host behavior must satisfy Application-owned contracts without exporting OpenCode vocabulary upward into Application, Domain, or Presentation. | New in issue #44 | This ADR |

## Decision

### Architectural role of OpenCode

OpenCode is an infrastructure runtime behind the CommonCode host adapter seam.

- OpenCode is not the CommonCode product model.
- OpenCode may provide runtime primitives used to back host behavior.
- CommonCode retains semantic ownership of Session, User, Identity, Client, Prompt Thread, Turn, Notification, Host, and Active Host concepts even when OpenCode supplies a backing runtime primitive.
- This decision remains bounded to ADR 0005's same-machine external-host direction and does not reopen whether the next host step is local versus remote.

### Adapter responsibilities

The OpenCode adapter belongs below the Application Facade and implements Application-owned contracts from issue #43.

Responsibilities inside the OpenCode adapter are limited to:

- translating between the Application-owned host gateway contract and OpenCode runtime operations
- translating between the Application-owned session observation contract and OpenCode runtime observation mechanisms
- preserving adapter-local OpenCode runtime handles, identifiers, and other integration state needed to interact with the OpenCode runtime
- performing OpenCode-specific integration glue needed to satisfy Application-owned contracts while keeping CommonCode vocabulary canonical above the adapter seam

The OpenCode adapter does not own:

- Domain invariants
- Session, User, or Identity authority
- Notification semantics
- Host or Active Host semantic authority
- Prompt Thread or Turn semantics
- Application Facade behavior or presentation-facing contracts
- persistence ownership
- observability / diagnostics contract ownership
- product naming or vocabulary authority

### Allowed mappings

Allowed 1:1 mapping across the OpenCode boundary is narrow.

- 1:1 mapping is allowed only for adapter-local infrastructure handles or identifiers whose semantics are fully preserved across the boundary.
- Any such mapping remains an adapter implementation detail rather than a product-semantic alias.
- CommonCode names remain canonical on the Application and Domain side even when OpenCode exposes a structurally similar runtime primitive.
- Mapping must preserve the meaning required by the Application-owned contracts rather than exporting OpenCode vocabulary upward.

Examples of the allowed class include runtime handles, subscription tokens, process references, or correlation identifiers that are needed only so the adapter can continue talking to the OpenCode runtime without changing CommonCode product meaning.

### Forbidden mappings

The following CommonCode concepts must not be treated as thin aliases of OpenCode concepts:

- User or Identity
- Session or Session authority
- Prompt Thread or Turn semantics
- Notification semantics
- Host or Active Host authority
- Application Facade concepts or presentation-facing contract concepts

OpenCode runtime primitives may back those responsibilities operationally, but CommonCode remains the canonical semantic owner.

The adapter must not:

- redefine Session meaning in OpenCode terms
- treat OpenCode identity/runtime concepts as canonical CommonCode identity
- let OpenCode observation/event vocabulary become the canonical Session observation model
- let OpenCode host/runtime concepts replace CommonCode Host authority semantics
- leak OpenCode DTOs, runtime types, or vendor terminology into Presentation, Application, or Domain contracts

### Package placement and dependency alignment

OpenCode-specific code belongs in `packages/host_opencode`.

- `packages/common_code_application` owns the stable contracts the OpenCode adapter satisfies.
- `packages/common_code_domain` remains pure and free of OpenCode concerns.
- `packages/common_code_persistence` does not become the home of OpenCode runtime behavior.
- `packages/common_code_observability` does not become the owner of OpenCode host semantics or contract definitions.
- `apps/common_code_desktop` remains a Presentation/app-shell client of Application and must not become the owner of OpenCode semantics or adapter internals.

Dependency direction remains aligned to issues #39, #40, and #41:

- Presentation continues to depend on the Application Facade.
- Application continues to define stable ports and depend on Domain rather than on concrete adapters.
- `packages/host_opencode` depends inward on Application-owned contracts and Domain as needed to implement the adapter path.

### Application-port alignment

The OpenCode adapter implements Application-owned contracts rather than defining them.

- The host gateway contract remains Application-owned, and the OpenCode adapter is one implementing adapter path.
- Session observation remains an Application-owned contract concern implemented on the host-adapter side, including the OpenCode adapter path.
- Identity context remains Application-owned or outer-boundary contract territory and is not redefined by the OpenCode adapter.
- Observability / diagnostics remain separate Application-owned concerns and are not collapsed into OpenCode runtime semantics.
- Presentation continues to depend on the Application Facade instead of on OpenCode concepts, OpenCode types, or adapter-local abstractions.

### Trust-boundary and semantic-ownership constraints

This ADR inherits and preserves the current trust boundary.

- Issue #30 remains the durable-local continuity baseline and is not reopened.
- ADR 0005 remains the governing same-machine, machine-local, out-of-process host boundary.
- ADR 0004 Notification semantics remain unchanged.
- Session, User, and Identity authority remain owned by CommonCode at the Session/Client layer.
- This issue does not define remote authentication, cross-machine trust, multi-tenant access, federated host authority, or internet-facing host behavior.

### Non-goals / out of scope

This ADR does not decide:

- transport, IPC, RPC, protocol, or bootstrap details
- process supervision or runtime wiring details
- cross-machine trust, remote auth, or multi-tenant security design
- concrete Dart APIs, DTOs, class names, field lists, or runtime types
- package creation, file moves, code changes, or migration sequencing

## Consequences / follow-up slices

- Later implementation slices may build `packages/host_opencode` as an adapter that satisfies Application-owned contracts without reopening product semantics.
- Later slices still need concrete adapter APIs, runtime wiring, and transport/bootstrap design if and when they are explicitly authorized.
- Reviewers can reject future work that leaks OpenCode vocabulary or runtime types upward into Application, Domain, or Presentation because this ADR makes that boundary explicit.
