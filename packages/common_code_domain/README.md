# common_code_domain

`common_code_domain` contains the first shared CommonCode domain model in pure
Dart.

## Scope

This package currently models only the issue #2 shared domain core:

- `Session`
- `PromptThread`
- `Turn`
- `Client`
- `Host`

The package enforces these session-level invariants:

- a valid `Session` always has exactly one active `Host`
- a valid `Session` has at most one active `Turn`
- when a `Client` starts a new `Turn`, that client becomes the session input
  client for the active turn

Invalid transitions fail with `SessionFailure` so callers and tests can assert
on invariant violations directly.

## Temporary compatibility export

The package entrypoint also still exports `CommonCodeDomainDescriptor` and
`commonCodeDomainDescriptor` as a **temporary compatibility shim** for the
existing scaffold consumer.

That placeholder descriptor is transitional only. It is retained narrowly so the
current scaffold app can continue to analyze and test while the real shared
domain model introduced in issue #2 becomes the intended package contract.

## Usage

```dart
import 'package:common_code_domain/common_code_domain.dart';

void main() {
  const host = Host(id: 'host-1');
  const client = Client(id: 'client-1');

  final session = Session(
    id: 'session-1',
    activeHost: host,
    clients: const [client],
  );

  final updatedSession = session.startTurn(turnId: 'turn-1', client: client);

  print(updatedSession.inputClient); // Client(id: client-1)
}
```

## Non-goals

This package does not currently model storage, transport, host services, UI,
or execution-loop behavior.
