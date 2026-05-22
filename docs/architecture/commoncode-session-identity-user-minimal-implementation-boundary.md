# CommonCode Session-owned Identity and User minimal implementation boundary

## 1. Status and scope

- Status: planning/specification only
- Canonical planning artifact for issue #80 under tracker #77
- Sole repository artifact for this slice: `docs/architecture/commoncode-session-identity-user-minimal-implementation-boundary.md`
- Prerequisite planning authority for implementation issue #86

This artifact defines the smallest current-stage implementation boundary for Session-owned `Identity` and `User` semantics without reopening accepted architecture, package ownership, facade or port design, authentication design, or broader identity-system work.

## 2. Governing artifacts

- Issue #80
- Issue #86
- `GLOSSARY.md`
- `contexts/session-orchestration/CONTEXT.md`
- `docs/architecture/commoncode-application-port-contract-set.md`
- `docs/architecture/commoncode-application-facade-contract.md`
- `docs/architecture/commoncode-target-module-package-map.md`
- `docs/architecture/commoncode-dependency-matrix-and-allowed-imports.md`
- `docs/adr/0006-commoncode-layered-architecture-constitution.md`
- `docs/adr/0007-opencode-host-adapter-boundary-and-mapping-rules.md`

## 3. Problem and trigger

CommonCode already distinguishes the human `User` from the authenticated `Identity` attached to a `Session`, and the accepted architecture already defines an Application-owned identity-context contract need. What was missing for issue #80 was one canonical planning artifact that states exactly how far current-stage implementation may go, what each layer owns now, and what work is authorized next without drifting into redesign.

## 4. Vocabulary guardrail: `User` vs `Identity`

The glossary distinction is fixed for this stage and must not collapse:

- `User` = the human who uses CommonCode through one or more Clients
- `Identity` = the authenticated identity attached to a Session

The Session relationship from the governing context remains authoritative:

- a Session belongs to exactly one `Identity`
- a Session is used by exactly one `User`

This slice does not redefine `User` as an account object and does not redefine `Identity` as the human actor.

## 5. Minimal boundary decision

The current stage does **not** require a full implemented dual-concept model for both `User` and `Identity`.

The minimal boundary decision is:

- implement only the bounded session-owned identity/client-context seam already implied by the accepted Application identity-context contract
- keep that seam limited to the current desktop flow consumed by issue #86
- do not broaden into a user model, account system, auth subsystem, package-level identity module, or broader identity architecture

## 6. Current-stage ownership by layer

### Domain

Domain owns semantic authority only in this slice.

Belongs in Domain now:

- preservation of the `User` vs `Identity` distinction
- preservation of the Session rule that one Session belongs to one `Identity` and is used by one `User`
- vocabulary authority for later slices if richer modeling is explicitly authorized

Does not belong in Domain now:

- authentication mechanics
- authorization rules
- account or profile management
- vendor or runtime identity mapping
- package-map expansion
- broad Session redesign just to model `User`

### Application

Application owns the already-accepted contract need, not a redesign.

Belongs in Application now:

- the contract-level need to resolve session-bound `Identity` and attached-client context for orchestration
- use of the already-accepted identity-context seam from `docs/architecture/commoncode-application-port-contract-set.md`
- coordination rules that require identity/client-context resolution before orchestration consumes that context in the current desktop flow

Does not belong in Application now:

- Application Facade redesign
- Application port or API redesign
- conversion of the identity-context seam into a broader auth or account API
- new canonical package ownership
- making `User` an immediate implemented requirement for this stage

### Outer adapter / app-edge

Outer adapter/app-edge code remains the current concrete implementation home for this slice.

Belongs at the outer adapter/app-edge now:

- concrete resolution of the session-bound `Identity` value and attached-client context used by the current desktop flow
- supplying that context through the already-accepted Application-owned seam
- desktop-flow wiring plus the tests and fixtures needed by issue #86

Does not belong at the outer adapter/app-edge now:

- redefining CommonCode semantics in vendor or runtime terms
- creating a new canonical identity package
- bypassing Application so presentation or adapter internals own product semantics
- auth redesign
- OpenCode identity mapping redesign
- remote trust, protocol, IPC, or transport design

## 7. Implemented-representation decision for this stage

This artifact makes the current-stage implementation decision explicit:

- **Identity:** yes, but only as a bounded implemented representation needed to satisfy the current desktop-flow session-bound identity/client-context seam
- **User:** no, not as a new implemented representation in this stage; `User` remains vocabulary-only for now

`User` may gain richer implemented representation only in a later accepted slice that proves a concrete behavior need beyond this bounded seam.

## 8. Bounded follow-on authorized for issue #86

Approval of issue #80 authorizes only issue #86 as follow-on implementation work.

Issue #86 is authorized to:

- implement the accepted session-bound identity/client-context seam for the current desktop flow
- resolve that context before orchestration consumes it during desktop bootstrap and any current desktop command-handling path that needs it
- update tests and fixtures for that live seam

No broader follow-on is authorized by this artifact.

## 9. Explicit constraints and forbidden drift

This slice explicitly forbids:

- package-map expansion
- Application Facade redesign
- Application port or API redesign
- authentication redesign
- authorization redesign
- OpenCode identity mapping redesign
- remote trust, protocol, IPC, or transport design
- broad identity-system work beyond the bounded seam consumed by #86

This artifact also does not authorize user-model implementation work, remote or multi-tenant trust design, or any second implementation slice adjacent to #86.

## 10. Out of scope / non-goals

Out of scope for issue #80:

- code implementation
- package creation or ownership changes
- facade, port, or contract replacement
- concrete Dart API, DTO, class, field, or transport design
- auth/authz, account lifecycle, or security-system design
- OpenCode runtime remapping of CommonCode product semantics
- broader reinterpretation of accepted architecture

## 11. Acceptance mapping to issue #80

This artifact satisfies issue #80 by stating that:

- it is the canonical planning child under tracker #77 for this topic
- it is the prerequisite planning authority for #86
- `User` and `Identity` remain distinct glossary concepts
- current-stage ownership is split explicitly across Domain, Application, and outer adapter/app-edge
- `Identity` gets bounded implemented representation now
- `User` remains vocabulary-only for this stage
- authorized follow-on work is bounded to issue #86 only
- package-map, facade, port/API, auth, OpenCode identity mapping, remote trust/transport, and broad identity-system drift are forbidden

Completion of issue #80 still requires an explicit acceptance comment on the issue linking this document as the approved canonical artifact.
