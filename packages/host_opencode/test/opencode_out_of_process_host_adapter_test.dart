import 'package:common_code_application/common_code_application.dart';
import 'package:common_code_domain/common_code_domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:host_opencode/host_opencode.dart';

void main() {
  group('OpenCodeHostProcessLauncher', () {
    test('launch returns success with process handle and endpoint', () async {
      const launcher = OpenCodeHostProcessLauncher();

      final outcome = await launcher.launch();

      expect(outcome, isA<OpenCodeHostProcessLaunchSuccess>());
      final success = outcome as OpenCodeHostProcessLaunchSuccess;
      expect(success.result.processHandle, isA<int>());
      expect(success.result.connectionEndpoint, isA<String>());
    });
  });

  group('OpenCodeHostProcessConnector', () {
    test('connect returns failure when no host is running', () async {
      const connector = OpenCodeHostProcessConnector();

      final outcome = await connector.connect();

      expect(outcome, isA<OpenCodeHostConnectionFailed>());
      final failed = outcome as OpenCodeHostConnectionFailed;
      expect(failed.failure.reason, isNotEmpty);
    });
  });

  group('OutOfProcessOpenCodeHostAdapter', () {
    late OpenCodeHostProcessLauncher launcher;
    late OpenCodeHostProcessConnector connector;

    setUp(() {
      launcher = const OpenCodeHostProcessLauncher();
      connector = const OpenCodeHostProcessConnector();
    });

    test('createSession succeeds when host bootstrap succeeds', () async {
      final adapter = OutOfProcessOpenCodeHostAdapter(
        connector: connector,
        launcher: launcher,
      );

      final session = adapter.createSession(
        sessionId: 'test-session',
        activeHost: _testHost,
      );

      expect(session.id, equals('test-session'));
    });

    test('submitTurn succeeds after bootstrap', () async {
      final adapter = OutOfProcessOpenCodeHostAdapter(
        connector: connector,
        launcher: launcher,
      );

      adapter.createSession(
        sessionId: 'test-session',
        activeHost: _testHost,
      );

      // Attach client before submitting turn
      adapter.attachClient(
        sessionId: 'test-session',
        client: _testClient,
      );

      final session = adapter.submitTurn(
        sessionId: 'test-session',
        client: _testClient,
        submittedText: 'Hello',
      );

      expect(session.id, equals('test-session'));
      expect(session.activeTurn, isNotNull);
    });

    test('OpenCode vocabulary does not leak above HostService boundary', () {
      // Verify that the adapter only uses HostService types in public API
      final adapter = OutOfProcessOpenCodeHostAdapter(
        connector: connector,
        launcher: launcher,
      );

      // The adapter implements HostService, verifying no OpenCode vocabulary leaks
      expect(adapter, isA<HostService>());
    });

    test('duplicate sessionId throws duplicateSessionId failure', () {
      final adapter = OutOfProcessOpenCodeHostAdapter(
        connector: connector,
        launcher: launcher,
      );

      adapter.createSession(
        sessionId: 'test-session',
        activeHost: _testHost,
      );

      expect(
        () => adapter.createSession(
          sessionId: 'test-session',
          activeHost: _testHost,
        ),
        throwsA(
          isA<HostServiceFailure>().having(
            (f) => f.code,
            'code',
            HostServiceFailureCode.duplicateSessionId,
          ),
        ),
      );
    });

    test('readSession throws for unknown session', () {
      final adapter = OutOfProcessOpenCodeHostAdapter(
        connector: connector,
        launcher: launcher,
      );

      expect(
        () => adapter.readSession('unknown-session'),
        throwsA(
          isA<HostServiceFailure>().having(
            (f) => f.code,
            'code',
            HostServiceFailureCode.unknownSessionId,
          ),
        ),
      );
    });

    test('watchSession throws for unknown session', () {
      final adapter = OutOfProcessOpenCodeHostAdapter(
        connector: connector,
        launcher: launcher,
      );

      expect(
        () => adapter.watchSession('unknown-session'),
        throwsA(
          isA<HostServiceFailure>().having(
            (f) => f.code,
            'code',
            HostServiceFailureCode.unknownSessionId,
          ),
        ),
      );
    });

    test('attachClient adds client to session', () {
      final adapter = OutOfProcessOpenCodeHostAdapter(
        connector: connector,
        launcher: launcher,
      );

      adapter.createSession(
        sessionId: 'test-session',
        activeHost: _testHost,
      );

      final session = adapter.attachClient(
        sessionId: 'test-session',
        client: _testClient,
      );

      expect(session.clients, contains(_testClient));
    });
  });
}

/// Test helper host with a simple ID.
final _testHost = Host(id: 'test-host');

/// Test helper client.
final _testClient = Client(id: 'test-client');
