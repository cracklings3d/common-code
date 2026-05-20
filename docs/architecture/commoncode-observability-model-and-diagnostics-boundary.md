# CommonCode observability model and diagnostics boundary

## Status and scope

- Status: planning/specification only
- Change scope: docs-only
- Canonical artifact for issue #46
- Deliverable scope: define the CommonCode observability model and diagnostics boundary as a consequence of already accepted architecture decisions

This artifact defines architecture and contract boundaries only. It does not authorize runtime wiring, logging implementation, metrics implementation, telemetry implementation, trace implementation, adapter extraction, package creation, refactors, or production code changes.

## Alignment with accepted architecture decisions

This artifact realizes accepted decisions from issue #39 through issue #43 rather than replacing them.

- ADR 0006 from issue #39 keeps `Presentation -> Application Facade -> Domain` as the governing inward direction, keeps Domain pure, and places observability in the infrastructure side of the architecture.
- The target package map from issue #40 places observability support in `packages/common_code_observability`, keeps `packages/common_code_application` as the application-contract owner, and keeps `apps/common_code_desktop` as an app-shell/presentation host rather than the reusable home of cross-cutting runtime concerns.
- The dependency matrix from issue #41 requires Application to depend on stable ports rather than concrete adapters and forbids Presentation feature behavior from depending directly on observability adapter implementations.
- The application facade contract from issue #42 keeps Presentation dependent on application-facing commands, reads, and observation surfaces while hiding infrastructure and observability implementation details.
- The application port contract set from issue #43 defines an Application-owned observability / diagnostics port in `packages/common_code_application`, implemented by observability adapters in `packages/common_code_observability`.

## Inherited decisions from accepted prerequisites

The following decisions are inherited and are not newly decided by issue #46.

| Inherited decision | Source |
| --- | --- |
| Domain remains pure and free of logging frameworks, telemetry SDKs, transport details, and vendor/runtime concerns. | ADR 0006 (#39) |
| Presentation depends on the Application Facade rather than concrete persistence, host, or observability implementations for feature behavior. | ADR 0006 (#39), issue #41, issue #42 |
| `packages/common_code_application` owns stable application-facing orchestration and port contracts. | issue #40, issue #43 |
| `packages/common_code_observability` is the target home for concrete observability support. | issue #40 |
| Application records diagnostics through an Application-owned observability / diagnostics port rather than by importing concrete observability implementations. | issue #41, issue #43 |
| Session `Notification` semantics remain product-domain behavior and are not redefined as observability plumbing. | ADR 0004 |

## New decisions introduced by issue #46

Issue #46 adds only the bounded decisions needed to define CommonCode observability at the architecture level.

| New decision | Decision status |
| --- | --- |
| CommonCode observability is described by explicit categories for operational diagnostics/events, structured logs/diagnostic records, metrics, tracing, and user-facing failure/result surfaces that are adjacent to but not identical with observability. | New in issue #46 |
| Layer ownership of observability-relevant signals is explicit across Domain, Application, adapters, observability infrastructure, and Presentation. | New in issue #46 |
| The Application-to-observability boundary is explicitly defined around the Application-owned observability / diagnostics port from issue #43. | New in issue #46 |
| Current desktop-owned diagnostics seams are accepted as current-state evidence only and are explicitly transitional rather than the long-term architecture home. | New in issue #46 |

## Observability model

CommonCode observability is the set of operational signals used to understand how application orchestration and adapter-backed runtime behavior are proceeding without redefining product-domain meaning or user-facing presentation contracts.

The canonical observability-relevant categories are:

| Category | Boundary intent |
| --- | --- |
| Application/domain-significant operational events or diagnostics | Record bounded operational facts about orchestration activity, state transitions, recoverable failures, or important execution conditions that matter for understanding system behavior. These are not user-facing product read models. |
| Structured logs or diagnostic records | Capture machine-readable diagnostic detail for debugging and operational investigation. These records remain implementation-facing and are not the Presentation contract. |
| Metrics, counters, or aggregates | Measure operational behavior in aggregate form for health, throughput, frequency, or trend analysis. Metric naming and backend choices are outside this slice. |
| Tracing or causal runtime-correlation hooks | Preserve causal linkage across orchestration and adapter/runtime work so later implementations can correlate activity without coupling core layers to trace vendors or frameworks. |
| User-facing failure or result surfaces | Communicate loading, empty, data, recoverable failure, and similar product-facing outcomes through the Application Facade for Presentation to render. These surfaces may be informed by failures, but they are not themselves the observability system. |

Observability remains distinct from CommonCode product-state contracts:

- Session `Notification` semantics remain product behavior governed by ADR 0004, not logging, telemetry, or diagnostics plumbing.
- Facade read surfaces and session-observation surfaces from issues #42 and #43 remain application-facing product contracts, not replacements for logs, metrics, traces, or diagnostics.
- Snackbars, badges, toasts, and other user-visible affordances may render application-facing results, but they are not the canonical observability architecture contract.

## Layer ownership of signals

| Layer | What it may own or emit | What it does not own |
| --- | --- | --- |
| Domain | Product meaning, invariants, meaningful state changes, and failures that observability may later describe. | Logging frameworks, telemetry SDKs, trace implementations, desktop-specific diagnostics classes, vendor/runtime instrumentation details. |
| Application Facade / Application layer | The decision to record orchestration-level diagnostics; bounded operational events, warnings, failures, and tracing intent through the Application-owned observability / diagnostics port; mapping underlying failures into application-facing outcome categories for Presentation. | Concrete log sinks, metrics backends, trace exporters, vendor SDKs, desktop-owned diagnostics classes, raw adapter diagnostics as the UI contract. |
| Persistence / Data and host adapters | Adapter-local runtime, storage, transport, or host diagnostics relevant to their responsibilities, emitted behind accepted adapter seams and inward-facing contracts. | Application-contract ownership, presentation-facing outcome ownership, canonical cross-cutting observability policy for product behavior. |
| Observability adapters | Translation of Application diagnostic intent into concrete diagnostic records, logs, metrics, traces, or telemetry integrations inside `packages/common_code_observability`. | Domain invariants, presentation UX behavior, product read models, application-facing outcome contracts. |
| Presentation | Rendering of user-facing states, errors, notices, and platform UX behavior; optional local presentation-runtime diagnostics for app-shell concerns. | Cross-cutting product observability policy, reusable application diagnostics ownership, snackbars/toasts as the canonical diagnostics contract. |

## Application-to-observability boundary

The Application layer accesses observability through the Application-owned observability / diagnostics port defined by issue #43.

- Application records bounded operational diagnostics through that port rather than through desktop-owned classes or vendor telemetry SDKs.
- Application may express that an orchestration event, warning, failure, metric-worthy occurrence, or tracing hook should be recorded, but concrete log formatting, exporters, backends, and framework integration remain adapter concerns.
- Presentation depends on application-facing outcome and read surfaces from issue #42, not on raw observability adapters or raw adapter-specific diagnostic payloads.
- Application must not depend directly on `DurableLocalHostDiagnostic*` classes, desktop runtime diagnostics plumbing, or vendor-specific logging/telemetry packages as its architectural contract.

## Package placement and adapter expectations

- Observability contract ownership remains in `packages/common_code_application`.
- Concrete observability adapters belong in `packages/common_code_observability`.
- `packages/common_code_persistence`, `packages/host_in_memory`, and `packages/host_opencode` may generate adapter-local diagnostic details relevant to storage or host/runtime behavior, but they do not become the canonical observability home for the application contract.
- `apps/common_code_desktop` may temporarily host app-edge composition or local diagnostics wiring in the current slice, but that app-shell location is not the target reusable ownership model for CommonCode observability.
- This preserves the accepted dependency direction: Application defines the observability boundary, observability adapters implement it inward, and Presentation feature behavior remains dependent on the facade rather than on adapter implementations.

## Current-seam notes

Current desktop seams motivate this boundary but do not define the target architecture.

- `DurableLocalHostDiagnosticCode`, `DurableLocalHostDiagnostic`, and `DurableLocalHostDiagnosticsSink` in `apps/common_code_desktop/lib/src/durable_local_host_service.dart` are current-state diagnostics seams.
- Diagnostics sink threading through `apps/common_code_desktop/lib/src/desktop_session_runtime.dart` is current-state runtime context only.
- Snackbar behavior associated with observed turn transitions is Presentation UX behavior and must not be mistaken for the canonical observability contract.
- The current desktop-specific placement is transitional and must not be treated as the long-term architecture home for diagnostics behavior.

## Non-goals

This artifact does not:

- define exact Dart APIs, classes, enums, DTOs, schema fields, log formats, metric names, or trace-span names
- choose logging libraries, telemetry vendors, metric backends, or trace propagation mechanisms
- prescribe instrumentation calls, runtime choreography, or migration sequencing
- move current desktop diagnostics code, extract adapters, or create packages
- redefine Session Notifications, facade read surfaces, or session observation contracts as observability artifacts

Issue #46 is planning/specification only. Implementation, runtime wiring, telemetry/logging/metrics/tracing behavior, and production code changes remain later slices.
