# CommonCode current-to-target architecture mapping

## Status and scope

- Status: planning/specification only
- Change scope: docs-only
- Sole implementation artifact for issue #47: `docs/architecture/commoncode-current-to-target-architecture-mapping.md`
- Required completion action outside this diff: an explicit acceptance comment on issue #47 linking this document as the approved mapping artifact
- Accepted-baseline caveat: `docs/adr/0007-opencode-host-adapter-boundary-and-mapping-rules.md` still says `Status: Proposed` locally, but issue #44 is already accepted; this mapping follows the accepted issue/artifact content and does not reinterpret that boundary from the local status label

This document maps current CommonCode seams into the already accepted target architecture homes. It is a consequence of accepted issues #39 through #46. It does not reopen those decisions, authorize code moves, define migration sequencing, or create any package beyond the accepted target package set.

## Alignment with accepted architecture baseline

| Accepted prerequisite | Governing reuse in this mapping |
| --- | --- |
| Issue #39 / `docs/adr/0006-commoncode-layered-architecture-constitution.md` | Keeps the governing `Presentation -> Application Facade -> Domain` direction and keeps persistence and infrastructure concerns behind inward-facing seams. |
| Issue #40 / `docs/architecture/commoncode-target-module-package-map.md` | Limits target homes to `apps/common_code_desktop`, `packages/common_code_domain`, `packages/common_code_application`, `packages/common_code_persistence`, `packages/common_code_observability`, `packages/host_in_memory`, and `packages/host_opencode`. |
| Issue #41 / `docs/architecture/commoncode-dependency-matrix-and-allowed-imports.md` | Keeps Presentation dependent on Application-facing APIs, and keeps adapters dependent inward on Application and Domain. |
| Issue #42 / `docs/architecture/commoncode-application-facade-contract.md` | Keeps the Application Facade as the only stable presentation-facing boundary for bootstrap, refresh, submission, read, and observation behavior. |
| Issue #43 / `docs/architecture/commoncode-application-port-contract-set.md` | Keeps host gateway, session store, session observation, identity context, and observability / diagnostics as Application-owned contract concerns beneath the facade. |
| Issue #44 / `docs/adr/0007-opencode-host-adapter-boundary-and-mapping-rules.md` | Keeps OpenCode-specific runtime translation behind `packages/host_opencode` and forbids leaking OpenCode semantics upward. |
| Issue #45 / `docs/architecture/commoncode-persistence-model-and-adapter-contract.md` | Keeps durable continuity storage, snapshot translation, and legacy-shape normalization in `packages/common_code_persistence` behind the Application-owned session store port. |
| Issue #46 / `docs/architecture/commoncode-observability-model-and-diagnostics-boundary.md` | Keeps observability contract ownership in Application and concrete diagnostics sinks/adapters in `packages/common_code_observability`. |

## Decision taxonomy

| decision_class | Meaning |
| --- | --- |
| `stays` | The responsibility remains in its current long-term architecture home because it is desktop-only presentation or app-edge composition work allowed by the accepted target package map. |
| `moves` | The responsibility has one clear accepted target home and should not remain owned by its current seam in the target architecture. |
| `must_split_before_migration` | The current seam mixes responsibilities that belong to multiple accepted homes; later implementation must separate the responsibilities before any truthful migration can occur. This label identifies target ownership only and does not prescribe sequencing. |

## Canonical current-to-target mapping

| current_seam | current_responsibility | decision_class | target_home | alignment_basis | notes |
| --- | --- | --- | --- | --- | --- |
| `apps/common_code_desktop/lib/src/desktop_session_controller.dart` | `ChangeNotifier`-based desktop view-state shaping for `loading` / `empty` / `data` / `error` / `isSubmitting` | `stays` | `apps/common_code_desktop` | Issues #39, #40, and #42 keep presentation rendering and view shaping in the desktop app-shell | This is desktop-owned presentation behavior, not reusable application-core ownership. |
| `apps/common_code_desktop/lib/src/desktop_session_controller.dart` | Desktop UI command delegation (`initialize`, `refresh`, `submitTurn`) and snapshot-to-view-state adaptation | `stays` | `apps/common_code_desktop` | Issue #42 keeps Presentation invoking Application-facing commands while staying thin | The controller remains a presentation adapter; the underlying orchestration responsibilities are mapped separately below. |
| `apps/common_code_desktop/lib/src/desktop_session_runtime.dart` | Desktop callback binding and app-edge runtime assembly between controller and lower seams | `stays` | `apps/common_code_desktop` | Issue #40 allows adapter wiring only at the desktop composition/bootstrap edge | This responsibility is app-edge composition, not reusable application behavior. |
| `apps/common_code_desktop/lib/src/desktop_session_runtime.dart` | Session bootstrap / restore / fresh-fallback coordination | `must_split_before_migration` | `packages/common_code_application` | Issues #42 and #43 place bootstrap and restore coordination behind the Application Facade using session store, identity, and host gateway contracts | The current runtime mixes orchestration with concrete durable-local and host adapter selection. |
| `apps/common_code_desktop/lib/src/desktop_session_runtime.dart` | Refresh and ongoing session-watch coordination, including restart generation handling | `must_split_before_migration` | `packages/common_code_application` | Issues #42 and #43 make ongoing observation an Application-facing concern backed by the session observation port | Coordination belongs in Application; concrete observation implementation remains adapter-side. |
| `apps/common_code_desktop/lib/src/desktop_session_runtime.dart` | Concrete host-service factory selection and durable-local adapter wiring | `stays` | `apps/common_code_desktop` | Issues #40 and #41 allow adapter wiring at the app-edge bootstrap/composition boundary only | This should stay bounded to desktop composition instead of becoming reusable runtime ownership. |
| `apps/common_code_desktop/lib/src/desktop_session_snapshot_store.dart` | Durable snapshot read/write against local storage | `moves` | `packages/common_code_persistence` | Issue #45 places durable continuity access behind the Application-owned session store port in persistence adapters | The current desktop-local store is a persistence seam, not a long-term desktop ownership concept. |
| `apps/common_code_desktop/lib/src/desktop_session_snapshot_codec.dart` | Storage DTO/schema translation for Session, Turn, and Notification continuity payloads | `moves` | `packages/common_code_persistence` | Issue #45 keeps canonical persistence translation and physical storage representation in persistence adapters | Snapshot codec logic is storage translation, not presentation logic. |
| `apps/common_code_desktop/lib/src/durable_local_host_service.dart` | Durable session payload read/write, restore-from-storage, and legacy-seed normalization/marker handling | `must_split_before_migration` | `packages/common_code_persistence` | Issue #45 assigns durable continuity, normalization of old persisted shapes, and storage-specific translation to persistence adapters | The current file mixes persistence responsibilities with runtime execution and diagnostics emission. |
| `apps/common_code_desktop/lib/src/durable_local_host_service.dart` | In-memory host execution lifecycle, turn simulation, session mutation, and live watch implementation | `must_split_before_migration` | `packages/host_in_memory` | Issues #40 and #43 place local in-memory host behavior and session observation implementation on the host adapter side | This is the durable-local file's host-adapter portion, not persistence or desktop presentation ownership. |
| `apps/common_code_desktop/lib/src/durable_local_host_service.dart` | Diagnostics codes, diagnostics sink, and diagnostics emission around bootstrap / read / write / legacy-seed events | `must_split_before_migration` | `packages/common_code_observability` | Issue #46 places concrete observability support in `packages/common_code_observability` while Application owns the contract | Diagnostics plumbing is cross-cutting observability support, not a desktop-owned or host-core-owned end state. |
| `apps/common_code_desktop/lib/src/durable_local_host_service.dart` | Top-level bootstrap entrypoint that chooses restore vs legacy-seed vs fresh session path | `must_split_before_migration` | `packages/common_code_application` | Issues #42 and #43 keep bootstrap orchestration in Application while persistence and host adapters satisfy lower contracts | The current single adapter seam over-owns coordination that should sit above persistence and host implementations. |
| `packages/host_core/lib/src/host_service.dart` | Aggregated create / attach / read / restore session continuity contract | `must_split_before_migration` | `packages/common_code_application` | Issue #43 separates session store and identity-related contract concerns beneath the facade | `packages/host_core` is transitional only; this combined surface is not a canonical target package or final contract shape. |
| `packages/host_core/lib/src/host_service.dart` | Aggregated `watchSession(...)` observation contract | `must_split_before_migration` | `packages/common_code_application` | Issue #43 establishes session observation as an explicit Application-owned port | Concrete observation implementations belong in `packages/host_in_memory` or `packages/host_opencode`, not in a transitional shared seam. |
| `packages/host_core/lib/src/host_service.dart` | Aggregated `submitTurn(...)` host execution contract | `must_split_before_migration` | `packages/common_code_application` | Issue #43 establishes the host gateway as an Application-owned contract concern | The current host-core seam conflates application contract ownership with adapter implementation shape. |
| `packages/host_core/lib/src/host_service_failure.dart` | Bounded contract-visible failure categories for current host/session operations | `moves` | `packages/common_code_application` | Issues #42 and #43 keep adapter internals hidden while Application owns stable contract and outcome surfaces | Adapter-specific runtime/storage failures stay adapter-side; only bounded contract-facing failures belong with Application-owned ports. |
| `packages/host_core/lib/src/in_memory_host_service.dart` | In-memory host adapter implementation for session mutation, observation, and simulated execution | `moves` | `packages/host_in_memory` | Issue #40 explicitly reserves `packages/host_in_memory` for the in-memory host runtime path, and issue #43 places host/session-observation implementations on host adapters | This is the clearest current source for the future `host_in_memory` adapter path. |

## Desktop-owned seam notes

- `apps/common_code_desktop` remains the home for controller/view-state shaping, Flutter-facing command delegation, and app-edge composition/wiring.
- Desktop ownership does **not** extend to durable persistence translation, reusable bootstrap orchestration, reusable session-watch orchestration, reusable diagnostics infrastructure, or reusable host adapter implementation.
- The current runtime file is only partly desktop-owned: callback binding and adapter wiring stay at the desktop edge, while reusable orchestration responsibilities map to `packages/common_code_application`.
- The current snapshot store and snapshot codec are desktop-local today, but their target ownership is persistence, not presentation.

## Transitional `host_core` seam notes

- `packages/host_core` is transitional current-state context only. It is not a canonical target package and does not appear as a valid `target_home` in this mapping.
- The current `HostService` seam over-combines responsibilities that the accepted architecture separates into Application-owned contracts plus adapter implementations.
- Conceptually, Application owns the stable host/session contract surfaces; `packages/host_in_memory` and `packages/host_opencode` own concrete host-adapter implementations.
- `HostServiceFailure` aligns with Application-owned bounded contract failures only to the extent that Presentation/Application need stable outcome categories; adapter-specific runtime/storage/vendor failures remain adapter-local and should not leak upward as canonical product contracts.
- The `host_core` package itself is retired as a target ownership concept. Its useful responsibilities are re-homed, and the package boundary itself is not preserved in the accepted target architecture.

## Cross-cutting responsibility mapping notes

| responsibility_category | target_home | bounded note |
| --- | --- | --- |
| session bootstrap / restore coordination | `packages/common_code_application` | Coordinated through the Application Facade and Application-owned ports, not owned by desktop runtime or one concrete adapter. |
| session observation / watch behavior | `packages/common_code_application` | Application owns the observation contract; concrete watch implementations live in `packages/host_in_memory` or `packages/host_opencode`. |
| turn submission coordination | `packages/common_code_application` | Presentation invokes it through the facade; host adapters implement the underlying execution path. |
| durable snapshot persistence and translation | `packages/common_code_persistence` | Includes storage access, schema translation, and normalization of older persisted forms. |
| legacy-seed migration / bootstrap logic | `packages/common_code_persistence` | Legacy-shape normalization and durable-local seeding are persistence concerns, even when currently triggered during bootstrap. |
| simulated host execution lifecycle behavior | `packages/host_in_memory` | Current local turn simulation and session mutation belong with the in-memory host adapter path. |
| diagnostics emission / sinks / codes | `packages/common_code_observability` | Application owns the diagnostics contract, while concrete sinks/helpers live in observability infrastructure. |
| desktop app-edge composition and adapter wiring | `apps/common_code_desktop` | Desktop may assemble Application plus adapters at the app edge without becoming their reusable ownership home. |
| OpenCode-specific host runtime translation | `packages/host_opencode` | None of the minimum seams are OpenCode-specific today; if a responsibility is OpenCode-specific later, issue #44 requires it to land here and not in desktop/Application/Domain/persistence/observability code. |

## Non-goals

This mapping does not:

- move files, rewrite imports, create packages, or refactor current seams
- define migration sequencing, extraction order, batching, or implementation choreography
- change the accepted target package set or dependency rules
- normalize `packages/host_core` as a target package
- treat this diff as a substitute for the separately required issue acceptance comment linking the approved mapping artifact
