# host_core

`host_core` exposes the first CommonCode host boundary as a pure Dart, typed,
in-process service.

This package is intentionally narrow for issue #3:

- create a `Session`
- attach one `Client`
- read the current `Session` snapshot

The current implementation is an in-memory desktop-safe path used directly by
the Flutter desktop app in the same process. It is not the final transport
architecture and does not introduce networking, IPC, platform channels,
isolates, or persistence.

## Usage

```dart
import 'package:common_code_domain/common_code_domain.dart';
import 'package:host_core/host_core.dart';

final hostService = createInMemoryHostService();

hostService.createSession(
  sessionId: 'session-1',
  activeHost: const Host(id: 'desktop-host'),
);

hostService.attachClient(
  sessionId: 'session-1',
  client: const Client(id: 'desktop-client'),
);

final session = hostService.readSession('session-1');
```

## Public boundary

- `HostService`
- `createInMemoryHostService()`
- `HostServiceFailure`
- `HostServiceFailureCode`
