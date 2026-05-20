# CommonCode persistence model and adapter contract

## Status and scope

- Status: planning/specification only
- Change scope: docs-only
- Canonical artifact for issue #45
- This artifact defines the product-level persistence model and adapter contract for CommonCode.

This document does not authorize persistence-adapter implementation, storage-engine selection, schema rollout, migration execution, package creation, code movement, or production/test code changes.

## Pinned prerequisite baseline

This artifact is anchored to the accepted prerequisite baseline for issues #39-#43 plus issue #30 and ADR 0005. Those artifacts provide inherited architecture decisions reused here; this issue defines only the persistence-model and adapter-contract decisions that were still open.

| Source | Pinned artifact or reference | Inherited decision reused here |
| --- | --- | --- |
| Issue #39 | `6685aafb4e921a27fdfd8fc0ff361ecc9035d4d8:docs/adr/0006-commoncode-layered-architecture-constitution.md` | CommonCode keeps the governing `Presentation -> Application Facade -> Domain` direction while persistence and infrastructure adapters depend inward behind seams. |
| Issue #40 | `ee4499cef5e8f6800a59cab968816f27e543e628:docs/architecture/commoncode-target-module-package-map.md` | `packages/common_code_application` owns stable application-facing orchestration and ports, while `packages/common_code_persistence` owns persistence adapters. |
| Issue #41 | `4c0bff7b2346364db0cac91b8180c528e649e4cf:docs/architecture/commoncode-dependency-matrix-and-allowed-imports.md` | Application owns stable ports, adapters depend inward, and adapter-to-adapter coupling is forbidden by default. |
| Issue #42 | `258110f7ecc91e5f6b1e7f90f2e0dd70e2d2c48e:docs/architecture/commoncode-application-facade-contract.md` | Presentation depends on the Application Facade rather than on persistence implementations or persistence DTOs. |
| Issue #43 | `28ec99e42fdb67ad9d0bb6d7cd0a0ee516897583:docs/architecture/commoncode-application-port-contract-set.md` | The `session store` is an Application-owned port implemented by persistence adapters, while live session observation remains a host/runtime-side contract concern. |
| Issue #30 | closed issue baseline for durable local restart continuity | Durable restart continuity preserves Session state, Turn state, and Notification acknowledgement/replay state without automatic resumption of in-flight host execution. |
| ADR 0005 | `2bf14448e7555c79612a380fb82805e0d13503fa:docs/adr/0005-external-host-path-after-durable-local-baseline.md` | The next external-host direction stays close to the durable-local baseline by keeping the model same-machine and adapter-neutral rather than desktop-process-specific. |

## Inherited decisions from accepted architecture

The following decisions are inherited and are not reopened by issue #45.

| Decision | Status | Source |
| --- | --- | --- |
| Presentation stays thin and depends on the Application Facade for feature behavior. | Inherited from accepted prerequisites | Issues #39, #41, #42 |
| Domain remains pure and does not own storage, transport, runtime, or presentation concerns. | Inherited from accepted prerequisites | Issues #39, #41 |
| `packages/common_code_application` owns stable ports and orchestration around the Domain. | Inherited from accepted prerequisites | Issues #40, #43 |
| `packages/common_code_persistence` is the adapter-side home for persistence implementations that depend inward on Application and Domain. | Inherited from accepted prerequisites | Issues #40, #41 |
| Persistence and host/runtime concerns must remain distinct rather than collapsing back into one seam. | Inherited from accepted prerequisites | Issues #39, #41, #43 |
| Durable-local restart continuity for Session, Turn, and Notification acknowledgement/replay state remains the current authoritative product baseline. | Inherited from accepted prerequisites | Issue #30 |
| The architecture should remain compatible with a same-machine out-of-process host direction without reopening Session/Active Host semantics. | Inherited from accepted prerequisites | ADR 0005 |

## New decisions introduced by issue #45

Issue #45 adds the bounded persistence-model decisions below.

| Decision | Status | Source |
| --- | --- | --- |
| CommonCode persistence is a product-semantic continuity model behind an adapter seam, not presentation state and not a storage-engine-owned model. | New in issue #45 | This artifact |
| Durable product state and excluded ephemeral client/presentation state are explicitly classified at the architecture level. | New in issue #45 | This artifact |
| The logical canonical persisted shape is owned by CommonCode product semantics, with Domain supplying meaning and Application owning the stable persistence-facing contract boundary. | New in issue #45 | This artifact |
| Persistence adapters translate between the canonical logical model and adapter-specific physical storage representations without owning product meaning. | New in issue #45 | This artifact |
| Normalization and migration of older persisted representations into the current canonical model are adapter responsibilities in `packages/common_code_persistence`. | New in issue #45 | This artifact |
| Live session observation remains a host/runtime-side concern and is not absorbed into the persistence adapter contract. | New in issue #45 | This artifact |

## Why persistence is a product-semantic model behind an adapter seam

CommonCode persistence exists to preserve durable continuity for product concepts such as Session identity/binding, Prompt Thread and Turn continuity, Notification acknowledgement/replay continuity, and Active Host continuity information needed to restore the same Session experience after restart.

Because that continuity is a product concern, the canonical persistence model is not owned by:

- a desktop-only app shell
- `SharedPreferences` or any other storage engine
- current local JSON payloads or snapshot codecs
- one concrete adapter implementation
- OS-specific, hardware-specific, or in-process assumptions

Persistence therefore sits behind the Application-owned `session store` port and is implemented by adapter-side components in `packages/common_code_persistence`. Presentation continues to depend on the Application Facade, not on persistence adapters or persistence DTOs.

## Durable product state versus ephemeral client state

The persistence model must preserve product continuity state and must exclude client/presentation state that is only useful for local rendering convenience.

| State category | Classification | Why |
| --- | --- | --- |
| Session continuity identity/binding needed to restore the same Session | Durable product state | Restoring the same Session is a product continuity requirement, not a UI convenience. |
| Prompt Thread continuity and authored Turn history | Durable product state | The ordered work history is part of the product's continuity model. |
| Active Turn lifecycle state, including active/completed/failed status and last-known queued/running state | Durable product state | Issue #30 makes Turn continuity a restart requirement even when execution does not automatically resume. |
| Notification acknowledgement and replay continuity | Durable product state | Acknowledged versus unacknowledged Notification behavior is a product semantic defined for restart continuity. |
| Active Host / Session continuity information needed to reconnect to the same Session-bound host relationship | Durable product state | Restart continuity must preserve the same authoritative Session/Active Host relationship without reopening host-boundary decisions. |
| Session-bound identity or attached-client context only when needed to restore product continuity semantics | Durable product state when justified | Identity/client context belongs here only when it is required to restore the same Session continuity, not merely for UI convenience. |
| Loading, submitting, refreshing, or controller/view-model flags | Ephemeral client/presentation state | These are render-time operation states owned by Presentation and facade-facing UI behavior. |
| Widget-tree composition, route state, tab choice, focus, selection, and scroll position | Ephemeral client/presentation state | These are platform-local rendering concerns rather than CommonCode product continuity. |
| Snackbar, toast, transient banner, or similar rendering state | Ephemeral client/presentation state | Notification semantics are durable when required, but their local rendering surfaces are not. |
| Platform-local caches, bootstrap conveniences, or memoized view data that do not define Session continuity | Not canonical durable product persistence | They may exist locally, but they do not own the product persistence model. |

Future client-local durable preferences may exist as a separate concern, but they are not part of the canonical product persistence model defined in this slice.

## Canonical persisted shape ownership

The canonical persisted shape/schema is owned at the product-semantic level, not at the storage-engine level.

### Ownership split

| Concern | Architectural owner | Meaning |
| --- | --- | --- |
| Product meaning and invariants | Domain | Domain defines what Session, Prompt Thread, Turn, Notification, Host, and Active Host concepts mean and what invariants those concepts must satisfy. |
| Stable persistence-facing contract and logical persistence model/snapshot boundary | Application | Application owns the `session store` contract boundary and the logical persisted shape it depends on for durable continuity orchestration. |
| Physical storage representation | Persistence adapter | Adapters may use storage-specific DTOs, envelopes, serialization formats, keys, tables, or files, but those remain projections of the canonical logical model rather than owners of it. |

### Canonical logical model versus physical storage representation

- The **logical canonical persisted model** is the adapter-neutral product continuity model that crosses the Application-facing persistence boundary.
- The **adapter-specific physical storage representation** is whatever a persistence adapter needs internally to store, read, version, or migrate that logical model in one concrete engine or medium.
- Storage-specific DTOs, local JSON payloads, and engine-native schemas may exist, but they must map to the canonical logical model rather than redefine it.

This keeps persistence product-semantic and prevents current desktop payloads, `SharedPreferences` keys, or app-owned snapshot formats from becoming the long-term architecture owner of persisted shape.

## Persistence adapter contract and responsibilities

Issue #43 already established the `session store` as an Application-owned port. Issue #45 refines the persistence semantics and adapter boundary that sit behind that port without reopening issue #43.

### Contract placement

- Stable persistence-facing contract owner: Application layer in `packages/common_code_application`
- Expected implementing adapter package: `packages/common_code_persistence`
- Dependency direction: persistence adapters may depend on Application and Domain as allowed by issue #41; Application and Domain do not depend back on concrete persistence adapters

### Persistence adapters are responsible for

- loading or restoring canonical durable continuity state for Application orchestration
- saving or replacing canonical durable continuity state when orchestration requires persistence
- translating between the canonical logical persisted model and adapter-specific physical storage representations
- normalizing older persisted representations into the current canonical model before data crosses into the Application layer
- surfacing bounded persistence failures when restore, save, or migration cannot be completed correctly

### Persistence adapters intentionally do not own

- presentation shaping or client UI state
- host execution behavior or host-runtime policy
- live session observation, watch semantics, or runtime subscriptions
- authentication or authorization policy
- vendor-specific host logic
- domain invariant ownership
- application orchestration policy beyond satisfying the Application-owned persistence contract

Live session observation remains a host/runtime-side concern from issue #43. Persistence in this slice preserves durable continuity; it does not become a session-observation channel.

## Migration and versioning expectations

Canonical persisted state must carry or be governed by an explicit model/schema version expectation.

- The version concept belongs to the product persistence model, not merely to one local storage key or one desktop payload shape.
- The Application-facing persistence boundary expects the current canonical logical model/version.
- Persistence adapters may maintain storage-specific physical versions internally, but they must normalize persisted data to the current canonical model before it crosses the Application boundary.
- Migration and upgrade behavior belong in `packages/common_code_persistence`, not in Presentation and not as raw Domain invariant ownership.
- Migration or normalization failure must surface as a bounded persistence/application failure rather than silent schema drift, silent data reinterpretation, or best-effort UI fallback.

This artifact intentionally does not prescribe exact version numbers, migration algorithms, storage layouts, rollout steps, or implementation sequencing.

## Durable-local baseline and restart continuity alignment

Issue #30 remains the authoritative durable-local restart baseline.

This persistence model preserves that baseline by keeping all of the following central to canonical durable continuity:

- Session continuity state needed to restore the same Session
- Turn continuity state, including last-known queued or running state without automatic host resumption
- Notification acknowledgement/replay continuity
- Session/Active Host continuity information needed to remain aligned with one-active-host semantics

Persistence supports restart continuity, but it does not itself become Presentation state. The model remains conceptually adapter-neutral so that the first durable-local adapter path can evolve toward ADR 0005's same-machine out-of-process direction without redefining persistence as a desktop-only, in-process, OS-bound, or hardware-bound concern.

This issue does not redefine host-boundary, protocol, attachment, transport, or recovery decisions.

## Current-seam notes

Current seams are useful implementation context, but they do not define the target persistence model.

- `apps/common_code_desktop/lib/src/desktop_session_snapshot_store.dart` is a current local adapter seam, not the canonical owner of persisted shape.
- `apps/common_code_desktop/lib/src/durable_local_host_service.dart` is a current durable-local implementation context, not the canonical persistence contract owner.
- Current desktop snapshot codecs, payloads, and `SharedPreferences` keys are local implementation details rather than the long-term product persistence model.
- `packages/host_core/lib/src/host_service.dart` currently mixes create/attach/watch/restore/submit concerns across persistence-adjacent and host/runtime behavior, so it is evidence of a transitional seam rather than the target persistence contract.

These notes are descriptive only. They do not prescribe migration choreography or normalize the current desktop-local shape as the future contract.

## Non-goals

This artifact does not:

- implement a persistence adapter, repository, store, codec, DTO, schema, or migration
- choose `SharedPreferences`, files, SQLite, Isar, Drift, JSON structure details, or any other concrete storage technology
- define exact Dart APIs, method signatures, class names, DTO fields, key names, tables, or file layouts
- move app/package code, rewrite `host_core`, or prescribe extraction/refactor sequencing
- reopen the accepted decisions from issues #39-#43, issue #30, or ADR 0005
- expand scope into IPC/RPC, remote sync, multi-device replication, or distributed persistence guarantees

Issue #45 is planning/specification only. Later implementation slices may build adapters and concrete schemas behind this contract, but completion of this issue does not require implementation work.
