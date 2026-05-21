# CommonCode layered test strategy

## Status and scope

- Status: planning/specification only
- Change scope: docs-only
- Canonical artifact for issue #52
- Sole implementation artifact authorized by this slice: `docs/architecture/commoncode-layered-test-strategy.md`
- Separate non-diff completion action still required: post the acceptance comment on issue `#52` linking this document

This document defines the canonical layered test strategy for the accepted CommonCode target architecture. It assigns testing responsibilities by target package and architectural boundary so later implementation slices can supply evidence without reopening the architecture baseline, choosing concrete tooling, or reorganizing suites in this issue.

## Alignment with accepted architecture baseline

This strategy is a consequence of accepted decisions and does not replace them.

| Issue | Baseline artifact or accepted reference | Reused architectural meaning |
| --- | --- | --- |
| #39 | `docs/adr/0006-commoncode-layered-architecture-constitution.md` | Governing layered constitution and one-way dependency direction |
| #40 | `docs/architecture/commoncode-target-module-package-map.md` | Canonical target package set and package ownership |
| #41 | `docs/architecture/commoncode-dependency-matrix-and-allowed-imports.md` | Dependency and import rules that tests must reinforce, not blur |
| #42 | `docs/architecture/commoncode-application-facade-contract.md` | Presentation-facing facade boundary |
| #43 | `docs/architecture/commoncode-application-port-contract-set.md` | Application-owned port set and adapter-side contract ownership |
| #44 | `docs/adr/0007-opencode-host-adapter-boundary-and-mapping-rules.md` | OpenCode host adapter boundary and mapping constraints |
| #45 | `docs/architecture/commoncode-persistence-model-and-adapter-contract.md` | Persistence-side continuity semantics and adapter responsibilities |
| #46 | `docs/architecture/commoncode-observability-model-and-diagnostics-boundary.md` | Observability boundary and diagnostics ownership |
| #47 | accepted issue baseline at `docs/architecture/commoncode-current-to-target-architecture-mapping.md` | Current-to-target mapping remains authoritative even if the file is absent in this workspace snapshot |
| #48 | accepted issue baseline at `docs/architecture/commoncode-staged-migration-plan.md` | Staged migration constraints remain authoritative even if the file is absent in this workspace snapshot |

## Inherited decisions from accepted prerequisites

The following are inherited baseline constraints and are not newly decided by issue `#52`:

- `Presentation -> Application -> Domain` remains the governing inward direction, while persistence and infrastructure adapters depend inward behind seams.
- `packages/common_code_application` remains the only stable presentation-facing contract owner.
- `packages/common_code_application` also remains the owner of the stable ports that adapters satisfy.
- `packages/common_code_domain` remains pure and must not rely on runtime, persistence, host, observability, or presentation concerns.
- `packages/common_code_persistence`, `packages/common_code_observability`, `packages/host_in_memory`, and `packages/host_opencode` remain adapter/infrastructure-side packages.
- `apps/common_code_desktop` remains the presentation host and app-shell, with adapter imports allowed only at the composition/bootstrap edge rather than in feature-facing presentation code.
- Current mixed seams are transitional context only and do not become canonical long-term test ownership.

## New decisions introduced by issue #52

Issue `#52` adds only these bounded decisions:

1. CommonCode test strategy is defined by layer/package responsibility rather than by current seam location.
2. Each target package has a distinct testing role that should be visible in later implementation evidence.
3. Contract tests are required for adapter implementations of the Application-owned ports, but contract ownership stays in `packages/common_code_application`.
4. Functional tests complement architecture review and dependency enforcement; they do not replace them.
5. Migration-era evidence may be gathered through transitional seams, but that evidence must still be explained in terms of target ownership.

## Layered test responsibility model

The table below is the canonical responsibility model for later implementation slices.

| Layer or boundary | Target package or package category | Test responsibilities | Test types in scope | Architectural failures tests should catch | Architectural failures deferred to review or enforcement | Dependency-direction reinforcement | Migration alignment notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Domain | `packages/common_code_domain` | Prove pure product semantics, invariants, transformations, and failure behavior for Sessions, Clients, Prompt Threads, Turns, Notifications, Hosts, and Active Host relationships. | Pure unit and domain-spec tests only. | Broken invariants, invalid state transitions, incorrect value transformations, incorrect domain failure behavior. | Domain importing frameworks, storage/runtime/vendor concerns, or depending on Application/adapters/presentation. | Runs at the pure domain boundary with no adapter or app-shell participation, reinforcing that Domain is inward and framework-independent. | Transitional current seams do not own these tests long term; any temporary evidence gathered elsewhere should be traced back to eventual `common_code_domain` ownership. |
| Application | `packages/common_code_application` | Prove use-case orchestration, facade-facing behavior, policy coordination, port usage, and outcome mapping over Domain plus Application-owned contracts. | Application-layer unit/service tests and facade-behavior tests against ports/test doubles. | Incorrect orchestration, incorrect facade outcomes, incorrect policy around port coordination, incorrect mapping of domain and adapter-facing failures into facade-facing results. | Application importing concrete adapters, depending on app-shell code, or reaching through package internals. | Exercises behavior through Domain plus Application-owned ports, reinforcing that Application depends inward on Domain and outward only through its own contracts. | If current seams still host some orchestration, later slices must explain how evidence maps to target Application ownership instead of canonizing transitional seams. |
| Adapter / persistence | `packages/common_code_persistence` | Prove the `session store` adapter translates, normalizes, restores, and persists canonical continuity semantics behind the Application-owned contract. | Adapter tests, contract tests for `session store`, and adapter-local translation/normalization tests. | Session-store contract non-conformance, incorrect persistence translation, incorrect normalization of older persisted representations, incorrect bounded persistence failure behavior. | Reverse dependencies into other adapters, presentation-owned persistence behavior, or Application depending directly on persistence implementation. | Validates conformance from the adapter side inward toward the Application-owned `session store` contract rather than making persistence a peer of Presentation or Application. | During migration, persistence evidence may be gathered from legacy durable-local seams, but acceptance should explain how that evidence proves the target persistence adapter responsibility rather than preserving desktop-local ownership. |
| Adapter / observability | `packages/common_code_observability` | Prove observability adapters honor the Application-owned observability/diagnostics contract and translate bounded diagnostics intent into concrete observability behavior. | Contract tests for observability/diagnostics plus adapter-local translation tests. | Observability contract non-conformance, dropped or misclassified diagnostics intent, incorrect translation of bounded application diagnostics into adapter behavior. | Presentation depending on raw observability adapters, Application owning vendor/logging details, or observability becoming the owner of product semantics. | Keeps diagnostics validation on the adapter side of the Application-owned port so Application remains contract owner and Presentation remains facade-bound. | Transitional desktop diagnostics seams may provide temporary evidence, but they must be justified as migration-era support rather than target ownership. |
| Adapter / host runtime | `packages/host_in_memory` | Prove the in-memory host adapter satisfies the host gateway and session observation contracts and preserves CommonCode semantics without exporting runtime-specific vocabulary upward. | Contract tests for `host gateway` and `session observation`, plus adapter-behavior tests for in-memory runtime translation. | Host contract non-conformance, incorrect session observation behavior, incorrect host-side translation, semantic drift between Application-owned contracts and in-memory runtime behavior. | Application importing in-memory adapter internals, presentation bypassing the facade, or adapter-to-adapter shortcuts. | Validates host behavior from the adapter side inward toward Application-owned contracts, preserving the accepted boundary. | Migration evidence may temporarily come from current local runtime seams, but it should be explained as proving the target host adapter responsibility for `host_in_memory`. |
| Adapter / host runtime | `packages/host_opencode` | Prove the OpenCode-backed host adapter satisfies the host gateway and session observation contracts while keeping OpenCode terms and runtime types below the adapter seam. | Contract tests for `host gateway` and `session observation`, plus adapter-behavior tests for OpenCode translation/mapping rules. | Contract non-conformance, leaked OpenCode semantics, incorrect adapter mappings, incorrect observation behavior across the OpenCode seam. | Application or Presentation depending on OpenCode-specific types, thin-alias treatment of CommonCode semantics, or adapter internals imported across packages. | Tests validate conformance inward to Application-owned contracts rather than treating OpenCode types as canonical contracts. | Migration-era evidence should align to accepted mapping and staging constraints without redefining OpenCode adapter ownership or prescribing rollout order. |
| Presentation / app shell | `apps/common_code_desktop` | Prove presentation behavior, view/state shaping, user-visible rendering, and app-edge composition behavior stay aligned to the Application Facade while respecting the narrow bootstrap edge for adapter wiring. Identity-context adapter evidence that still lives at the outer app edge should also be explained here until a later accepted package decision changes that ownership. | Presentation tests, facade-aligned integration tests, and app-edge composition tests bounded to the desktop shell. | Presentation behavior that violates facade expectations, incorrect rendering of application outcomes, incorrect app-edge composition behavior, or facade bypasses visible through feature behavior. | Presentation imports of persistence/host/observability internals, bootstrap allowances leaking into feature code, or direct adapter reach-through that only architecture review/enforcement can police reliably. | Verifies presentation through the Application Facade and keeps any adapter wiring evidence at the app edge only, reinforcing that feature behavior must not reach around the facade. | Current desktop seams may host temporary evidence during migration, but they do not become the canonical long-term home for persistence, host, or observability testing responsibility. |

## Contract-test role for Application-owned ports

Contract tests are required where adapters satisfy Application-owned ports from issue `#43`. They validate behavioral conformance across adapter implementations without moving contract ownership out of `packages/common_code_application` and without authorizing Application to depend on concrete adapters as its canonical dependency shape.

| Application-owned port | Contract-test target adapters | Contract-test purpose | Explicit boundary reminder |
| --- | --- | --- | --- |
| Host gateway | `packages/host_in_memory`, `packages/host_opencode` | Prove each host adapter satisfies the same Application-owned execution-facing behavior contract. | Contract ownership remains in Application; Application tests stay adapter-agnostic. |
| Session store | `packages/common_code_persistence` | Prove persistence adapters preserve canonical continuity semantics and bounded failure behavior through the Application-owned store contract. | Persistence translation stays behind the adapter seam. |
| Session observation | `packages/host_in_memory`, `packages/host_opencode` | Prove runtime-facing host adapters deliver session observation behavior expected by Application without leaking runtime-specific semantics upward. | Observation is a first-class Application contract, not a presentation subscription contract. |
| Identity context | Outer adapter/app-shell implementation currently expected at the desktop edge | Prove session-bound identity/client-context resolution satisfies the Application-owned contract where that adapter responsibility currently exists. | This does not authorize a new canonical package; it remains bounded by the accepted package map. |
| Observability / diagnostics | `packages/common_code_observability` | Prove observability adapters honor bounded Application diagnostics intent without turning vendor/logging details into Application contracts. | Diagnostics contract ownership remains in Application. |

Contract tests are distinct from:

- Domain tests, which prove pure product semantics.
- Application tests, which prove orchestration against ports rather than concrete adapters.
- Presentation tests, which prove facade-aligned user-facing behavior.
- Broad end-to-end coverage, which may be useful later but is not the canonical boundary owner for these contracts.

## What tests should catch vs what review/enforcement should catch

### Failures tests should catch

- Broken domain invariants and product semantics.
- Incorrect Application orchestration against Domain and Application-owned ports.
- Adapter non-conformance to the `host gateway`, `session store`, `session observation`, `identity context`, and `observability / diagnostics` contracts.
- Presentation behavior that violates facade-level expectations.
- Observable regressions that occur within an allowed architectural boundary.

### Failures primarily caught by review or enforcement under issue #41

- Forbidden dependency edges and import-direction violations.
- Cross-package `lib/src/**` reach-through.
- Presentation code importing persistence, host, or observability internals directly.
- Application code depending on concrete adapters.
- Domain code importing framework, runtime, storage, OpenCode, or observability implementation concerns.
- Adapter-to-adapter shortcuts that violate the accepted dependency matrix.

Tests complement architecture review and dependency enforcement; they do not replace them.

## Migration-alignment notes

- Test expectations remain aligned to accepted target ownership even while current seams are transitional.
- Mixed current seams from the accepted current-to-target mapping do not become canonical long-term test ownership merely because they exist today.
- Staged migration constraints may temporarily affect where evidence is gathered, but they do not redefine which layer or package ultimately owns a class of testing responsibility.
- Later implementation slices should explain transitional evidence in terms of the target package and boundary this strategy assigns, not in terms of current file location alone.
- This document intentionally does not prescribe migration order, extraction choreography, or batching.

## Evidence expectations for later implementation slices

Later implementation and review slices should show, for each meaningful test change:

1. which layer/package responsibility the test evidence belongs to;
2. which Application-owned contract boundary is being validated, if the test is a contract test;
3. how the evidence avoids rewarding forbidden dependency direction or reach-through;
4. which concerns remain intentionally enforced by review/dependency policy rather than asserted through functional tests;
5. how any migration-era temporary seam still produces evidence for the target ownership model in this strategy.

## Non-goals

This artifact does not:

- write tests, fixtures, helpers, harnesses, or suite reorganization rules;
- choose frameworks, commands, CI jobs, or automation tooling;
- define exact test file placement, naming schemes, or directory layout;
- redefine the accepted architecture, package map, dependency matrix, facade contract, port contract set, persistence contract, observability boundary, current-to-target mapping, or migration order;
- create companion artifacts, matrices, sidecar files, or implementation plans.
