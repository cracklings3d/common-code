# CommonCode architecture enforcement and guardrails

## Status and scope

- Status: planning/specification only
- Change scope: docs-only
- Canonical artifact for issue #51
- Deliverable scope: define enforcement strategy and guardrails for the already-accepted CommonCode architecture baseline

This artifact derives from and does not reopen the accepted architecture baseline from issues #39 through #48. Its job is to define enforcement strategy for those accepted rules, not to replace layer ownership, package ownership, dependency direction, contract placement, OpenCode boundaries, persistence semantics, observability semantics, current-to-target mapping, or migration stage ordering.

This artifact does not add tooling, CI rules, analyzers, scripts, lints, branch protection, or machine enforcement implementation. The required explicit acceptance comment linking this artifact on issue #51 remains a separate non-diff completion action.

## Alignment with accepted architecture baseline

The guardrails in this document protect the accepted architecture baseline established by the following artifacts:

| Issue | Accepted artifact | Guarded baseline |
| --- | --- | --- |
| #39 | `docs/adr/0006-commoncode-layered-architecture-constitution.md` | Governing layered constitution and one-way dependency direction |
| #40 | `docs/architecture/commoncode-target-module-package-map.md` | Canonical target package/module ownership |
| #41 | `docs/architecture/commoncode-dependency-matrix-and-allowed-imports.md` | Dependency-direction and allowed-import rule surface |
| #42 | `docs/architecture/commoncode-application-facade-contract.md` | Presentation-to-Application facade boundary |
| #43 | `docs/architecture/commoncode-application-port-contract-set.md` | Application-owned ports/contracts boundary |
| #44 | `docs/adr/0007-opencode-host-adapter-boundary-and-mapping-rules.md` | OpenCode host-adapter boundary |
| #45 | `docs/architecture/commoncode-persistence-model-and-adapter-contract.md` | Persistence placement behind the Application-owned session store port |
| #46 | `docs/architecture/commoncode-observability-model-and-diagnostics-boundary.md` | Observability placement behind the Application-owned diagnostics boundary |
| #47 | `docs/architecture/commoncode-current-to-target-architecture-mapping.md` | Transitional seam mapping, including non-canonical current seams |
| #48 | `docs/architecture/commoncode-staged-migration-plan.md` | Stage ordering and rollout safety constraints |

Issue #41 is the primary accepted rule surface for eventual automation because it already expresses the target dependency matrix and import-boundary policy in reviewable rule form. This artifact classifies how that accepted rule surface should be enforced over time.

## Inherited rule surface from issues #39-#48

This enforcement strategy guards, at minimum, the following inherited rule classes:

- layer direction and layer responsibilities from issue #39
- target package/module ownership from issue #40
- dependency matrix and allowed-import rules from issue #41
- Presentation depends on Application-facing APIs rather than adapter implementations from issue #42
- Application depends on stable ports/contracts rather than concrete adapters from issue #43
- OpenCode-specific behavior stays behind the host adapter seam from issue #44
- persistence remains adapter-side and product-semantic from issue #45
- observability contract ownership remains in Application with concrete implementations adapter-side from issue #46
- transitional seams such as `packages/host_core` remain current-state mapping inputs, not canonical target architecture, from issue #47
- rollout safety must respect the accepted migration ordering `S1` through `S5` from issue #48

## Enforcement decision model

Every guardrail in this document is classified into one of these explicit enforcement buckets:

1. **Review-enforced during migration**
   - Used when the architecture rule is already accepted and reviewers can safely block new violations now.
   - Appropriate when current transitional seams still make hard machine failure too early or too noisy.

2. **Candidate for machine enforcement**
   - Used when the accepted rule surface is precise enough to justify later static validation, import-surface validation, or CI verification.
   - Machine enforcement may still start after a named rollout stage even when review enforcement starts earlier.

3. **Deferred until migration prerequisites are complete**
   - Used when hard enforcement would falsely fail against known transitional seams or before accepted target seams exist.
   - These rules still guide review, but machine enforcement waits until the relevant migration prerequisites are stable.

The decision priority is:

1. preserve no-regression review guardrails immediately where possible;
2. automate highest-value issue #41 rule surfaces once the relevant target seams exist;
3. defer hard enforcement that would accidentally normalize or punish accepted transitional architecture.

## Enforcement categories

The major enforcement categories for this repo are:

1. **Review policy and checklist enforcement** for immediate no-regression decisions during migration.
2. **Static dependency validation** for package/layer dependency direction and adapter-leakage rules once seams are stable.
3. **Public-import-surface validation** for public entrypoint imports versus forbidden `lib/src/**` reach-through.
4. **CI verification** for running already-approved automated checks once rollout is safe.
5. **Migration-stage rollout gates** for deciding which rules are safe now, which become hard checks later, and which remain deferred until prerequisite stages complete.

These categories are intentional enforcement classes only. They do not prescribe specific tools, packages, scripts, commands, or CI YAML.

## Canonical guardrail inventory

| rule_source | rule_summary | scope_boundary | enforcement_mode | earliest_safe_rollout_stage | prerequisites | required_evidence | notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| #39, #40, #41 | Preserve target layer/package dependency direction and forbid reverse dependencies that violate `Presentation -> Application Facade -> Domain` with adapters depending inward. | All target packages/modules named in issue #40. | Review-enforced during migration; candidate for machine enforcement after target package seams are stable. | S1 for review, S5 for hard machine enforcement across the full target map. | Accepted target package map (#40), dependency matrix (#41), retirement of transitional mixed seams from #47/#48. | Rule source cited; changed-file scope; examples of forbidden reverse dependencies; validation or review evidence that no new reverse path was introduced. | High-value automation candidate from issue #41, but full hard enforcement is unsafe while transitional seams still mix responsibilities. |
| #41, #42 | Forbid Presentation feature behavior from depending directly on persistence adapters, host adapters, or observability implementations. | Presentation code across target packages plus regular presentation code inside `apps/common_code_desktop`; excludes the narrow desktop bootstrap/composition edge. | Review-enforced during migration; candidate for machine enforcement. | S1 | Accepted facade boundary (#42) and dependency/import policy (#41). | Rule source cited; changed-file scope; examples of blocked Presentation-to-adapter imports; evidence that any adapter imports are limited to app-edge composition only. | One of the highest-value no-regression checks because new Presentation leakage is easy to detect and costly to unwind later. |
| #41, #43 | Protect the rule that Application depends on ports/contracts rather than concrete persistence, host, or observability adapters. | `packages/common_code_application` and any future Application-owned code. | Review-enforced during migration; candidate for machine enforcement. | S1 for review, S4 for broader hard machine enforcement once observability and host seams are re-homed. | Accepted application port contract set (#43), accepted adapter package ownership (#40), dependency matrix (#41). | Rule source cited; changed-file scope; examples of forbidden Application-to-adapter imports; validation or review evidence that dependencies remained on Application-owned contracts. | Highest-value automation candidate after issue #41 because it protects the core inward dependency contract. |
| #39, #41, #44, #45, #46 | Preserve Domain purity against Flutter, storage, transport, OpenCode, host-runtime, and observability-framework leakage. | `packages/common_code_domain` only. | Candidate for machine enforcement with concurrent review enforcement during migration. | S1 | Accepted layered constitution (#39) and dependency/import policy (#41); package placement baselines for OpenCode, persistence, and observability (#44-#46). | Rule source cited; changed-file scope; examples of forbidden framework/runtime/vendor/storage imports; validation or review evidence that Domain remained pure. | High-value automation candidate because the forbidden import classes are explicit and stable early. |
| #41 | Enforce public package entrypoint imports and forbid cross-package `lib/src/**` reach-through. | All cross-package imports in target packages/modules and app-edge code. | Candidate for machine enforcement with review enforcement during migration. | S1 | Accepted import policy (#41). | Rule source cited; changed-file scope; examples of public-entrypoint compliance and blocked `lib/src/**` imports; validation or review evidence showing import-surface compliance. | High-value automation candidate because the rule is precise, repo-wide, and does not depend on later business semantics. |
| #41 | Preserve the narrow desktop bootstrap/composition allowance without broadening it into package-wide Presentation permission to import adapters. | `apps/common_code_desktop` only, with explicit distinction between bootstrap/composition code and regular Presentation widgets/controllers/view-shaping code. | Review-enforced during migration; deferred until migration prerequisites are complete for machine enforcement. | S1 for review, S5 for hard machine enforcement. | Accepted desktop app-edge allowance (#41), staged migration completion that leaves the app as presentation and app-edge composition only (#48). | Rule source cited; changed-file scope; evidence identifying which files are app-edge composition versus regular Presentation; review evidence that adapter imports were not broadened. | Needs review-first enforcement because hard automation is unsafe until app-edge and regular Presentation seams are cleaner and more durable. |
| #40, #47, #48 | Prevent transitional seam normalization, especially treating `packages/host_core` or similar mixed seams as canonical target architecture. | Transitional seams and any docs/review claims about target ownership. | Review-enforced during migration; deferred until migration prerequisites are complete for machine enforcement. | S1 for review, S5 for hard machine enforcement. | Accepted current-to-target mapping (#47) and staged retirement of transitional seams (#48). | Rule source cited; changed-file scope; examples showing transitional seams were treated as current-state mapping inputs only; review evidence that no change re-canonized mixed seams. | This guardrail exists to stop migration drift and to keep current-state exceptions from becoming permanent architecture. |

## Highest-value automation candidates

The highest-value candidates for eventual automation come primarily from issue #41 because its accepted rule surface is already explicit enough to be checked without reopening architecture intent.

Priority automation candidates are:

1. dependency-direction violations between target packages/modules
2. forbidden direct Presentation dependencies on persistence, host, and observability adapters
3. Application importing concrete adapters instead of depending on ports/contracts
4. Domain importing forbidden Flutter, storage, transport, OpenCode, host-runtime, or observability-framework concerns
5. cross-package `lib/src/**` imports instead of public package entrypoints

Some of these rules still begin as review-enforced first because early hard failure could misclassify accepted transitional seams, especially around app-edge composition and current mixed seams such as `packages/host_core`. Review should block new violations immediately even where machine enforcement must wait.

## Migration-stage rollout guidance

The accepted migration ordering remains:

| Stage | Accepted rollout intent | Enforcement guidance |
| --- | --- | --- |
| S1 | stabilize presentation-to-application boundaries and split mixed orchestration seams before re-homing adapter concerns | Safe to apply immediate no-regression review guardrails for Presentation thinness, Application-to-port discipline, Domain purity, and public import surfaces. Limited automation candidates may begin only where the current seams already match the accepted target rule. |
| S2 | separate and re-home persistence-owned continuity, snapshot, and translation responsibilities | Safe to tighten review evidence for persistence-boundary compliance. Hard enforcement of persistence-specific dependency rules becomes safer only after the relevant persistence seams are no longer mixed with transitional current-state code. |
| S3 | separate and re-home host gateway, session observation, and in-memory host adapter responsibilities while draining transitional host_core ownership | Safe point to increase confidence in host-boundary review checks. Hard checks that assume `packages/host_core` retirement must still wait until transitional ownership is no longer canonical in practice. |
| S4 | re-home observability and diagnostics responsibilities behind the accepted Application-owned observability port and observability adapter boundary | Safe point to harden more Application-versus-observability adapter rules once observability responsibilities are clearly re-homed. |
| S5 | retire transitional seams and leave `apps/common_code_desktop` as presentation and app-edge composition only | Safe point for full hard enforcement across the target package map, including stronger machine checks around desktop composition-edge exceptions and transitional-seam retirement. |

Rollout policy:

- **Safe immediately as no-regression review policy:** do not introduce new Presentation-to-adapter leakage, Application-to-concrete-adapter leakage, Domain impurity, or cross-package `lib/src/**` reach-through.
- **Automate only after the relevant seams stabilize:** package-direction checks and adapter-boundary checks should become hard failures only once the target packages and boundaries they assume actually exist.
- **Wait until later stages retire transitional seams:** rules that would falsely fail because `packages/host_core` or similar mixed seams are still being drained remain deferred from hard machine enforcement.
- **Do not hard-enforce against accepted transitional architecture:** rollout must not fail work solely because issue #48 still schedules a current seam for migration.

## Package/layer boundaries versus app-edge composition allowance

Package/layer guardrails apply broadly across the accepted target architecture. The desktop app's bootstrap/composition edge is a narrow exception area, not a general Presentation permission to import adapter packages.

Review and later automation must distinguish between:

- **allowed app-edge composition code** in `apps/common_code_desktop` that wires approved adapter packages to assemble the desktop app; and
- **regular Presentation code** such as widgets, controllers, and view-shaping logic, which must continue to depend on Application-facing APIs and Domain-facing presentation models only.

This distinction keeps package/layer guardrails stricter than temporary app-edge composition allowances and prevents the desktop exception from broadening into package-wide adapter access.

## Evidence expectations for future guardrail work

Any future implementation slice that introduces, applies, or claims compliance with an architecture guardrail should provide evidence that is reusable for both review-only guardrails and future automated checks.

Required evidence categories are:

1. the guardrail or rule source being enforced
2. the enforcement mode being added or applied
3. the migration-stage rationale explaining why the guardrail is safe now
4. changed-file scope proving the slice stayed within approved boundaries
5. examples of the violation classes covered or prevented
6. validation output or review evidence showing the guardrail behaves as intended without reopening the accepted baseline

At minimum, a compliant future guardrail slice should show:

| Evidence field | Expectation |
| --- | --- |
| Rule source | Cite the accepted artifact(s) being guarded, especially issue #41 when the work enforces dependency or import rules. |
| Enforcement mode | State whether the slice adds review policy, machine validation, CI verification, or rollout-gate behavior. |
| Stage rationale | State the earliest safe rollout stage and why the relevant prerequisites are complete enough now. |
| Changed-file scope | Show that the implementation stayed inside the approved file/component boundary for that slice. |
| Violation classes covered | Name the exact dependency, import, or boundary violations the slice prevents or detects. |
| Validation evidence | Show either review evidence or automated validation output proving the guardrail works without redefining architecture ownership. |

## Non-goals

This artifact does not:

- implement tooling, scripts, analyzers, or CI configuration
- define exact commands, packages, lints, or repository settings
- move files, rewrite imports, create packages, or change production/test code
- reopen accepted architecture decisions from issues #39 through #48
- replace the separate issue-level acceptance comment required for issue #51 completion
