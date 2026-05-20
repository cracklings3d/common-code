# CommonCode dependency matrix and allowed imports

## Status and scope

- Status: planning/specification only
- Change scope: docs-only
- Canonical artifact for issue #41
- This document defines dependency-direction and import-surface rules for the target architecture only

This artifact realizes the accepted layered constitution in `docs/adr/0006-commoncode-layered-architecture-constitution.md` and the accepted target package map in `docs/architecture/commoncode-target-module-package-map.md`. It does not replace either document, and it does not authorize code changes, package extraction, import rewrites, CI enforcement, or migration work.

## Alignment with accepted architecture decisions

This matrix is the rule set that turns the accepted architecture decisions into explicit dependency and import policy.

- ADR 0006 remains the governing layered constitution.
- `docs/architecture/commoncode-target-module-package-map.md` remains the governing target package map.
- `packages/common_code_domain` remains the innermost pure product model.
- `packages/common_code_application` remains the only inward-facing coordination layer for Presentation and adapters.
- `packages/common_code_persistence`, `packages/common_code_observability`, `packages/host_in_memory`, and `packages/host_opencode` are adapter/infrastructure-side dependencies, not core dependencies of Domain or Application.
- `apps/common_code_desktop` retains a narrow app-shell composition edge that is broader than its presentation code allowance.
- The current `packages/host_core` seam is transitional current-state context only and is not a canonical target package in this matrix.

## Canonical target package set

This rule set applies to these target modules/packages and no broader target set:

- `packages/common_code_domain`
- `packages/common_code_application`
- `packages/common_code_persistence`
- `packages/common_code_observability`
- `packages/host_in_memory`
- `packages/host_opencode`
- `apps/common_code_desktop`

## Layer dependency matrix

| Layer | Allowed dependencies | Forbidden highlights |
| --- | --- | --- |
| Presentation | `Application Facade`; Domain-facing models needed to render | Must not depend directly on `Persistence / Data`; must not depend directly on `Infrastructure / Observability` adapter implementations for feature behavior |
| Application Facade | `Domain`; stable abstractions and ports it defines for coordination | Must not depend on `Persistence / Data`, `Infrastructure / Observability`, or `Presentation` implementations |
| Domain | None | Must not depend on `Presentation`, `Application Facade`, `Persistence / Data`, `Infrastructure / Observability`, Flutter, storage, transport, OpenCode, host runtime, or observability frameworks |
| Persistence / Data | `Application Facade`; `Domain` | Must not create a reverse path back into `Presentation`; must not cause Domain policy to depend on storage concerns |
| Infrastructure / Observability | `Application Facade`; `Domain` | Must not create a reverse path back into `Presentation`; must not cause Domain policy to depend on runtime, vendor, transport, or observability implementation concerns |

Governing direction remains one-way: `Presentation -> Application Facade -> Domain`, while persistence and infrastructure/observability adapters depend inward on Application Facade and Domain. No layer may create a reverse path that causes Domain policy to depend on app-shell, Flutter, storage, transport, vendor runtime, or observability implementation concerns.

## Package/module dependency matrix

| Target module/package | Allowed internal dependencies | Forbidden internal dependencies | Narrow allowance or interpretation |
| --- | --- | --- | --- |
| `packages/common_code_domain` | None | `packages/common_code_application`, `packages/common_code_persistence`, `packages/common_code_observability`, `packages/host_in_memory`, `packages/host_opencode`, `apps/common_code_desktop` | Domain stays pure and framework-independent |
| `packages/common_code_application` | `packages/common_code_domain` | `packages/common_code_persistence`, `packages/common_code_observability`, `packages/host_in_memory`, `packages/host_opencode`, `apps/common_code_desktop` | Application may define stable ports and coordination abstractions, but it must not depend on concrete adapters or app-shell code |
| `packages/common_code_persistence` | `packages/common_code_application`, `packages/common_code_domain` | `packages/common_code_observability`, `packages/host_in_memory`, `packages/host_opencode`, `apps/common_code_desktop` | Any exception requires a later accepted architecture decision; default rule is no adapter-to-adapter dependency |
| `packages/common_code_observability` | `packages/common_code_application`, `packages/common_code_domain` | `packages/common_code_persistence`, `packages/host_in_memory`, `packages/host_opencode`, `apps/common_code_desktop` | Any exception requires a later accepted architecture decision; observability remains adapter-side support |
| `packages/host_in_memory` | `packages/common_code_application`, `packages/common_code_domain` | `packages/common_code_persistence`, `packages/common_code_observability`, `packages/host_opencode`, `apps/common_code_desktop` | Any exception requires a later accepted architecture decision; this adapter satisfies Application-defined host ports inward |
| `packages/host_opencode` | `packages/common_code_application`, `packages/common_code_domain` | `packages/common_code_persistence`, `packages/common_code_observability`, `packages/host_in_memory`, `apps/common_code_desktop` | Any exception requires a later accepted architecture decision; OpenCode stays behind the host adapter seam |
| `apps/common_code_desktop` | `packages/common_code_application`, `packages/common_code_domain` for presentation concerns | No presentation code dependency on `packages/common_code_persistence`, `packages/common_code_observability`, `packages/host_in_memory`, or `packages/host_opencode` | Bootstrap/composition code may depend on adapter packages only to assemble the desktop app; that edge does not authorize package-wide presentation imports |

### Dependency interpretation notes

- `packages/common_code_application` defines the stable ports and interfaces that persistence, observability, and host adapters satisfy.
- Adapter packages depend inward on `packages/common_code_application` and `packages/common_code_domain`; Application and Domain do not depend back on adapter packages.
- `apps/common_code_desktop` has two distinct allowances:
  - presentation code depends on Application-facing APIs and Domain-facing models needed for rendering;
  - app bootstrap/composition code may wire adapter packages at the app edge.
- The app-shell composition allowance is narrower than package-wide permission for desktop presentation code.

## Allowed-import policy

Package-level dependency allowance and import-level access rules are separate. A package may be an allowed dependency and still expose only a narrow public import surface.

1. Cross-package imports must use public package entrypoints only.
   - Allowed shape: `package:some_package/some_package.dart`
   - Forbidden shape: `package:some_package/src/...`
2. `packages/common_code_application` may define stable ports, interfaces, and coordination abstractions consumed by adapters.
   - Adapter packages import Application and Domain to satisfy those ports.
   - Application must not import persistence, host, observability, or app-shell implementations back inward.
3. `apps/common_code_desktop` may import adapter packages only from desktop bootstrap/composition code that assembles the app.
   - Presentation widgets, controllers, and view-shaping code import Application-facing APIs and Domain-facing presentation models only.
   - Presentation code must not import persistence adapters, OpenCode adapters, in-memory host adapters, or observability implementation internals.
4. `packages/common_code_domain` must not import Flutter libraries, storage libraries, OpenCode libraries, transport/client libraries, host adapter implementation libraries, or observability frameworks.
5. Adapter packages must not expose convenience helpers that invite Application or Domain to import runtime-specific, vendor-specific, or framework-specific code back inward.
6. Package dependency allowance does not authorize import reach-through into another package's internal structure, even when the dependency itself is allowed.

## Forbidden dependencies and anti-patterns

The following are architecture violations unless a later accepted decision explicitly narrows an exception:

- Presentation reaching directly into persistence:
  - Example: a Flutter widget imports `packages/common_code_persistence` code to load or mutate storage directly.
- Presentation reaching directly into host adapters:
  - Example: a presentation controller imports `packages/host_opencode` to trigger host behavior instead of going through Application.
- Application importing concrete adapters:
  - Example: an application service imports `packages/host_in_memory`, `packages/host_opencode`, `packages/common_code_persistence`, or `packages/common_code_observability` directly instead of depending on an Application-defined port.
- Domain importing framework, runtime, or vendor concerns:
  - Example: a Domain type imports Flutter, storage serialization helpers, OpenCode SDK/runtime types, transport clients, or logging/telemetry frameworks.
- Adapter-to-adapter dependencies without explicit architecture reason:
  - Example: `packages/common_code_persistence` imports `packages/host_opencode` to reuse convenience logic instead of sharing only approved inward abstractions.
- Cross-package `lib/src/**` reach-through:
  - Example: desktop presentation code imports `package:common_code_application/src/...` or any other package's internal implementation files.
- Treating the desktop app as the reusable home for persistence or host logic:
  - Example: reusable persistence implementation or host adapter behavior is placed in `apps/common_code_desktop` instead of the appropriate adapter package.
- Convenience leakage back into core:
  - Example: an adapter exposes helper APIs that pull OpenCode, storage, or observability implementation types into Application or Domain codepaths.

## Expected implementation and review evidence

This document requires a concrete evidence bundle from future implementation and review slices. The evidence contract is part of the rule set so later execution can prove compliance without reopening architecture intent.

### Required implementation evidence bundle

Future implementation that authors, revises, or applies this matrix must provide all of the following:

1. Final artifact path and title.
   - Artifact path: `docs/architecture/commoncode-dependency-matrix-and-allowed-imports.md`
   - Artifact title: `# CommonCode dependency matrix and allowed imports`
2. A concise checklist showing where the artifact states:
   - layer dependency rules
   - package/module dependency rules
   - allowed-import policy
   - presentation restrictions
   - application-port rule
   - domain purity rule
   - anti-patterns/common violations
   - deferred enforcement boundary
3. A compact per-package dependency summary extracted from the artifact that lists, for each target package/module, its allowed internal dependencies.
4. A changed-files summary proving the slice stayed docs-only and limited to this single artifact.

### Required review evidence

Review must explicitly verify all of the following:

1. The artifact is a bounded architecture rule set, not a disguised implementation or enforcement design.
2. The artifact aligns with ADR 0006 and the accepted target package map without reopening either decision.
3. Layer dependency rules are explicit enough that allowed versus forbidden directions do not require inference.
4. Package/module rules are explicit enough that a later dependency-analysis slice could derive checks without reopening architecture intent.
5. Import-policy wording clearly separates public package imports from forbidden `lib/src/**` reach-through.
6. The app-shell composition-edge allowance is explicit and does not accidentally authorize presentation-layer imports of adapter internals.
7. The anti-pattern section includes concrete reviewable violations rather than abstract warnings only.
8. The artifact does not normalize `packages/host_core` as a target package or drift into package extraction/refactor steps.
9. The final diff is docs-only and limited to one artifact file.

### Evidence bundle content expectations

When this artifact is submitted or revalidated, the evidence bundle should make these checks easy to review:

- identify which layer rule is being followed or violated
- identify which package/module rule is being followed or violated
- show whether imports use public package entrypoints rather than `lib/src/**`
- show whether desktop adapter imports are limited to bootstrap/composition code rather than presentation code
- show whether Application still depends on ports rather than concrete adapters
- show whether Domain remains free of Flutter, storage, transport, OpenCode, host-runtime, and observability-framework concerns

## Deferred enforcement work

Later slices may derive enforcement from this matrix, but this issue intentionally does not decide:

- CI checks
- analyzer or lint rule design
- automated dependency scanning configuration
- implementation sequencing for import rewrites, package extraction, or refactor choreography

## Non-goals

This artifact does not:

- create packages, package manifests, or app modules
- change code, imports, public APIs, or file locations
- rewrite current dependencies
- normalize `packages/host_core` as a canonical target package
- define migration sequencing or implementation choreography
