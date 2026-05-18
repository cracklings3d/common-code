# CommonCode

CommonCode is a multi-platform continuation layer for OpenCode.

Its goal is to let a user move between clients and platforms without losing continuity. A turn can keep running on a host while the user reconnects from another client, receives notifications there, and continues the same prompt thread from the most appropriate interface for that platform.

## Core Ideas

- Sessions keep work continuous across clients.
- Hosts process turns independently of the currently active client.
- Presentation profiles let each platform expose the right amount of UI.
- Notifications are routed across clients so the next action can happen on the device the user is holding.

## Current Project Docs

- `CONTEXT-MAP.md`
- `GLOSSARY.md`
- `contexts/session-orchestration/CONTEXT.md`
- `contexts/execution/CONTEXT.md`
- `contexts/presentation/CONTEXT.md`
- `docs/adr/`

## Status

The repository is currently in the bootstrap stage. The domain language and a few initial architectural decisions are documented, and implementation will proceed issue by issue.
