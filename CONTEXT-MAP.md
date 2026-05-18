# Context Map

CommonCode is a multi-platform continuation layer for OpenCode. It keeps a User's work coherent across Clients, lets execution stay on a Host while the User moves between devices, and shapes each Client's Presentation to fit the platform without breaking continuity.

## Contexts

- [Session Orchestration](./contexts/session-orchestration/CONTEXT.md) - keeps Sessions, attached Clients, Prompt Threads, Input Client handoff, and Notifications coherent across devices
- [Execution](./contexts/execution/CONTEXT.md) - binds each Session to one active Host and processes Turns there
- [Presentation](./contexts/presentation/CONTEXT.md) - defines the configurable amount of UI each Client exposes on each platform

## Current Implementation Direction

- CommonCode will be built issue by issue rather than through a separate MVP phase.
- Client applications use Flutter so the same client stack can target desktop now and phone support later.
- The first implementation slices stay narrowly scoped, actionable, and testable, even when they only establish one end-to-end path.
- Desktop remains the first active client target while the project structure keeps room for later phone clients.

## Relationships

- **Session Orchestration -> Execution**: a Session binds to one active Host; each Turn is handed to Execution for processing
- **Execution -> Session Orchestration**: Host progress and completion update Session state and produce Notifications
- **Session Orchestration -> Presentation**: each attached Client uses a Presentation Profile to render the current Session and receive routed Notifications
- **Presentation -> Session Orchestration**: when an attached Client starts authoring a Turn, Session Orchestration promotes it to the Input Client
