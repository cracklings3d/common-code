# Context Map

CommonCode's domain language still describes a broader multi-client continuation model, but the currently shipped implementation is a single desktop slice with simulated host behavior and local snapshot restore.

## Domain language and future model intent

- [Session Orchestration](./contexts/session-orchestration/CONTEXT.md) - defines sessions, attached clients, prompt threads, input-client ownership, and notifications as the broader continuity model
- [Execution](./contexts/execution/CONTEXT.md) - defines the host-facing model where one active host processes turns for a session
- [Presentation](./contexts/presentation/CONTEXT.md) - defines how each client can present the session on a platform-specific surface

These context docs describe the intended domain model and vocabulary for future slices. They should not be read as a claim that multi-client or external-host behavior is already shipped in the current app.

## Currently shipped desktop slice

- The shipped app is the Windows desktop client in `apps/common_code_desktop`.
- `DesktopSessionController.initialize()` bootstraps the session runtime for the desktop app.
- When no local snapshot is restored, the controller creates `desktop-session`, attaches `desktop-client`, and begins watching that session.
- The desktop presentation renders the prompt thread, attached clients, input-client state, and composer state.
- Turn submission originates from the desktop composer and updates the same watched session.
- The presentation emits snackbars for observed turn transitions to running, completed, and failed states.

## Simulated host and runtime behavior used now

- The active host behavior is currently provided by the in-memory implementation in `packages/host_core`.
- Submitted turns are simulated through `queued -> running -> completed` or `failed` transitions.
- The desktop runtime mirrors the latest session to local snapshot storage and attempts to restore it on startup.
- This is a local desktop persistence path, not a cross-client synchronization mechanism.

## Current code seams

- **domain** -> `packages/common_code_domain`
- **host** -> `packages/host_core`
- **desktop controller/runtime** -> `apps/common_code_desktop/lib/src/desktop_session_controller.dart` and `apps/common_code_desktop/lib/src/desktop_session_snapshot_store.dart`
- **presentation** -> `apps/common_code_desktop/lib/main.dart`

## Relationships in the current slice

- **domain -> host**: domain session, client, host, prompt thread, and turn types define what the host service reads and updates
- **host -> desktop controller/runtime**: the desktop controller bootstraps the session, submits turns, watches session updates, and persists the latest snapshot
- **desktop controller/runtime -> presentation**: the controller exposes session state for prompt-thread rendering, authoring availability, refresh, and submission
- **presentation -> desktop controller/runtime**: the desktop UI initializes the controller, submits turns, refreshes the watched session, and renders lifecycle notices
