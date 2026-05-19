# CommonCode

CommonCode is a continuation-oriented workspace for OpenCode. The currently shipped slice is a Windows desktop Flutter app backed by shared Dart packages for domain types and host behavior.

## Workspace layout

```text
.
├─ apps/
│  └─ common_code_desktop/    # Shipped desktop presentation and session controller
├─ packages/
│  ├─ common_code_domain/     # Shared domain exports for sessions, clients, hosts, and turns
│  └─ host_core/              # Host service contract plus in-memory host implementation
└─ tool/                      # Root orchestration and validation scripts
```

## Current desktop behavior

The current shipped behavior is one desktop session slice:

1. `DesktopSessionController.initialize()` bootstraps the desktop session.
2. The controller creates `desktop-session` and attaches `desktop-client` when no local snapshot can be restored.
3. The desktop app renders the prompt thread, current session context, attached clients, and authoring state.
4. The composer submits turns from the desktop client into the host service.
5. The current host implementation simulates the turn lifecycle as `queued -> running -> completed` or `failed`.
6. The desktop controller persists the latest session snapshot locally and restores it on the next launch when possible.
7. The desktop presentation emits snackbars when a turn transitions to running, completed, or failed.

## Current limitations and simulated behavior

### Shipped now

- Windows desktop is the only active client target in this repository slice.
- The desktop app can bootstrap a session, attach the local desktop client, render prompt thread history, submit turns, and restore a locally persisted snapshot.

### Simulated or in-memory now

- Host execution is provided by the in-memory host service in `packages/host_core`.
- Turn progress is simulated with timers rather than a real external host.
- Snapshot restore uses local desktop persistence, not shared cross-device state.

### Intended later, not shipped yet

- External host integration.
- Live cross-client execution handoff across multiple real clients.
- Additional client targets beyond the current desktop slice.

## Architecture seams

- **domain** - `packages/common_code_domain`
- **host** - `packages/host_core`
- **desktop controller/runtime** - `apps/common_code_desktop/lib/src/desktop_session_controller.dart` and `apps/common_code_desktop/lib/src/desktop_session_snapshot_store.dart`
- **presentation** - `apps/common_code_desktop/lib/main.dart`

## Entry points

- `apps/common_code_desktop/lib/main.dart`
- `apps/common_code_desktop/lib/src/desktop_session_controller.dart`
- `packages/common_code_domain/lib/common_code_domain.dart`
- `packages/host_core/lib/host_core.dart`

## Validation commands

Run all commands from the repository root:

- `pwsh -File tool/bootstrap.ps1`
- `pwsh -File tool/analyze.ps1`
- `pwsh -File tool/test.ps1`
- `pwsh -File tool/run_windows.ps1`

## Current project docs

- `CONTEXT-MAP.md`
- `GLOSSARY.md`
- `contexts/session-orchestration/CONTEXT.md`
- `contexts/execution/CONTEXT.md`
- `contexts/presentation/CONTEXT.md`
- `docs/adr/`
