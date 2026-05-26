import 'dart:convert';

import 'package:common_code_application/common_code_application.dart';
import 'package:common_code_desktop/src/durable_local_host_service.dart';
import 'package:common_code_desktop/src/desktop_session_runtime.dart';
import 'package:common_code_domain/common_code_domain.dart';
import 'package:common_code_persistence/common_code_persistence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DurableLocalHostService', () {
    test('missing durable state seeds from legacy when eligible', () async {
      final diagnostics = <DurableLocalHostDiagnosticCode>[];
      final service = DurableLocalHostService(
        durableStorage: _MemoryDurableStorage(),
        legacySnapshotStore: _MemoryLegacySnapshotStore(
          storedSession: _completedSession(),
        ),
        diagnosticsSink: (diagnostic) => diagnostics.add(diagnostic.code),
      );

      final session = await _bootstrapService(service);

      expectSessionLike(session, _completedSession());
      expect(
        diagnostics,
        containsAllInOrder(<DurableLocalHostDiagnosticCode>[
          DurableLocalHostDiagnosticCode.durableReadMissing,
          DurableLocalHostDiagnosticCode.legacySeedActivated,
          DurableLocalHostDiagnosticCode.legacySeedSucceeded,
        ]),
      );
      expect(
        diagnostics,
        isNot(contains(DurableLocalHostDiagnosticCode.freshBootstrapActivated)),
      );
    });

    test('already bootstrapped re-entry returns current session', () async {
      final service = DurableLocalHostService(
        durableStorage: _MemoryDurableStorage(),
        legacySnapshotStore: _MemoryLegacySnapshotStore(
          storedSession: _completedSession(),
        ),
      );

      final seededSession = await _bootstrapService(service);

      final nextSession = await CommonCodeSessionBootstrapLifecycle.of(service)
          .bootstrap(
            request: const CommonCodeSessionBootstrapRequest(
              defaultSessionId: 'other-session',
              hostId: 'other-host',
              attachedClientId: 'other-client',
            ),
            port: service,
          );

      expect(nextSession.id, seededSession.id);
      expectSessionLike(nextSession, seededSession);
    });

    test(
      'missing durable state falls back fresh when legacy seeding is ineligible',
      () async {
        final diagnostics = <DurableLocalHostDiagnosticCode>[];
        final service = DurableLocalHostService(
          durableStorage: _MemoryDurableStorage(legacySeedEnabled: false),
          legacySnapshotStore: _MemoryLegacySnapshotStore(
            storedSession: _completedSession(),
          ),
          diagnosticsSink: (diagnostic) => diagnostics.add(diagnostic.code),
        );

        final session = await _bootstrapService(service);

        expect(session.id, desktopSessionRuntimeDefaultSessionId);
        expect(
          session.clients.single.id,
          desktopSessionRuntimeAttachedClientId,
        );
        expect(
          diagnostics,
          containsAllInOrder(<DurableLocalHostDiagnosticCode>[
            DurableLocalHostDiagnosticCode.durableReadMissing,
            DurableLocalHostDiagnosticCode.legacySeedSkipped,
            DurableLocalHostDiagnosticCode.freshBootstrapActivated,
          ]),
        );
        expect(
          diagnostics,
          isNot(contains(DurableLocalHostDiagnosticCode.legacySeedActivated)),
        );
      },
    );

    test(
      'missing durable state falls back fresh when no valid legacy snapshot exists',
      () async {
        final diagnostics = <DurableLocalHostDiagnosticCode>[];
        final service = DurableLocalHostService(
          durableStorage: _MemoryDurableStorage(),
          legacySnapshotStore: _MemoryLegacySnapshotStore(),
          diagnosticsSink: (diagnostic) => diagnostics.add(diagnostic.code),
        );

        final session = await _bootstrapService(service);

        expect(session.id, desktopSessionRuntimeDefaultSessionId);
        expect(
          diagnostics,
          containsAllInOrder(<DurableLocalHostDiagnosticCode>[
            DurableLocalHostDiagnosticCode.durableReadMissing,
            DurableLocalHostDiagnosticCode.legacySeedActivated,
            DurableLocalHostDiagnosticCode.legacySeedFailed,
            DurableLocalHostDiagnosticCode.freshBootstrapActivated,
          ]),
        );
      },
    );

    test(
      'full restart restores prior session state from durable storage',
      () async {
        final storage = _MemoryDurableStorage(
          payload: jsonEncode(
            const SessionSnapshotCodec().encode(
              _runningSessionWithNotifications(),
            ),
          ),
          legacySeedEnabled: false,
        );
        final service = DurableLocalHostService(
          durableStorage: storage,
          legacySnapshotStore: _MemoryLegacySnapshotStore(),
        );

        final session = await _bootstrapService(service);

        expectSessionLike(session, _runningSessionWithNotifications());
        expectSessionLike(
          service.readSession(session.id),
          _runningSessionWithNotifications(),
        );
      },
    );

    test('corrupt durable payload seeds from legacy when eligible', () async {
      final diagnostics = <DurableLocalHostDiagnosticCode>[];
      final service = DurableLocalHostService(
        durableStorage: _MemoryDurableStorage(payload: '{bad-json'),
        legacySnapshotStore: _MemoryLegacySnapshotStore(
          storedSession: _completedSession(),
        ),
        diagnosticsSink: (diagnostic) => diagnostics.add(diagnostic.code),
      );

      final session = await _bootstrapService(service);

      expectSessionLike(session, _completedSession());
      expect(
        diagnostics,
        containsAllInOrder(<DurableLocalHostDiagnosticCode>[
          DurableLocalHostDiagnosticCode.durableReadCorruptOrInvalid,
          DurableLocalHostDiagnosticCode.legacySeedActivated,
          DurableLocalHostDiagnosticCode.legacySeedSucceeded,
        ]),
      );
    });

    test(
      'corrupt durable payload falls back fresh when no valid legacy snapshot exists',
      () async {
        final diagnostics = <DurableLocalHostDiagnosticCode>[];
        final service = DurableLocalHostService(
          durableStorage: _MemoryDurableStorage(payload: '{bad-json'),
          legacySnapshotStore: _MemoryLegacySnapshotStore(),
          diagnosticsSink: (diagnostic) => diagnostics.add(diagnostic.code),
        );

        final session = await _bootstrapService(service);

        expect(session.id, desktopSessionRuntimeDefaultSessionId);
        expect(
          diagnostics,
          containsAllInOrder(<DurableLocalHostDiagnosticCode>[
            DurableLocalHostDiagnosticCode.durableReadCorruptOrInvalid,
            DurableLocalHostDiagnosticCode.legacySeedActivated,
            DurableLocalHostDiagnosticCode.legacySeedFailed,
            DurableLocalHostDiagnosticCode.freshBootstrapActivated,
          ]),
        );
      },
    );

    test(
      'corrupt durable payload falls back fresh when legacy seeding is ineligible',
      () async {
        final diagnostics = <DurableLocalHostDiagnosticCode>[];
        final service = DurableLocalHostService(
          durableStorage: _MemoryDurableStorage(
            payload: '{bad-json',
            legacySeedEnabled: false,
          ),
          legacySnapshotStore: _MemoryLegacySnapshotStore(
            storedSession: _completedSession(),
          ),
          diagnosticsSink: (diagnostic) => diagnostics.add(diagnostic.code),
        );

        final session = await _bootstrapService(service);

        expect(session.id, desktopSessionRuntimeDefaultSessionId);
        expect(
          diagnostics,
          containsAllInOrder(<DurableLocalHostDiagnosticCode>[
            DurableLocalHostDiagnosticCode.durableReadCorruptOrInvalid,
            DurableLocalHostDiagnosticCode.legacySeedSkipped,
            DurableLocalHostDiagnosticCode.freshBootstrapActivated,
          ]),
        );
        expect(
          diagnostics,
          isNot(contains(DurableLocalHostDiagnosticCode.legacySeedActivated)),
        );
      },
    );

    test(
      'legacy seeding branch failures stay classified as legacy seed failures',
      () async {
        final diagnostics = <DurableLocalHostDiagnosticCode>[];
        final service = DurableLocalHostService(
          durableStorage: _MemoryDurableStorage(
            eligibilityError: StateError('eligibility boom'),
          ),
          legacySnapshotStore: _MemoryLegacySnapshotStore(
            storedSession: _completedSession(),
          ),
          diagnosticsSink: (diagnostic) => diagnostics.add(diagnostic.code),
        );

        final session = await _bootstrapService(service);

        expect(session.id, desktopSessionRuntimeDefaultSessionId);
        expect(
          diagnostics,
          contains(DurableLocalHostDiagnosticCode.durableReadMissing),
        );
        expect(
          diagnostics,
          contains(DurableLocalHostDiagnosticCode.legacySeedFailed),
        );
        expect(
          diagnostics,
          contains(DurableLocalHostDiagnosticCode.freshBootstrapActivated),
        );
        expect(
          diagnostics,
          isNot(contains(DurableLocalHostDiagnosticCode.durableReadFailed)),
        );
      },
    );

    test('read failure falls through to legacy seed when eligible', () async {
      final diagnostics = <DurableLocalHostDiagnosticCode>[];
      final service = DurableLocalHostService(
        durableStorage: _MemoryDurableStorage(
          readError: StateError('read boom'),
        ),
        legacySnapshotStore: _MemoryLegacySnapshotStore(
          storedSession: _completedSession(),
        ),
        diagnosticsSink: (diagnostic) => diagnostics.add(diagnostic.code),
      );

      final session = await _bootstrapService(service);

      expectSessionLike(session, _completedSession());
      expect(
        diagnostics,
        containsAllInOrder(<DurableLocalHostDiagnosticCode>[
          DurableLocalHostDiagnosticCode.durableReadFailed,
          DurableLocalHostDiagnosticCode.legacySeedActivated,
          DurableLocalHostDiagnosticCode.legacySeedSucceeded,
        ]),
      );
    });

    test(
      'bootstrap persist failure after legacy restore falls back fresh',
      () async {
        final diagnostics = <DurableLocalHostDiagnosticCode>[];
        final storage = _MemoryDurableStorage(
          writeError: StateError('write boom'),
        );
        final service = DurableLocalHostService(
          durableStorage: storage,
          legacySnapshotStore: _MemoryLegacySnapshotStore(
            storedSession: _completedSession(),
          ),
          diagnosticsSink: (diagnostic) => diagnostics.add(diagnostic.code),
        );

        final session = await _bootstrapService(service);

        expect(session.id, desktopSessionRuntimeDefaultSessionId);
        expect(
          session.clients.single.id,
          desktopSessionRuntimeAttachedClientId,
        );
        expect(
          diagnostics,
          containsAllInOrder(<DurableLocalHostDiagnosticCode>[
            DurableLocalHostDiagnosticCode.durableReadMissing,
            DurableLocalHostDiagnosticCode.legacySeedActivated,
            DurableLocalHostDiagnosticCode.legacySeedFailed,
            DurableLocalHostDiagnosticCode.freshBootstrapActivated,
          ]),
        );
        expect(
          diagnostics,
          isNot(contains(DurableLocalHostDiagnosticCode.legacySeedSucceeded)),
        );
      },
    );

    test('durable restore failure activates fresh bootstrap only', () async {
      final diagnostics = <DurableLocalHostDiagnosticCode>[];
      final service = _RejectingRestoreDurableLocalHostService(
        durableStorage: _MemoryDurableStorage(
          payload: jsonEncode(
            const SessionSnapshotCodec().encode(_queuedSession()),
          ),
        ),
        legacySnapshotStore: _MemoryLegacySnapshotStore(
          storedSession: _completedSession(),
        ),
        diagnosticsSink: (diagnostic) => diagnostics.add(diagnostic.code),
      );

      final session = await _bootstrapService(service);

      expect(session.id, desktopSessionRuntimeDefaultSessionId);
      expect(
        diagnostics,
        contains(DurableLocalHostDiagnosticCode.durableRestoreFailed),
      );
      expect(
        diagnostics,
        contains(DurableLocalHostDiagnosticCode.freshBootstrapActivated),
      );
      expect(
        diagnostics,
        isNot(contains(DurableLocalHostDiagnosticCode.legacySeedActivated)),
      );
    });

    test('durable write failure is observable and non-fatal', () async {
      final diagnostics = <DurableLocalHostDiagnosticCode>[];
      final storage = _MemoryDurableStorage();
      final service = DurableLocalHostService(
        durableStorage: storage,
        legacySnapshotStore: _MemoryLegacySnapshotStore(),
        diagnosticsSink: (diagnostic) => diagnostics.add(diagnostic.code),
      );

      final session = await _bootstrapService(service);
      storage.writeError = StateError('write boom');

      final updated = service.submitTurn(
        sessionId: session.id,
        client: const Client(id: desktopSessionRuntimeAttachedClientId),
        submittedText: 'hello',
      );
      await service.flushPendingWrites();

      expect(updated.activeTurn?.submittedText, 'hello');
      expect(
        service.readSession(session.id).activeTurn?.submittedText,
        'hello',
      );
      expect(
        diagnostics,
        contains(DurableLocalHostDiagnosticCode.durableWriteFailed),
      );
    });

    test(
      'restored queued and running turns remain frozen after restart',
      () async {
        final queuedService = DurableLocalHostService(
          durableStorage: _MemoryDurableStorage(
            payload: jsonEncode(
              const SessionSnapshotCodec().encode(_queuedSession()),
            ),
          ),
          legacySnapshotStore: _MemoryLegacySnapshotStore(),
        );
        final queuedSession = await _bootstrapService(queuedService);
        await Future<void>.delayed(Duration.zero);
        expect(queuedSession.activeTurn?.status, TurnStatus.queued);
        expect(
          queuedService.readSession(queuedSession.id).activeTurn?.status,
          TurnStatus.queued,
        );

        final runningService = DurableLocalHostService(
          durableStorage: _MemoryDurableStorage(
            payload: jsonEncode(
              const SessionSnapshotCodec().encode(
                _runningSessionWithNotifications(),
              ),
            ),
          ),
          legacySnapshotStore: _MemoryLegacySnapshotStore(),
        );
        final runningSession = await _bootstrapService(runningService);
        await Future<void>.delayed(Duration.zero);
        expect(runningSession.activeTurn?.status, TurnStatus.running);
        expect(
          runningService.readSession(runningSession.id).activeTurn?.status,
          TurnStatus.running,
        );
      },
    );

    test('notification state round-trips without synthesis', () async {
      final notifiedService = DurableLocalHostService(
        durableStorage: _MemoryDurableStorage(
          payload: jsonEncode(
            const SessionSnapshotCodec().encode(
              _runningSessionWithNotifications(),
            ),
          ),
        ),
        legacySnapshotStore: _MemoryLegacySnapshotStore(),
      );

      final notifiedSession = await _bootstrapService(notifiedService);

      expect(
        notifiedSession.notifications,
        _runningSessionWithNotifications().notifications,
      );

      final turnOnlyPayload = jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'sessionId': 'restored-session',
        'activeHostId': 'restored-host',
        'clientIds': <String>[
          desktopSessionRuntimeAttachedClientId,
          'reviewer-client',
        ],
        'turns': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'turn-1',
            'clientId': 'reviewer-client',
            'submittedText': 'Completed turn',
            'status': 'completed',
            'failureSummary': null,
          },
        ],
      });
      final turnOnlyService = DurableLocalHostService(
        durableStorage: _MemoryDurableStorage(payload: turnOnlyPayload),
        legacySnapshotStore: _MemoryLegacySnapshotStore(),
      );

      final turnOnlySession = await _bootstrapService(turnOnlyService);

      expect(turnOnlySession.notifications, isEmpty);
    });

    test(
      'live acknowledgement updates durable session notification state',
      () async {
        final service = DurableLocalHostService(
          durableStorage: _MemoryDurableStorage(
            payload: jsonEncode(
              const SessionSnapshotCodec().encode(
                _runningSessionWithNotifications(),
              ),
            ),
          ),
          legacySnapshotStore: _MemoryLegacySnapshotStore(),
        );

        final session = await _bootstrapService(service);
        final notificationId = session.notifications
            .firstWhere((notification) => !notification.isAcknowledged)
            .id;

        final acknowledgedSession = service.acknowledgeNotification(
          sessionId: session.id,
          notificationId: notificationId,
        );
        await service.flushPendingWrites();

        expect(
          acknowledgedSession.notifications
              .firstWhere((notification) => notification.id == notificationId)
              .isAcknowledged,
          isTrue,
        );
        expect(
          service
              .readSession(session.id)
              .notifications
              .firstWhere((notification) => notification.id == notificationId)
              .isAcknowledged,
          isTrue,
        );
      },
    );

    test(
      'first successful durable write disables later legacy seeding',
      () async {
        final storage = _MemoryDurableStorage();
        final legacyStore = _MemoryLegacySnapshotStore(
          storedSession: _completedSession(),
        );
        final service = DurableLocalHostService(
          durableStorage: storage,
          legacySnapshotStore: legacyStore,
        );

        final seededSession = await _bootstrapService(service);

        expectSessionLike(seededSession, _completedSession());
        expect(storage.legacySeedEnabled, isFalse);

        storage.payload = null;
        legacyStore.storedSession = _runningSessionWithNotifications();

        final nextDiagnostics = <DurableLocalHostDiagnosticCode>[];
        final nextService = DurableLocalHostService(
          durableStorage: storage,
          legacySnapshotStore: legacyStore,
          diagnosticsSink: (diagnostic) => nextDiagnostics.add(diagnostic.code),
        );

        final freshSession = await _bootstrapService(nextService);

        expect(freshSession.id, desktopSessionRuntimeDefaultSessionId);
        expect(
          nextDiagnostics,
          contains(DurableLocalHostDiagnosticCode.legacySeedSkipped),
        );
        expect(
          nextDiagnostics,
          contains(DurableLocalHostDiagnosticCode.freshBootstrapActivated),
        );
      },
    );
  });
}

Future<Session> _bootstrapService(DurableLocalHostService service) {
  return CommonCodeSessionBootstrapLifecycle.of(service).bootstrap(
    request: const CommonCodeSessionBootstrapRequest(
      defaultSessionId: desktopSessionRuntimeDefaultSessionId,
      hostId: desktopSessionRuntimeHostId,
      attachedClientId: desktopSessionRuntimeAttachedClientId,
    ),
    port: service,
  );
}

void expectSessionLike(Session actual, Session expected) {
  expect(actual.id, expected.id);
  expect(actual.activeHost.id, expected.activeHost.id);
  expect(
    actual.clients.map((client) => client.id).toList(growable: false),
    expected.clients.map((client) => client.id).toList(growable: false),
  );
  expect(
    actual.promptThread.turns.map(_turnSignature).toList(growable: false),
    expected.promptThread.turns.map(_turnSignature).toList(growable: false),
  );
  expect(
    actual.notifications.map(_notificationSignature).toList(growable: false),
    expected.notifications.map(_notificationSignature).toList(growable: false),
  );
}

Map<String, Object?> _turnSignature(Turn turn) {
  return <String, Object?>{
    'id': turn.id,
    'clientId': turn.clientId,
    'submittedText': turn.submittedText,
    'status': turn.status,
    'failureSummary': turn.failureSummary,
  };
}

Map<String, Object?> _notificationSignature(SessionNotification notification) {
  return <String, Object?>{
    'id': notification.id,
    'turnId': notification.turnId,
    'transition': notification.transition,
    'isAcknowledged': notification.isAcknowledged,
  };
}

Session _baseSession() {
  return Session(
    id: 'restored-session',
    activeHost: const Host(id: 'restored-host'),
    clients: const <Client>[
      Client(id: desktopSessionRuntimeAttachedClientId),
      Client(id: 'reviewer-client'),
    ],
  );
}

Session _queuedSession() {
  return _baseSession().startTurn(
    turnId: 'turn-1',
    client: const Client(id: 'reviewer-client'),
    submittedText: 'Queued turn',
  );
}

Session _completedSession() {
  return _baseSession()
      .startTurn(
        turnId: 'turn-1',
        client: const Client(id: 'reviewer-client'),
        submittedText: 'Completed turn',
      )
      .advanceActiveTurnToRunning()
      .completeActiveTurn();
}

Session _runningSessionWithNotifications() {
  final session = _baseSession()
      .startTurn(
        turnId: 'turn-1',
        client: const Client(id: 'reviewer-client'),
        submittedText: 'First turn',
      )
      .advanceActiveTurnToRunning()
      .completeActiveTurn()
      .startTurn(
        turnId: 'turn-2',
        client: const Client(id: 'reviewer-client'),
        submittedText: 'Second turn',
      )
      .advanceActiveTurnToRunning();

  return Session(
    id: session.id,
    activeHost: session.activeHost,
    clients: session.clients,
    promptThread: session.promptThread,
    notifications: <SessionNotification>[
      SessionNotification.forTransition(
        sessionId: session.id,
        turnId: 'turn-1',
        transition: SessionNotificationTransition.queuedToRunning,
      ),
      SessionNotification.forTransition(
        sessionId: session.id,
        turnId: 'turn-1',
        transition: SessionNotificationTransition.runningToCompleted,
        isAcknowledged: true,
      ),
      SessionNotification.forTransition(
        sessionId: session.id,
        turnId: 'turn-2',
        transition: SessionNotificationTransition.queuedToRunning,
      ),
    ],
  );
}

final class _MemoryLegacySnapshotStore implements SessionSnapshotStore {
  _MemoryLegacySnapshotStore({this.storedSession});

  Session? storedSession;

  @override
  Future<Session?> readLatestSession({required String desktopClientId}) async {
    return storedSession;
  }

  @override
  Future<void> writeLatestSession(Session session) async {}
}

final class _MemoryDurableStorage implements DurableSessionStore {
  _MemoryDurableStorage({
    this.payload,
    this.legacySeedEnabled = true,
    this.readError,
    this.eligibilityError,
    this.writeError,
  });

  String? payload;
  bool legacySeedEnabled;
  Object? readError;
  Object? eligibilityError;
  Object? writeError;

  @override
  Future<void> disableLegacySeed({required String desktopClientId}) async {
    legacySeedEnabled = false;
  }

  @override
  Future<bool> isLegacySeedEnabled({required String desktopClientId}) async {
    final error = eligibilityError;
    if (error != null) {
      throw error;
    }

    return legacySeedEnabled;
  }

  @override
  Future<String?> readSessionPayload() async {
    final error = readError;
    if (error != null) {
      throw error;
    }

    return payload;
  }

  @override
  Future<void> writeSessionPayload(String payload) async {
    final error = writeError;
    if (error != null) {
      throw error;
    }

    this.payload = payload;
  }
}

final class _RejectingRestoreDurableLocalHostService
    extends DurableLocalHostService {
  _RejectingRestoreDurableLocalHostService({
    required super.legacySnapshotStore,
    required super.durableStorage,
    super.diagnosticsSink,
  });

  @override
  Session restoreDurableSession(Session session) {
    throw StateError('restore rejected');
  }
}
