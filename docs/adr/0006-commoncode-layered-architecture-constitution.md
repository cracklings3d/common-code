# CommonCode layered architecture constitution

## Status

Accepted

## Context and trigger

CommonCode already has stable domain language for Session Orchestration, Execution, and Presentation in `CONTEXT-MAP.md`, the three context documents, and ADRs 0001, 0002, 0004, and 0005. Those artifacts establish the meaning of **Session**, **Client**, **Prompt Thread**, **Notification**, **Host**, **Host Machine**, **Active Host**, and **Presentation**, but they do not yet define one canonical layered architecture constitution for the codebase.

Issue #39 exists to create that constitution as a governance artifact only. This ADR sets the target layer boundaries that future planning and implementation slices must follow without turning this issue into package mapping, contract design, dependency enforcement, migration planning, or refactor work.

## Fixed invariants and governing artifacts

The following remain in force and are not reopened by this ADR:

- `CONTEXT-MAP.md` remains the bridge between the broader domain language and the currently shipped durable-local desktop slice.
- `contexts/session-orchestration/CONTEXT.md` remains the source of truth for Session, Client, Prompt Thread, Turn, Input Client, and Notification vocabulary.
- `contexts/execution/CONTEXT.md` remains the source of truth for Host, Host Machine, and Active Host vocabulary.
- `contexts/presentation/CONTEXT.md` remains the source of truth for Platform, Presentation Profile, and Presentation Capability vocabulary.
- ADR 0001 remains in force: CommonCode has the three core contexts Session Orchestration, Execution, and Presentation.
- ADR 0002 remains in force: a Session binds to one Active Host at a time.
- ADR 0004 remains in force: Notification semantics are Session-level, while rendering behavior belongs to Presentation.
- ADR 0005 remains in force: Host integration details can evolve in later slices without redefining the product domain vocabulary.

This ADR governs layering across those artifacts. It does not replace their domain meanings.

## Decision

### Canonical layers

CommonCode's governing target layered constitution is:

1. **Infrastructure / Observability**
2. **Persistence / Data**
3. **Domain**
4. **Application Facade**
5. **Presentation**

These layers define architectural responsibilities, dependency direction, and future planning boundaries. They do not yet assign package ownership, file placement, or enforcement mechanics.

### One-way dependency direction

The governing dependency shape is one-way and reads top-down as `Presentation -> Application -> Domain`.

- **Presentation** may depend only on Application-facing APIs and models needed to render and interact with a Client on a Platform.
- **Application Facade** depends on **Domain** and on stable abstractions needed to coordinate use cases around Sessions, Prompt Threads, Notifications, Hosts, and related product behavior.
- **Domain** is inward-facing and remains pure. It does not depend on Presentation, Application, Persistence / Data, Infrastructure / Observability, Flutter, storage, transport, OpenCode concerns, or observability frameworks.
- **Persistence / Data** and **Infrastructure / Observability** provide outward-facing implementations behind adapter seams. They may depend inward on Domain concepts and on stable abstractions defined for coordination, but Domain does not depend back on their storage, transport, runtime, logging, telemetry, or vendor details.

No layer may reverse this direction by pulling Domain policy outward into framework or runtime concerns.

### Layer responsibilities

- **Presentation** owns platform-specific rendering and interaction only. It presents Session state, Prompt Thread state, Notification state, and authoring affordances for a Client on a Platform. It may contain presentation-specific rendering behavior, but it does not own persistence, host logic, or product orchestration.
- **Application Facade** owns use-case coordination and product orchestration around the Domain model. It is the layer Presentation talks to when authoring, observing, refreshing, or coordinating product behavior across Sessions, Clients, Notifications, and Hosts. Application is a separate layer from Domain and is not synonymous with the product model itself.
- **Domain** owns the pure product model and invariants for CommonCode. It expresses the meaning and rules of Sessions, Clients, Prompt Threads, Turns, Notifications, Hosts, and Active Host relationships without depending on UI frameworks, storage frameworks, transport protocols, OpenCode-specific concerns, or observability tooling.
- **Persistence / Data** owns storage-facing representations and repository or data-access implementations that load, save, restore, or query product state. It translates between durable storage concerns and the inward-facing model without making storage shape the Domain.
- **Infrastructure / Observability** owns external runtimes, host integrations, transports, logging, telemetry, process/runtime adapters, and similar operational concerns. It is where machine-facing and vendor-facing details live without redefining the Domain or the Application Facade.

### OpenCode placement

OpenCode belongs to **Infrastructure / Observability** behind an adapter seam. It is an external runtime or integration concern used to support CommonCode behavior; it is not the CommonCode product model, not the Domain, and not the Application Facade.

### Non-goals / out of scope

This ADR intentionally does not decide:

- package boundaries, package maps, or ownership matrices
- dependency matrices, rule tables, or CI enforcement mechanics
- concrete contracts, adapter interfaces, DTOs, transport protocols, or API surfaces
- migration planning, rollout choreography, or refactor sequencing
- implementation work or code changes to enforce the constitution

## Consequences / follow-up slices

- Future planning slices should map the constitution to concrete package boundaries without reopening the layer model itself.
- Future planning slices still need to define dependency enforcement mechanisms and any concrete rule tables required to uphold this constitution.
- Future planning slices still need to define concrete contracts and adapter seams for persistence, host integration, transport, and other infrastructure work.
- Future planning slices still need to decide migration sequencing and any implementation or refactor slices required to move existing code toward this constitution.
- Later implementation work must keep Presentation thin, keep Application separate from Domain, and keep Domain pure while honoring the existing Session, Host, and Notification vocabulary already established in the governing artifacts.
