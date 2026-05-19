# Session Notification semantics

A **Notification** is a routable, acknowledgeable notice about **Session** or **Turn** state that matters outside the currently visible Client state. The **Session** is the source of truth for which Notifications exist and whether each Notification is still unacknowledged, and Notifications route to attached **Clients** in that Session rather than to the **Active Host** or a **Platform** as domain targets.

Acknowledgement is a Session-level state change: once any attached Client acknowledges a Notification, that Notification becomes acknowledged for the Session rather than remaining unread separately per Client. After a Client reconnects, it should receive any still-unacknowledged Notifications for its Session; after a Session restarts, only Notifications that remain unacknowledged in the Session source of truth are replayed.

This decision governs domain semantics only. How a Client renders a Notification, interrupts the User, groups notices, badges counts, or chooses platform-specific presentation behavior belongs to **Presentation** rather than Session Notification semantics.

Out of scope for the first implementation slice: storage design, transport, delivery guarantees, retry policy, replay limits, notification priority, notification history beyond unacknowledged replay, and any UI treatment or client interaction pattern. This ADR is the sole canonical decision artifact for Session Notification semantics and unblocks downstream notification implementation work.
