# Presentation

Presentation defines how much UI a Client exposes on a given platform without breaking Session continuity. It exists so CommonCode can feel native to each platform while still participating in the same Session and Prompt Thread.

## Language

**Platform**:
The class of environment a Client runs on, such as phone, desktop, or web.
_Avoid_: Device type, target

**Presentation Profile**:
The configurable description of how much UI and interaction a Client exposes on a Platform.
_Avoid_: Surface profile, layout, mode

**Presentation Capability**:
A separately configurable slice of UI or interaction granted by a Presentation Profile.
_Avoid_: Feature flag, widget, screen

## Relationships

- A **Client** runs on exactly one **Platform** at a time
- A **Client** uses exactly one **Presentation Profile** at a time
- A **Presentation Profile** targets one **Platform** and grants many **Presentation Capabilities**
- Different **Clients** on different **Platforms** may represent the same **Session** with different **Presentation Profiles**

## Example dialogue

> **Dev:** "Why does the phone show only a narrow authoring view while the desktop shows more controls for the same Session?"
> **Domain expert:** "Because those Clients use different Presentation Profiles for different Platforms, even though they are attached to the same Session."

## Flagged ambiguities

- "UI" was too broad for the domain discussion - resolved: use **Presentation** for the platform-specific shape of the product
- "surface profile" was proposed for the configurable UI shape - resolved: use **Presentation Profile** instead
