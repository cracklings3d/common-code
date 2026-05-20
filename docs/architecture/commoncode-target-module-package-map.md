# CommonCode target module and package map

## Status and scope

This artifact is the canonical target module and package map for issue #40.

- Status: planning/specification only
- Change scope: docs-only
- Governing prerequisite: the accepted CommonCode layered architecture constitution from issue #39, recorded in `docs/adr/0006-commoncode-layered-architecture-constitution.md`
- Follow-on boundary: issue #41 remains responsible for the full dependency matrix, import-policy wording, architecture-violation examples, and enforcement mechanics

This document defines target package ownership and high-level dependency allowances for the next architecture phase. It does not authorize package creation, file moves, import changes, refactors, or migration sequencing.

## Alignment with the accepted architecture constitution

This target package map realizes the accepted CommonCode layered architecture constitution from issue #39 rather than replacing it.

- `packages/common_code_domain` is the Domain layer package.
- `packages/common_code_application` is the Application Facade layer package.
- `packages/common_code_persistence`, `packages/host_in_memory`, and `packages/host_opencode` live on the adapter/infrastructure side of the constitution.
- `packages/common_code_observability` belongs to Infrastructure / Observability support.
- `apps/common_code_desktop` is the desktop app-shell and presentation host, not a product-core package.

The governing layer intent remains:

- Presentation -> Application Facade -> Domain
- Persistence / Data and Infrastructure / Observability stay behind adapter seams and depend inward as needed
- Domain remains pure and framework-independent

## Canonical target package map

| Target module/package | Category | Layer alignment | High-level role |
| --- | --- | --- | --- |
| `packages/common_code_domain` | `product-core` | Domain | Pure product model and invariants |
| `packages/common_code_application` | `product-core` | Application Facade | Use cases, orchestration, and stable ports around the domain |
| `packages/common_code_persistence` | `adapter` | Persistence / Data | Storage-facing adapters and persistence translation |
| `packages/common_code_observability` | `support infrastructure` | Infrastructure / Observability | Logging, telemetry, tracing, and instrumentation support |
| `packages/host_in_memory` | `adapter` | Infrastructure adapter | In-memory host adapter/runtime path |
| `packages/host_opencode` | `adapter` | Infrastructure adapter | OpenCode-facing host adapter/runtime path |
| `apps/common_code_desktop` | `app-shell` | Presentation host | Desktop presentation, bootstrap, and app-edge wiring |

## Package definitions

### `packages/common_code_domain`

- Category: `product-core`
- Responsibility: owns the pure CommonCode product model and invariants.
- Belongs here:
  - entities, value objects, and failures for Sessions, Clients, Prompt Threads, Turns, Notifications, Hosts, and Active Host relationships
  - domain rules that preserve Session, Prompt Thread, Turn, Notification, and Host meaning from the governing context documents
- Does not belong here:
  - Flutter UI or presentation shaping
  - application use-case orchestration or facades
  - storage adapters, serialization helpers, or repository implementations
  - OpenCode integration or in-memory host runtime behavior
  - logging, telemetry, tracing, or runtime wiring
- Allowed dependencies:
  - may depend on no internal CommonCode package
  - must remain pure and framework-independent

### `packages/common_code_application`

- Category: `product-core`
- Responsibility: owns application-facing use cases, orchestration, facades, and stable ports around the Domain.
- Belongs here:
  - application services, commands, queries, coordination flows, and facade APIs used by presentation
  - stable ports and interfaces consumed by persistence, host, and observability adapters
  - reusable orchestration around Sessions, Clients, Prompt Threads, Notifications, and Hosts without taking ownership of domain invariants
- Does not belong here:
  - domain invariant ownership
  - Flutter widgets or desktop-only bootstrap code
  - concrete OpenCode code
  - concrete persistence implementations
  - package-local app composition details
- Allowed dependencies:
  - may depend on `packages/common_code_domain`
  - must not depend on concrete persistence, host, observability, or Flutter app packages

### `packages/common_code_persistence`

- Category: `adapter`
- Responsibility: owns storage-facing adapters and translation between durable/local storage concerns and the inward-facing model.
- Belongs here:
  - repository implementations
  - snapshot stores
  - storage DTO and serialization helpers
  - persistence mappers and storage-facing translation code
- Does not belong here:
  - domain rule ownership
  - desktop widgets or presentation logic
  - OpenCode runtime integration
  - application orchestration policy
- Allowed dependencies:
  - may depend on `packages/common_code_application` and `packages/common_code_domain`
  - may use storage libraries needed to implement persistence adapters

### `packages/common_code_observability`

- Category: `support infrastructure`
- Responsibility: owns logging, telemetry, tracing, and other observability infrastructure.
- Belongs here:
  - event and log sinks
  - telemetry adapters
  - instrumentation helpers
  - observability-facing composition helpers
- Does not belong here:
  - domain invariants
  - storage ownership
  - OpenCode host execution logic
  - Flutter presentation logic
- Allowed dependencies:
  - may depend on `packages/common_code_application` and `packages/common_code_domain` only where needed to instrument application or domain activity
  - may use observability and logging libraries

### `packages/host_in_memory`

- Category: `adapter`
- Responsibility: owns the in-memory host adapter/runtime path used for local, development, and test-style execution.
- Belongs here:
  - in-memory host-service implementation
  - adapter logic that satisfies application-defined host ports for local execution paths
  - local runtime behavior that is specific to the in-memory host path
- Does not belong here:
  - domain ownership
  - application use-case ownership
  - Flutter presentation
  - OpenCode-backed execution code
- Allowed dependencies:
  - may depend on `packages/common_code_application` and `packages/common_code_domain`
  - must remain an inward-facing adapter, not a core dependency of Domain or Application

### `packages/host_opencode`

- Category: `adapter`
- Responsibility: owns OpenCode-backed host integration behind the infrastructure adapter seam.
- Belongs here:
  - OpenCode-specific host adapter code
  - runtime integration glue for OpenCode-backed execution
  - OpenCode-facing translation needed to satisfy application-defined ports
- Does not belong here:
  - domain invariants
  - application orchestration ownership
  - persistence ownership
  - desktop presentation code
- Allowed dependencies:
  - may depend on `packages/common_code_application` and `packages/common_code_domain`
  - may use OpenCode-specific runtime and integration libraries
  - must not cause OpenCode-specific concerns to appear in Domain, Application, Persistence, or Flutter presentation code

OpenCode placement is explicit: OpenCode-specific code belongs in `packages/host_opencode` and must not appear in `packages/common_code_domain`, `packages/common_code_application`, `packages/common_code_persistence`, `packages/common_code_observability`, or Flutter presentation code in `apps/common_code_desktop`.

### `apps/common_code_desktop`

- Category: `app-shell`
- Responsibility: owns the desktop app-shell, Flutter presentation, and desktop composition/bootstrap.
- Belongs here:
  - Flutter widgets and presentation-specific view shaping
  - desktop bootstrap and app composition
  - adapter wiring only at the app edge needed to assemble the desktop application
- Does not belong here:
  - reusable domain ownership
  - reusable application-core ownership
  - persistence adapter internals
  - OpenCode or in-memory host implementation internals
- Allowed dependencies:
  - may depend on Flutter plus `packages/common_code_application` and domain-facing models needed for presentation
  - may depend on adapter packages only at the desktop composition/bootstrap edge to wire the app
  - this app-level allowance does not authorize presentation-layer code to reach directly into persistence or host adapter internals

Desktop presentation code depends on application-facing APIs. Adapter wiring belongs only at the app composition/bootstrap edge. The desktop app does not own domain rules, persistence internals, or host adapter internals.

## Current-to-target seam notes

The current `packages/host_core` seam is transitional and is not the final target package boundary.

- The current host contract and use-case coordination concerns conceptually belong with `packages/common_code_application`.
- The current in-memory host implementation conceptually belongs with `packages/host_in_memory`.
- The current desktop controller/runtime seam remains app-owned in `apps/common_code_desktop` unless and until later slices move reusable orchestration into `packages/common_code_application`.

These notes clarify target ownership only. They do not define migration order, extraction choreography, or refactor steps.

## Deferred dependency-matrix work

Issue #41 remains responsible for:

- the full allowed and forbidden dependency matrix
- import-policy wording
- architecture-violation examples
- eventual enforcement mechanics

This document intentionally stops at package-level ownership and high-level allowed dependencies needed to guide placement decisions for the target architecture.

## Non-goals

This artifact does not:

- create packages, apps, directories, or `pubspec.yaml` entries
- move files, rename packages, or change imports
- define concrete adapter APIs, DTO catalogs, storage schemas, or transport contracts
- prescribe migration sequencing or implementation choreography
- reopen ADR 0006 or the existing CommonCode context vocabulary
