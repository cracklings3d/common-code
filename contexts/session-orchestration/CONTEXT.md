# Session Orchestration

Session Orchestration keeps a User's work continuous while Clients attach, detach, and hand off input across platforms. It exists so device changes do not interrupt the same Session, Prompt Thread, or active Turn.

## Language

**User**:
The human who uses CommonCode through one or more Clients.
_Avoid_: Operator, actor, account

**Identity**:
The authenticated identity attached to a Session, regardless of whether it came from sign-in, a token, or another credential flow.
_Avoid_: Sign-in, login, account

**Session**:
The continuity boundary that keeps one User's Prompt Thread, attached Clients, Notifications, and active Turn coherent across device switches.
_Avoid_: Connection, login session, workspace

**Client**:
A platform-specific CommonCode presence that attaches to a Session to display state, author Turns, and receive Notifications.
_Avoid_: Device, frontend, UI

**Input Client**:
The attached Client currently authoring the next Turn.
_Avoid_: Focus client, primary client, active device

**Prompt Thread**:
The ordered conversation of Turns inside a Session.
_Avoid_: Chat, history, transcript

**Turn**:
The single submitted unit of work in a Prompt Thread that the Session advances through one at a time.
_Avoid_: Run, job, task

**Notification**:
A routable, acknowledgeable notice sent to a Client about Session or Turn state.
_Avoid_: Toast, popup, alert

## Relationships

- A **Session** belongs to exactly one **Identity** and is used by exactly one **User**
- A **Session** contains exactly one **Prompt Thread**
- A **Prompt Thread** contains zero or more **Turns**
- A **Session** may have many attached **Clients**
- At most one attached **Client** is the **Input Client** at any moment
- A **Session** may have at most one active **Turn** at a time
- A **Notification** is routed to one or more **Clients**

## Example dialogue

> **Dev:** "The User started typing on the phone while the desktop client was still open. Did we create a new Session?"
> **Domain expert:** "No. The same Session stayed active, the phone became the Input Client by starting the next Turn, and the desktop client kept observing that same Prompt Thread."

## Flagged ambiguities

- "user" was initially used to mean both the human and the sign-in identity - resolved: **User** is the human and **Identity** is the authenticated identity
- "focus client" was proposed for the authoring client - resolved: use **Input Client** instead
