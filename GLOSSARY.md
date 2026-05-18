# Glossary

This glossary is the quick-reference vocabulary for CommonCode. The context files remain the source of truth when a term needs fuller boundaries or relationships.

## Session Orchestration

**User**:
The human who uses CommonCode through one or more Clients.
Avoid: Operator, actor, account

**Identity**:
The authenticated identity attached to a Session, regardless of whether it came from sign-in, a token, or another credential flow.
Avoid: Sign-in, login, account

**Session**:
The continuity boundary that keeps one User's Prompt Thread, attached Clients, Notifications, and active Turn coherent across device switches.
Avoid: Connection, login session, workspace

**Client**:
A platform-specific CommonCode presence that attaches to a Session to display state, author Turns, and receive Notifications.
Avoid: Device, frontend, UI

**Input Client**:
The attached Client currently authoring the next Turn.
Avoid: Focus client, primary client, active device

**Prompt Thread**:
The ordered conversation of Turns inside a Session.
Avoid: Chat, history, transcript

**Turn**:
The single submitted unit of work in a Prompt Thread that the Session advances through one at a time.
Avoid: Run, job, task

**Notification**:
A routable, acknowledgeable notice sent to a Client about Session or Turn state.
Avoid: Toast, popup, alert

## Execution

**Host**:
The execution runtime responsible for processing Turns for a Session.
Avoid: Agent, runner, machine

**Host Machine**:
The desktop, laptop, or server that runs a Host.
Avoid: Host, client device

**Active Host**:
The Host currently bound to a Session and authorized to process its active Turn.
Avoid: Owner host, primary machine

## Presentation

**Platform**:
The class of environment a Client runs on, such as phone, desktop, or web.
Avoid: Device type, target

**Presentation Profile**:
The configurable description of how much UI and interaction a Client exposes on a Platform.
Avoid: Surface profile, layout, mode

**Presentation Capability**:
A separately configurable slice of UI or interaction granted by a Presentation Profile.
Avoid: Feature flag, widget, screen

## Working Model

- A User works through a Session.
- A Session contains one Prompt Thread.
- A Prompt Thread advances through Turns one at a time.
- A Session may have many attached Clients.
- Any attached Client may become the Input Client by starting the next Turn.
- A Session binds to one Active Host at a time.
- The Host runs on a Host Machine.
- A Client runs on one Platform and uses one Presentation Profile.
- Notifications are routed to Clients and can be acknowledged.

## Source Contexts

- `contexts/session-orchestration/CONTEXT.md`
- `contexts/execution/CONTEXT.md`
- `contexts/presentation/CONTEXT.md`
