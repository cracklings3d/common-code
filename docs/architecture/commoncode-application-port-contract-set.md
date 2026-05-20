# CommonCode application port contract set

## Status and scope

- Status: planning/specification only
- Change scope: docs-only
- Canonical artifact for issue #43
- Deliverable scope: define the Application-owned port contract surface that the CommonCode Application Facade uses for session orchestration and related coordination

This artifact defines contract boundaries only. It does not authorize interface implementation, adapter extraction, package creation, migration sequencing, concrete API signatures, transport choices, storage-engine choices, or code changes in `apps/**` or `packages/**`.

## Pinned prerequisite baseline

This artifact is a consequence of accepted prerequisites and does not replace them.

| Issue | Pinned prerequisite artifact | Inherited decision reused here |
| --- | --- | --- |
| #39 | `6685aafb4e921a27fdfd8fc0ff361ecc9035d4d8:docs/adr/0006-commoncode-layered-architecture-constitution.md` | CommonCode uses the governing `Presentation -> Application Facade -> Domain` direction, while persistence and infrastructure adapters depend inward behind seams. |
| #40 | `ee4499cef5e8f6800a59cab968816f27e543e628:docs/architecture/commoncode-target-module-package-map.md` | `packages/common_code_application` owns stable application-facing orchestration and ports; host, persistence, and observability implementations live in the accepted adapter-side packages. |
| #41 | `4c0bff7b2346364db0cac91b8180c528e649e4cf:docs/architecture/commoncode-dependency-matrix-and-allowed-imports.md` | Application defines stable ports and must not depend on concrete adapters; adapters depend inward on Application and Domain. |
| #42 | `258110f7ecc91e5f6b1e7f90f2e0dd70e2d2c48e:docs/architecture/commoncode-application-facade-contract.md` | Presentation depends on the Application Facade as the stable boundary, and the facade coordinates lower-level work through contracts beneath that boundary. |

## Inherited decisions from accepted architecture

The following decisions are inherited from accepted prerequisites and are not newly decided by issue #43.

| Decision | Decision status | Source |
| --- | --- | --- |
| Presentation remains thin and depends on the Application Facade rather than on persistence or infrastructure implementations for feature behavior. | Inherited from accepted prerequisites | ADR 0006 (#39), facade contract (#42), dependency matrix (#41) |
| The Application Facade is a distinct layer that coordinates use cases around Sessions, Prompt Threads, Notifications, Hosts, and related product behavior. | Inherited from accepted prerequisites | ADR 0006 (#39), facade contract (#42) |
| `packages/common_code_application` is the target package that owns application-facing orchestration plus stable ports around the Domain. | Inherited from accepted prerequisites | target package map (#40) |
| `packages/common_code_persistence`, `packages/common_code_observability`, `packages/host_in_memory`, and `packages/host_opencode` are adapter-side packages that depend inward on Application-owned contracts. | Inherited from accepted prerequisites | target package map (#40), dependency matrix (#41) |
| Application may depend on Domain and on stable abstractions it defines, but must not depend on concrete adapter packages or app-shell code. | Inherited from accepted prerequisites | ADR 0006 (#39), dependency matrix (#41) |
| Current `packages/host_core` and desktop runtime seams are transitional current-state context, not canonical target package ownership. | Inherited from accepted prerequisites | target package map (#40), dependency matrix (#41), facade contract (#42) |

## New decisions introduced by issue #43

Issue #43 adds the bounded contract-surface decisions below the accepted facade boundary.

| Decision | Decision status | Source |
| --- | --- | --- |
| The canonical Application-owned port set beneath the facade consists of five explicit concerns: host gateway, session store, session observation, identity context, and observability/diagnostics. | New in issue #43 | This artifact |
| Session observation is a first-class contract surface rather than an implicit behavior hidden inside another port. | New in issue #43 | This artifact |
| Session observation adapters belong on the accepted host-adapter side (`packages/host_in_memory`, `packages/host_opencode`) rather than in persistence, presentation, or a newly invented package. | New in issue #43 | This artifact |
| Identity is a required contract concern, but this slice limits it to session-bound identity/client-context resolution under existing trust assumptions and does not expand the accepted package map. | New in issue #43 | This artifact |
| Each canonical port is defined by purpose, owning layer, owning package, supported behavior categories, excluded responsibilities, and expected adapter category. | New in issue #43 | This artifact |

## Why the Application Facade depends on ports

The Application Facade defined in issue #42 remains the only stable boundary that Presentation depends on. The facade coordinates session orchestration through inward-facing Application-owned ports rather than through concrete adapters.

This separation keeps responsibilities explicit:

- Presentation depends on the facade, not directly on ports or concrete adapter implementations.
- `packages/common_code_application` owns the port contracts and may depend on Domain, but not on concrete persistence, observability, host, or app-shell packages.
- Concrete adapters depend inward on the Application-owned contracts and Domain as needed.
- The facade can coordinate session bootstrap, refresh, submission, observation, identity lookup, persistence access, and diagnostics without exposing infrastructure details to Presentation.

## Canonical application port set

| Canonical port concern | Why it exists beneath the facade | Expected implementing adapter category |
| --- | --- | --- |
| Host gateway port | Coordinate Application-needed host execution interactions for session work. | Host adapters in `packages/host_in_memory` and `packages/host_opencode` |
| Session store port | Provide durable session continuity access needed by orchestration flows. | Persistence adapters in `packages/common_code_persistence` |
| Session observation port | Observe active-session changes needed to keep facade state current over time. | Runtime-facing host adapters in `packages/host_in_memory` and `packages/host_opencode` |
| Identity context port | Resolve session-bound identity and attached-client context needed by orchestration. | Outer adapter/app-shell implementations, with any dedicated package decision deferred |
| Observability / diagnostics port | Record bounded operational diagnostics about orchestration activity. | Observability adapters in `packages/common_code_observability` |

## Port definitions

All ports below are owned by the `Application Facade` layer and belong in `packages/common_code_application`.

### Host gateway port

- **Purpose**: gives the Application layer a stable way to coordinate host execution needed for session work.
- **Architectural owner**: Application Facade layer.
- **Target package owner**: `packages/common_code_application`.
- **Supported behavior categories**:
  - request or forward authored work for host processing
  - interact with the active host path needed for session work execution
  - obtain host-driven session effects needed by Application orchestration
  - support host-facing coordination needed by session bootstrap or turn handling
- **Intentionally excluded responsibilities**:
  - domain invariant ownership
  - persistence mechanics
  - presentation behavior
  - OpenCode-specific runtime details in the contract itself
- **Expected implementing adapters**: host-side adapters in `packages/host_in_memory` and `packages/host_opencode`.

### Session store port

- **Purpose**: gives the Application layer durable session continuity access needed to initialize, restore, refresh, or replace orchestration state.
- **Architectural owner**: Application Facade layer.
- **Target package owner**: `packages/common_code_application`.
- **Supported behavior categories**:
  - load or restore session state needed by the Application layer
  - persist or replace session snapshots/state when orchestration requires it
  - provide repository-style access to session continuity data
- **Intentionally excluded responsibilities**:
  - host execution behavior
  - presentation-state shaping
  - storage-engine, schema, or serialization details in the contract itself
- **Expected implementing adapters**: persistence adapters in `packages/common_code_persistence`.

### Session observation port

- **Purpose**: gives the Application layer explicit observation of active-session changes needed to keep facade state synchronized over time.
- **Architectural owner**: Application Facade layer.
- **Target package owner**: `packages/common_code_application`.
- **Supported behavior categories**:
  - watch or subscribe to session changes relevant to facade state
  - receive session update flows, events, or snapshots in a contract-level way
  - support refresh or resubscribe behavior needed by the Application layer
- **Intentionally excluded responsibilities**:
  - commitment to a specific stream, listenable, callback, or subscription primitive
  - presentation-layer subscription mechanics
  - concrete transport or runtime implementation details
- **Expected implementing adapters**: runtime-facing host adapters in `packages/host_in_memory` and `packages/host_opencode`.

Session observation is an explicit contract surface, not an implicit side effect of another port. App-shell glue may subscribe through the facade, but the implementing adapter category for the port itself is the accepted host-adapter side rather than persistence, presentation, or a new package.

### Identity context port

- **Purpose**: gives the Application layer the session-bound identity and attached-client context it needs for orchestration.
- **Architectural owner**: Application Facade layer.
- **Target package owner**: `packages/common_code_application`.
- **Supported behavior categories**:
  - resolve the current identity bound to a session
  - resolve the current client or attached-client context needed for orchestration
  - surface identity/context information needed by session bootstrap or command handling
- **Scope limit**: this port is limited to resolving session-bound identity/client context under existing trust assumptions for the running client/session path.
- **Intentionally excluded responsibilities**:
  - sign-in UI
  - authentication behavior or protocol details
  - authorization behavior, policy, or permission decisions
  - vendor SDK details
  - package-map expansion beyond what issue #40 accepted
- **Expected implementing adapters**: outer adapter or app-shell implementations, while any dedicated future identity package decision is deferred to a later accepted architecture slice.

### Observability / diagnostics port

- **Purpose**: gives the Application layer a bounded sink for operational diagnostics about orchestration activity.
- **Architectural owner**: Application Facade layer.
- **Target package owner**: `packages/common_code_application`.
- **Supported behavior categories**:
  - record operational events
  - record warnings and failures
  - emit tracing or telemetry hooks
  - record bounded diagnostics about orchestration activity
- **Intentionally excluded responsibilities**:
  - user-facing Notification semantics from the Domain model
  - presentation toast, snackbar, or other UI behavior
  - vendor-specific telemetry framework details in the contract itself
- **Expected implementing adapters**: observability adapters in `packages/common_code_observability`.

## Adapter placement and dependency direction

This artifact realizes accepted architecture rather than redefining it.

- `packages/common_code_application` owns these port contracts and may depend on Domain, but not on concrete adapter packages.
- Host adapters in `packages/host_in_memory` and `packages/host_opencode` implement host-related contracts from the adapter side, including the host gateway port and the session observation port.
- Persistence adapters in `packages/common_code_persistence` implement the session store port.
- Observability adapters in `packages/common_code_observability` implement the observability / diagnostics port.
- Identity remains an outer adapter or app-shell concern in this slice; this artifact defines the contract need without inventing a new canonical package-map entry.
- `apps/common_code_desktop` and other Presentation clients continue to depend on the Application Facade for feature behavior, not directly on these port implementations.

This keeps issue #43 aligned with the accepted architecture:

- ADR 0006 (#39): preserves Application-vs-adapter separation.
- Target package map (#40): keeps contracts in `packages/common_code_application` and implementations in accepted adapter-side packages.
- Dependency matrix (#41): keeps Application dependent on ports rather than on concrete host, persistence, or observability implementations.
- Facade contract (#42): defines the lower-level contracts the facade uses beneath the presentation-facing boundary.

## Current-seam notes

Current seams motivate this contract set but do not define it.

- The current `packages/host_core` seam is transitional and currently mixes concerns that the target architecture separates into Application-owned ports plus adapter implementations.
- The current desktop runtime, snapshot-store, and durable-local bootstrap seams in `apps/common_code_desktop` are current-state implementation context, not the canonical contract surface.
- The current `HostService` surface combines session creation/bootstrap, client attachment, session watch/read, restore, and turn submission in one seam. That current overlap is evidence that the target architecture needs multiple explicit ports.
- The current `HostService.watchSession(...)` behavior demonstrates the need for a session observation contract, but this artifact does not canonize the current API shape, stream primitive, or runtime implementation as the target contract.

## Non-goals

This artifact does not:

- implement interfaces, abstract classes, adapters, repositories, gateways, or facades
- define exact Dart method signatures, DTOs, generic types, stream primitives, or error catalogs
- create packages, change the accepted package map, or normalize `packages/host_core` as a target package
- define migration sequencing, extraction choreography, or refactor steps from current seams to target seams
- choose transport, protocol, storage-engine, OpenCode integration, or dependency-injection mechanics
- change ADR 0006 or the accepted artifacts from issues #40, #41, or #42

Issue #43 is planning/specification only. Implementation, adapter extraction, package creation, and migration remain later slices.
