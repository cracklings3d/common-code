# CommonCode architecture review checklist

## Status and scope

This is the canonical reviewer-facing checklist for issue #50.

- Status: planning/specification only
- Change scope: docs-only
- Applies during the current CommonCode architecture migration program only
- Not a permanent repo-wide review policy

Issue #50 is planning/specification only and does not require implementation.

This checklist inherits the accepted baseline from the prerequisite chain and does not redefine architecture:

- #39 -> `docs/adr/0006-commoncode-layered-architecture-constitution.md`
- #40 -> `docs/architecture/commoncode-target-module-package-map.md`
- #41 -> `docs/architecture/commoncode-dependency-matrix-and-allowed-imports.md`
- #42 -> `docs/architecture/commoncode-application-facade-contract.md`
- #43 -> `docs/architecture/commoncode-application-port-contract-set.md`
- #44 -> accepted OpenCode host-adapter baseline, with `docs/adr/0007-opencode-host-adapter-boundary-and-mapping-rules.md` used for decision content only
- #45 -> `docs/architecture/commoncode-persistence-model-and-adapter-contract.md`
- #46 -> `docs/architecture/commoncode-observability-model-and-diagnostics-boundary.md`

For #44, reviewers should use the accepted prerequisite chain and issue acceptance as the authority for the OpenCode host-adapter baseline even if ADR 0007 still shows stale repo-status text.

## When this checklist applies

- **Planning/specification PRs**: use before approving any PR that adds or revises canonical architecture artifacts under `docs/adr/` or `docs/architecture/`.
- **Implementation/refactor PRs**: use before approving any PR that changes architecture-relevant code or structure, or claims architecture alignment.

This checklist does **not** apply to non-architecture PRs with no architecture-relevant change and no architecture-alignment claim.

## Review checkpoints

- **Planning/specification PR checkpoint**: complete this checklist before approving the architecture artifact change.
- **Implementation/refactor PR checkpoint**: complete this checklist before approving the code or structural change.

## Reviewer checklist

1. **Accepted baseline alignment**
   - Applicability: **both**
   - Review question: Does the PR stay aligned with the accepted baseline from issues #39 through #46 instead of redefining architecture?
   - Evidence to inspect: PR description, changed artifact or diff, cited prerequisite artifacts, and any stated architecture claim.
   - **Not applicable** allowed: No.

2. **Scope discipline and non-goals**
   - Applicability: **both**
   - Review question: Does the PR stay inside its stated slice without reopening accepted decisions, adding new policy, or smuggling in unrelated architecture work?
   - Evidence to inspect: stated scope, non-goals, diff size, and whether the change introduces new rules beyond the accepted baseline.
   - **Not applicable** allowed: No.

3. **Presentation thinness**
   - Applicability: **both**
   - Review question: Does the change keep presentation/app-shell behavior thin rather than making it the owner of persistence, host, observability, or product orchestration concerns?
   - Evidence to inspect: planning text about presentation responsibilities, or implementation diffs in presentation/app-shell code and wiring.
   - **Not applicable** allowed: Yes, for planning/specification PRs with no code evidence and for implementation/refactor PRs that do not touch presentation or app-shell responsibilities.

4. **Application vs domain boundary integrity**
   - Applicability: **both**
   - Review question: Does the PR preserve Application as the coordination boundary and Domain as the pure product-semantic core?
   - Evidence to inspect: contract or boundary language in planning artifacts, or implementation diffs showing ownership of use-case coordination, invariants, and domain meaning.
   - **Not applicable** allowed: Yes, only when the PR does not touch or claim any application/domain boundary behavior.

5. **Dependency direction and allowed imports**
   - Applicability: **both**
   - Review question: Does the change preserve the accepted dependency direction and avoid forbidden inward leaks or cross-package reach-through?
   - Evidence to inspect: dependency/import statements, module/package placement, architecture notes, and any claim of allowed exceptions.
   - **Not applicable** allowed: Yes, for planning/specification PRs with no code imports to inspect.

6. **Persistence placement**
   - Applicability: **both**
   - Review question: Are durable continuity and persistence concerns kept in the accepted persistence boundary rather than moved into Presentation, Domain, host adapters, or ad hoc app-shell seams?
   - Evidence to inspect: persistence-related architecture text, storage-facing code placement, adapter ownership, and any continuity-model claims.
   - **Not applicable** allowed: Yes, when the PR does not touch persistence responsibilities and makes no persistence-alignment claim.

7. **Observability and diagnostics placement**
   - Applicability: **both**
   - Review question: Are observability and diagnostics concerns kept in the accepted Application-to-observability boundary instead of being treated as Domain semantics or presentation-owned behavior?
   - Evidence to inspect: observability-related artifact text, diagnostics/logging/telemetry code placement, and whether user-facing result surfaces are kept distinct from observability plumbing.
   - **Not applicable** allowed: Yes, when the PR does not touch observability or diagnostics responsibilities and makes no such claim.

8. **OpenCode host-adapter boundary integrity and leakage prevention**
   - Applicability: **both**
   - Review question: Does the PR keep OpenCode concerns behind the accepted host-adapter boundary without leaking OpenCode vocabulary, runtime types, or semantic ownership into Application, Domain, Persistence, Observability, or Presentation?
   - Evidence to inspect: OpenCode-related artifact text, package/module placement, boundary language, adapter code, and any mapping or translation logic.
   - **Not applicable** allowed: Yes, only when the PR has no OpenCode or host-adapter impact and makes no host-boundary claim.

9. **Evidence fit for the PR class**
   - Applicability: **both**
   - Review question: Does the PR provide the right kind of evidence for its class: architecture-artifact evidence for planning/specification, and concrete code/structure evidence for implementation/refactor?
   - Evidence to inspect: artifact paths and changed sections for planning/specification PRs; concrete file diffs, imports, placements, and boundary-adherence evidence for implementation/refactor PRs.
   - **Not applicable** allowed: No. Code-evidence-oriented checks above may be marked **not applicable** for planning/specification PRs when no code evidence exists, but those checklist items remain in force.

Completion of issue #50 also requires an explicit acceptance comment on issue #50 that links this approved checklist document: `docs/architecture/commoncode-architecture-review-checklist.md`.
