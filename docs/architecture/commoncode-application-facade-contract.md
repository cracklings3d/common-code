# CommonCode application facade contract

## Status and scope

- Status: planning/specification only
- Change scope: docs-only
- Canonical artifact for issue #42
- Governing prerequisites:
  - `docs/adr/0006-commoncode-layered-architecture-constitution.md`
  - `docs/architecture/commoncode-target-module-package-map.md`
  - `docs/architecture/commoncode-dependency-matrix-and-allowed-imports.md`

This artifact defines the stable CommonCode application-facing contract that Presentation clients depend on for feature behavior. It is a contract-level consequence of the accepted layered constitution, target package map, and dependency matrix. It does not authorize implementation work, concrete API design, dependency-rule changes, migration sequencing, or package extraction.

## Alignment with accepted architecture decisions

This contract realizes existing accepted decisions rather than replacing them.

- It realizes ADR 0006's separation between `Presentation -> Application Facade -> Domain`.
- It realizes issue #40's package ownership by locating the facade contract in `packages/common_code_application`.
- It remains consistent with issue #41 by making Presentation depend on Application-facing APIs instead of concrete persistence or infrastructure packages.
- It does not reopen the accepted layered constitution, target package map, or dependency matrix.

Within that accepted architecture, the CommonCode Application Facade is the stable application-facing contract boundary between Presentation and the underlying Domain plus adapter-backed implementations. It is the `Application Facade` layer named in ADR 0006, not a new architectural layer.

## Why Presentation depends on the Application Facade

Presentation depends on the Application Facade because CommonCode needs platform-specific clients to stay thin while still participating in the same Session and Prompt Thread behavior.

Presentation should depend on the facade because it:

- keeps desktop and other platform-specific Presentation focused on rendering and local interaction handling
- avoids direct coupling to storage, snapshot mechanics, host adapter behavior, OpenCode or other vendor/runtime details, and low-level orchestration internals
- preserves one stable application-facing contract even if adapter implementations or client surfaces change
- makes future replacement, addition, or reduction of client surfaces safer because product behavior stays behind the same application boundary

Presentation therefore does not own product orchestration, persistence access, host execution coordination, or vendor/runtime integrations. Consistent with issue #41, Presentation imports Application-facing APIs and only the domain-facing models needed for rendering.

## Contract responsibilities and boundary

### Application Facade ownership

The CommonCode Application Facade belongs in `packages/common_code_application`.

It owns application-facing use-case coordination and stable state/operation surfaces around:

- Sessions
- attached Clients and Input Client visibility
- Prompt Threads and Turns
- Notifications
- Hosts and Active Host-related application behavior

The facade coordinates product behavior around those concepts without taking ownership of Domain invariants. Domain meaning remains in the Domain layer; concrete persistence, host, observability, and vendor/runtime implementations remain behind Application-defined ports or seams.

### Responsibility split at the boundary

| Layer/boundary participant | Owns | Does not own |
| --- | --- | --- |
| Presentation | rendering, local interaction handling, platform-specific UX, view-specific composition | persistence access, host execution coordination, adapter wiring, vendor/runtime integration, product orchestration |
| Application Facade | use-case coordination, application-facing commands, read surfaces, observation surfaces, renderable operation/result categories | domain invariant ownership, concrete adapter implementation details, platform-specific rendering |
| Domain | product invariants and domain meaning for Session, Client, Prompt Thread, Turn, Notification, Host, and Active Host vocabulary | presentation orchestration, storage mechanics, transport/runtime details, framework-specific implementation |
| Adapters / infrastructure | persistence implementation, host integration, runtime/vendor integration, observability implementation, wiring behind seams | presentation behavior ownership, domain invariant ownership, application-facing contract ownership |

## Contract surface categories

The facade contract is defined as categories of behavior and state, not as exact classes, methods, DTOs, stream types, or file placement details.

### Command categories

Presentation may invoke application-facing command categories such as:

| Category | Contract intent |
| --- | --- |
| Session bootstrap / initialize | start or restore the current client's Session experience so Presentation can render the current Session state |
| Session refresh / re-synchronize | request a fresh application view of current Session state when Presentation needs resynchronization |
| Turn authoring / submission | submit the next authored unit of work into the current Prompt Thread |
| Client-level session actions | perform other application-level client actions related to attached Client participation, notification handling, or authoring availability, without exposing adapter internals |

These categories are motivated by the current desktop slice's initialize, refresh, and submit-style flows, but that current controller shape is current-state context only and is not canonized as the long-term facade API.

### Query and read-surface categories

Presentation may consume stable application-facing read surfaces such as:

| Category | Presentation need |
| --- | --- |
| Current Session view/state | render the overall current Session state for the attached Client |
| Attached Client and Input Client visibility | show which Client is attached and which Client currently owns authoring responsibility |
| Prompt Thread and Turn history visibility | render the Prompt Thread and its Turn progression |
| Notification visibility | render routable Session or Turn notices without knowing delivery mechanics |
| Authoring availability visibility | render whether the current client can author or submit the next Turn |
| Host-related session visibility | show application-facing host status relevant to the Session without exposing host adapter implementation details |

### Observation categories

Presentation may subscribe or listen to conceptual observation surfaces such as:

| Category | Contract intent |
| --- | --- |
| Ongoing Session-state observation | keep the UI synchronized with changes to the current Session view over time |
| Operation-state observation | surface loading, empty, data, error, and submission-progress style states in a renderable form |
| Bounded notice/event observation | surface ephemeral notices or bounded event-style updates when useful for Presentation, without leaking transport semantics |

The contract requires observability at the application boundary, but it does not prescribe whether those surfaces are streams, listenables, subscriptions, callbacks, or another implementation mechanism.

### Outcome and error-state categories

Presentation may depend on application-facing outcome categories such as:

| Category | Contract intent |
| --- | --- |
| Loading | work is in progress and Presentation should render a loading state |
| Empty | there is no current renderable Session content for the relevant view |
| Data / ready | renderable Session data is available |
| Submission in progress | authored work has been accepted for processing and Presentation should reflect in-flight status |
| Recoverable operation failure | Presentation can render failure and permit retry or continued observation without knowing adapter internals |
| Non-renderable internal detail | adapter- or runtime-specific failure details remain behind the facade and are not part of the Presentation contract |

## Hidden concerns and non-exposed details

The facade explicitly hides concerns that Presentation must not coordinate directly, including:

- snapshot and persistence mechanics
- storage schemas, serialization, and durable-local restore details
- concrete host implementation choice, including in-memory versus OpenCode-backed execution
- host adapter selection, execution implementation details, and low-level execution sequencing
- OpenCode or other vendor/runtime request, response, transport, and integration details
- adapter wiring and composition details
- infrastructure and observability implementation details
- internal orchestration choreography used to coordinate Sessions, Prompt Threads, Notifications, and Hosts

Presentation consumes stable application-facing operations and read surfaces rather than directing those hidden concerns itself.

## Current-slice motivation and future-client applicability

The current desktop app is one Presentation client of this facade, not the owner of the contract.

The current shipped desktop slice shows why the contract needs categories for:

- initializing or bootstrapping a Session experience
- observing current Session state over time
- refreshing or re-synchronizing the Session view
- submitting the next authored Turn
- rendering loading, empty, data, error, and submission-progress states

Those existing controller and `host_core` seams are transitional current-state context only. They help motivate the contract categories, but they do not define the canonical future facade.

Because the facade is application-facing rather than platform-specific, desktop and future alternative clients can depend on the same command, read, observation, and outcome categories while rendering differently for their own Platforms, Presentation Profiles, and Presentation Capabilities. This stabilizes application-facing behavior even as Presentation surfaces, host adapters, storage implementations, and vendor/runtime integrations evolve.

## Non-goals

This artifact does not:

- implement a facade, controller, port, adapter, or package
- define concrete method signatures, Dart classes, DTO catalogs, exact stream primitives, or dependency injection mechanics
- authorize code changes in `apps/**` or `packages/**`
- define storage schemas, adapter behavior, OpenCode integration behavior, or notification transport semantics
- define migration sequencing, extraction choreography, or refactor steps from the current desktop slice
- change ADR 0006, the target package map, or the dependency/import rules from issues #40 and #41

Issue #42 is planning/specification only. Implementation remains a later slice.
