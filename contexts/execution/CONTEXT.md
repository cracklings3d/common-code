# Execution

Execution defines where CommonCode processes work and how that processing survives device changes. It exists so a Session can stay attached to one active Host while Clients reconnect from different platforms.

## Language

**Host**:
The execution runtime responsible for processing Turns for a Session.
_Avoid_: Agent, runner, machine

**Host Machine**:
The desktop, laptop, or server that runs a Host.
_Avoid_: Host, client device

**Active Host**:
The Host currently bound to a Session and authorized to process its active Turn.
_Avoid_: Owner host, primary machine

## Relationships

- A **Host** runs on exactly one **Host Machine**
- A **Session** binds to exactly one **Active Host** at a time
- An **Active Host** processes the **Session**'s active **Turn**
- A **Host** may process Turns for many **Sessions**
- In the first version, a **Host Machine** is a desktop, laptop, or server rather than a phone

## Example dialogue

> **Dev:** "The User left the PC, opened the phone client, and the Turn kept running. Did execution move to the phone?"
> **Domain expert:** "No. The same Host kept processing that Turn on its Host Machine, and the phone client just reattached to the Session."

## Flagged ambiguities

- "host" was used ambiguously for both the runtime and the machine - resolved: **Host** is the runtime and **Host Machine** is the machine
- Session-level parallel work was discussed - resolved: a **Session** has at most one active **Turn** at a time, even if that Turn internally uses subagents
