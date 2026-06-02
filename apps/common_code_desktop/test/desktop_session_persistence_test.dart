import 'dart:async';
import 'dart:convert';

import 'package:common_code_application/common_code_application.dart';
import 'package:common_code_desktop/src/desktop_session_runtime.dart';
import 'package:common_code_domain/common_code_domain.dart';
import 'package:common_code_observability/common_code_observability.dart';
import 'package:common_code_persistence/common_code_persistence.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:host_in_memory/host_in_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SessionSnapshotCodec', () {
    const codec = SessionSnapshotCodec();

    test('round-trips schema 2 notifications without synthesis', () {
      final encoded = codec.encode(_runningSessionWithNotifications());
      final decoded = codec.decode(
        encoded,
        desktopClientId: desktopSessionRuntimeAttachedClientId,
      );

      expectSessionLike(decoded, _runningSessionWithNotifications());
      expect(encoded['schemaVersion'], 2);
    });

    test('schema 1 restore yields empty notifications', () {
      final decoded = codec.decode(<String, Object?>{
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
      }, desktopClientId: desktopSessionRuntimeAttachedClientId);

      expect(decoded.notifications, isEmpty);
    });
  });

  group('SharedPreferencesDurableSessionStore', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('writes and reads durable payload and marker', () async {
      final storage = SharedPreferencesDurableSessionStore();

      await storage.writeSessionPayload('payload');
      expect(await storage.readSessionPayload(), 'payload');
      expect(
        await storage.isLegacySeedEnabled(
          desktopClientId: desktopSessionRuntimeAttachedClientId,
        ),
        isTrue,
      );

      await storage.disableLegacySeed(
        desktopClientId: desktopSessionRuntimeAttachedClientId,
      );
      expect(
        await storage.isLegacySeedEnabled(
          desktopClientId: desktopSessionRuntimeAttachedClientId,
        ),
        isFalse,
      );
    });
  });

  group('desktop durable continuity compatibility', () {
    test('eligible legacy snapshot seeds durable state once', () async {
      final storage = _MemoryDurableStorage();
      final legacyStore = _MemoryLegacySnapshotStore(
        storedSession: _completedSessionWithNotifications(),
      );
      final runtime = _createDurableRuntime(
        durableStorage: storage,
        snapshotStore: legacyStore,
      );
      Session? snapshot;
      runtime.bind(
        onSnapshot: (session) => snapshot = session,
        onWatchError: (error, stackTrace) {},
      );

      await runtime.initialize();
      await _lastCreatedSessionStore!.waitForPendingPersistence();

      expectSessionLike(snapshot!, _completedSessionWithNotifications());
      expect(storage.payload, isNotNull);
      expect(storage.legacySeedEnabled, isFalse);
    });

    test('missing ineligible branch boots fresh instead of seeding', () async {
      final diagnostics = <DurableLocalHostDiagnosticCode>[];
      final storage = _MemoryDurableStorage(legacySeedEnabled: false);
      final runtime = _createDurableRuntime(
        durableStorage: storage,
        snapshotStore: _MemoryLegacySnapshotStore(
          storedSession: _completedSessionWithNotifications(),
        ),
        diagnosticsPort: DurableLocalHostDiagnosticsEmitter(
          (diagnostic) => diagnostics.add(diagnostic.code),
        ),
      );
      Session? snapshot;
      runtime.bind(
        onSnapshot: (session) => snapshot = session,
        onWatchError: (error, stackTrace) {},
      );

      await runtime.initialize();

      expect(snapshot, isNotNull);
      expect(snapshot!.id, desktopSessionRuntimeDefaultSessionId);
      expect(
        diagnostics,
        containsAllInOrder(<DurableLocalHostDiagnosticCode>[
          DurableLocalHostDiagnosticCode.durableReadMissing,
          DurableLocalHostDiagnosticCode.legacySeedSkipped,
          DurableLocalHostDiagnosticCode.freshBootstrapActivated,
        ]),
      );
    });

    test('corrupt ineligible branch boots fresh instead of seeding', () async {
      final diagnostics = <DurableLocalHostDiagnosticCode>[];
      final runtime = _createDurableRuntime(
        durableStorage: _MemoryDurableStorage(
          payload: '{bad-json',
          legacySeedEnabled: false,
        ),
        snapshotStore: _MemoryLegacySnapshotStore(
          storedSession: _completedSessionWithNotifications(),
        ),
        diagnosticsPort: DurableLocalHostDiagnosticsEmitter(
          (diagnostic) => diagnostics.add(diagnostic.code),
        ),
      );
      Session? snapshot;
      runtime.bind(
        onSnapshot: (session) => snapshot = session,
        onWatchError: (error, stackTrace) {},
      );

      await runtime.initialize();

      expect(snapshot, isNotNull);
      expect(snapshot!.id, desktopSessionRuntimeDefaultSessionId);
      expect(
        diagnostics,
        containsAllInOrder(<DurableLocalHostDiagnosticCode>[
          DurableLocalHostDiagnosticCode.durableReadCorruptOrInvalid,
          DurableLocalHostDiagnosticCode.legacySeedSkipped,
          DurableLocalHostDiagnosticCode.freshBootstrapActivated,
        ]),
      );
    });

    test(
      'after first successful durable write bootstrap ignores legacy shadow data',
      () async {
        final storage = _MemoryDurableStorage(
          payload: jsonEncode(
            const SessionSnapshotCodec().encode(
              _runningSessionWithNotifications(),
            ),
          ),
          legacySeedEnabled: false,
        );
        final runtime = _createDurableRuntime(
          durableStorage: storage,
          snapshotStore: _MemoryLegacySnapshotStore(
            storedSession: _completedSessionWithNotifications(),
          ),
        );
        Session? snapshot;
        runtime.bind(
          onSnapshot: (session) => snapshot = session,
          onWatchError: (error, stackTrace) {},
        );

        await runtime.initialize();

        expectSessionLike(snapshot!, _runningSessionWithNotifications());
      },
    );

    test(
      'acknowledged notifications stay non-replayable after restart while unacknowledged remain replayable',
      () async {
        final runtime = _createDurableRuntime(
          durableStorage: _MemoryDurableStorage(
            payload: jsonEncode(
              const SessionSnapshotCodec().encode(
                _runningSessionWithNotifications(),
              ),
            ),
          ),
          snapshotStore: _MemoryLegacySnapshotStore(),
        );
        Session? snapshot;
        runtime.bind(
          onSnapshot: (session) => snapshot = session,
          onWatchError: (error, stackTrace) {},
        );

        await runtime.initialize();

        final replayableNotifications = snapshot!.notifications
            .where((notification) => !notification.isAcknowledged)
            .toList(growable: false);
        final acknowledgedNotifications = snapshot!.notifications
            .where((notification) => notification.isAcknowledged)
            .toList(growable: false);

        expect(replayableNotifications, hasLength(2));
        expect(acknowledgedNotifications, hasLength(1));
      },
    );

    test('live acknowledgement persists across full restart', () async {
      final storage = _MemoryDurableStorage(
        payload: jsonEncode(
          const DesktopSessionSnapshotJsonCodec().encode(
            _runningSessionWithNotifications(),
          ),
        ),
      );
      final firstRuntime = _createDurableRuntime(
        durableStorage: storage,
        snapshotStore: _MemoryLegacySnapshotStore(),
      );
      final firstHostService = _lastCreatedHostService!;
      Session? firstSnapshot;
      firstRuntime.bind(
        onSnapshot: (session) => firstSnapshot = session,
        onWatchError: (error, stackTrace) {},
      );

      await firstRuntime.initialize();
      final acknowledgedNotificationId = firstSnapshot!.notifications
          .firstWhere((notification) => !notification.isAcknowledged)
          .id;

      final acknowledgedSession = firstHostService.acknowledgeNotification(
        sessionId: firstSnapshot!.id,
        notificationId: acknowledgedNotificationId,
      );
      _createPersistSessionMutation(
        _lastCreatedSessionStore!,
        attachedClientId: desktopSessionRuntimeAttachedClientId,
      )(acknowledgedSession);
      await _lastCreatedSessionStore!.waitForPendingPersistence();

      final restartedRuntime = _createDurableRuntime(
        durableStorage: storage,
        snapshotStore: _MemoryLegacySnapshotStore(),
      );
      Session? restartedSnapshot;
      restartedRuntime.bind(
        onSnapshot: (session) => restartedSnapshot = session,
        onWatchError: (error, stackTrace) {},
      );

      await restartedRuntime.initialize();

      expect(
        restartedSnapshot!.notifications
            .firstWhere(
              (notification) => notification.id == acknowledgedNotificationId,
            )
            .isAcknowledged,
        isTrue,
      );
      expect(
        restartedSnapshot!.notifications.where(
          (notification) => !notification.isAcknowledged,
        ),
        isNotEmpty,
      );
    });

    test(
      'host-driven streamed unacknowledged notifications replay after restart',
      () async {
        // AC1: Exercise full restart after host-driven streamed transitions emit
        // notification-bearing Session updates that have not yet been acknowledged.
        final durableStorage = _MemoryDurableStorage();
        final firstHostAdapter = _MultiEmittingInMemoryHostAdapter();
        final sessionStore = DurableLocalSessionStore.fromPersistenceComponents(
          legacySnapshotStore: _MemoryLegacySnapshotStore(),
          durableStorage: durableStorage,
        );
        final firstBootstrapPort = CommonCodeSessionBootstrapPortAdapter(
          sessionStore: sessionStore,
          host: CommonCodeSessionBootstrapHost(
            restoreSession: firstHostAdapter.restoreSession,
            createSession: firstHostAdapter.createSession,
            attachClient: firstHostAdapter.attachClient,
          ),
        );
        final firstRuntime = HostDesktopSessionRuntime(
          hostService: _BootstrappedHostService(
            hostService: firstHostAdapter as HostService,
            bootstrapPort: firstBootstrapPort,
          ),
          bootstrapPort: firstBootstrapPort,
          snapshotStore: _MemoryLegacySnapshotStore(),
          persistSessionMutation: _createPersistSessionMutation(
            sessionStore,
            attachedClientId: desktopSessionRuntimeAttachedClientId,
          ),
        );
        Session? firstSnapshot;
        Object? watchError;
        firstRuntime.bind(
          onSnapshot: (session) => firstSnapshot = session,
          onWatchError: (error, stackTrace) => watchError = error,
        );

        await firstRuntime.initialize();
        await sessionStore.waitForPendingPersistence();

        expect(watchError, isNull, reason: 'First runtime watch must succeed');
        expect(
          firstSnapshot,
          isNotNull,
          reason: 'First runtime must receive snapshot',
        );

        // Emit host-driven streamed notifications through the watch path
        // (not through submitTurn), proving watch itself triggers persistence.
        final streamedSnapshot = firstHostAdapter
            .emitStreamedSessionWithNotifications();
        await sessionStore.waitForPendingPersistence();

        // AC2: Prove still-unacknowledged notifications replay after restart
        // from durable state. Record the unacknowledged notification IDs
        // from the streamed snapshot so we can verify they survive restart.
        final unacknowledgedNotificationIds = streamedSnapshot.notifications
            .where((notification) => !notification.isAcknowledged)
            .map((notification) => notification.id)
            .toSet();

        expect(
          unacknowledgedNotificationIds,
          isNotEmpty,
          reason: 'AC2 requires at least one unacknowledged notification',
        );

        // Capture payload to prove persistence occurred
        final payloadAfterStream = durableStorage.payload;
        expect(
          payloadAfterStream,
          isNotNull,
          reason: 'Streamed session must persist notification state',
        );

        // AC4: The assertion below will fail if streamed transitions emitted
        // before restart are missing from restored state.
        // Restart by creating a NEW runtime with fresh adapter over the SAME
        // durable storage; the old adapter's active watch is discarded and
        // the new adapter has no watch conflict.
        final secondHostAdapter = _MultiEmittingInMemoryHostAdapter();
        final secondBootstrapPort = CommonCodeSessionBootstrapPortAdapter(
          sessionStore: sessionStore,
          host: CommonCodeSessionBootstrapHost(
            restoreSession: secondHostAdapter.restoreSession,
            createSession: secondHostAdapter.createSession,
            attachClient: secondHostAdapter.attachClient,
          ),
        );
        final secondRuntime = HostDesktopSessionRuntime(
          hostService: _BootstrappedHostService(
            hostService: secondHostAdapter as HostService,
            bootstrapPort: secondBootstrapPort,
          ),
          bootstrapPort: secondBootstrapPort,
          snapshotStore: _MemoryLegacySnapshotStore(),
          persistSessionMutation: _createPersistSessionMutation(
            sessionStore,
            attachedClientId: desktopSessionRuntimeAttachedClientId,
          ),
        );
        Session? restartedSnapshot;
        watchError = null;
        secondRuntime.bind(
          onSnapshot: (session) => restartedSnapshot = session,
          onWatchError: (error, stackTrace) => watchError = error,
        );

        await secondRuntime.initialize();

        expect(
          watchError,
          isNull,
          reason: 'Restart watch must succeed (no active watch conflict)',
        );
        expect(
          restartedSnapshot,
          isNotNull,
          reason: 'Restart must receive snapshot from persistence',
        );

        // AC2: Unacknowledged notifications from the streamed session MUST
        // be present in the restarted runtime's snapshot - they replay.
        final localSnapshot = restartedSnapshot!;
        for (final notificationId in unacknowledgedNotificationIds) {
          final found = localSnapshot.notifications.any(
            (notification) =>
                notification.id == notificationId &&
                !notification.isAcknowledged,
          );
          expect(
            found,
            isTrue,
            reason:
                'AC2: Unacknowledged notification $notificationId must '
                'replay after restart (was lost if this fails)',
          );
        }
      },
    );

    test(
      'acknowledged streamed notification does not replay after subsequent restart',
      () async {
        // AC3: Prove a notification acknowledged before restart does not
        // replay again after the next restart.
        final durableStorage = _MemoryDurableStorage();
        final firstHostAdapter = _MultiEmittingInMemoryHostAdapter();
        final sessionStore = DurableLocalSessionStore.fromPersistenceComponents(
          legacySnapshotStore: _MemoryLegacySnapshotStore(),
          durableStorage: durableStorage,
        );
        final firstBootstrapPort = CommonCodeSessionBootstrapPortAdapter(
          sessionStore: sessionStore,
          host: CommonCodeSessionBootstrapHost(
            restoreSession: firstHostAdapter.restoreSession,
            createSession: firstHostAdapter.createSession,
            attachClient: firstHostAdapter.attachClient,
          ),
        );
        final firstRuntime = HostDesktopSessionRuntime(
          hostService: _BootstrappedHostService(
            hostService: firstHostAdapter as HostService,
            bootstrapPort: firstBootstrapPort,
          ),
          bootstrapPort: firstBootstrapPort,
          snapshotStore: _MemoryLegacySnapshotStore(),
          persistSessionMutation: _createPersistSessionMutation(
            sessionStore,
            attachedClientId: desktopSessionRuntimeAttachedClientId,
          ),
        );
        Session? firstSnapshot;
        Object? watchError;
        firstRuntime.bind(
          onSnapshot: (session) => firstSnapshot = session,
          onWatchError: (error, stackTrace) => watchError = error,
        );

        await firstRuntime.initialize();
        await sessionStore.waitForPendingPersistence();

        expect(watchError, isNull, reason: 'First runtime watch must succeed');
        expect(
          firstSnapshot,
          isNotNull,
          reason: 'First runtime must receive snapshot',
        );

        // Emit streamed notifications
        final streamedSnapshot = firstHostAdapter
            .emitStreamedSessionWithNotifications();
        await sessionStore.waitForPendingPersistence();

        // Record the notification IDs before acknowledgement
        final unacknowledgedIdsBefore = streamedSnapshot.notifications
            .where((notification) => !notification.isAcknowledged)
            .map((notification) => notification.id)
            .toSet();
        // Acknowledge one unacknowledged notification and persist
        final toAcknowledge = firstSnapshot!.notifications.firstWhere(
          (notification) => !notification.isAcknowledged,
        );
        final stillUnacknowledgedIds = unacknowledgedIdsBefore.difference({
          toAcknowledge.id,
        });
        final acknowledgedSession = firstHostAdapter.acknowledgeNotification(
          sessionId: firstSnapshot!.id,
          notificationId: toAcknowledge.id,
        );
        _createPersistSessionMutation(
          sessionStore,
          attachedClientId: desktopSessionRuntimeAttachedClientId,
        )(acknowledgedSession);
        await sessionStore.waitForPendingPersistence();

        // First restart: acknowledged notification should stay acknowledged,
        // unacknowledged ones should still be present.
        // Restart by creating a NEW runtime with fresh adapter over the SAME
        // durable storage; the old adapter's active watch is discarded.
        final secondHostAdapter = _MultiEmittingInMemoryHostAdapter();
        final secondBootstrapPort = CommonCodeSessionBootstrapPortAdapter(
          sessionStore: sessionStore,
          host: CommonCodeSessionBootstrapHost(
            restoreSession: secondHostAdapter.restoreSession,
            createSession: secondHostAdapter.createSession,
            attachClient: secondHostAdapter.attachClient,
          ),
        );
        final secondRuntime = HostDesktopSessionRuntime(
          hostService: _BootstrappedHostService(
            hostService: secondHostAdapter as HostService,
            bootstrapPort: secondBootstrapPort,
          ),
          bootstrapPort: secondBootstrapPort,
          snapshotStore: _MemoryLegacySnapshotStore(),
          persistSessionMutation: _createPersistSessionMutation(
            sessionStore,
            attachedClientId: desktopSessionRuntimeAttachedClientId,
          ),
        );
        Session? secondSnapshot;
        watchError = null;
        secondRuntime.bind(
          onSnapshot: (session) => secondSnapshot = session,
          onWatchError: (error, stackTrace) => watchError = error,
        );

        await secondRuntime.initialize();

        expect(
          watchError,
          isNull,
          reason: 'First restart watch must succeed (no active watch conflict)',
        );
        expect(
          secondSnapshot,
          isNotNull,
          reason: 'First restart must receive snapshot from persistence',
        );

        // Verify acknowledgement persisted across first restart
        final acknowledgedInSecond = secondSnapshot!.notifications.firstWhere(
          (notification) => notification.id == toAcknowledge.id,
        );
        expect(
          acknowledgedInSecond.isAcknowledged,
          isTrue,
          reason: 'Acknowledgement must persist through restart',
        );

        // Unacknowledged notifications must still be present after restart
        final localSecondSnapshot = secondSnapshot!;
        for (final id in stillUnacknowledgedIds) {
          final found = localSecondSnapshot.notifications.any(
            (notification) =>
                notification.id == id && !notification.isAcknowledged,
          );
          expect(
            found,
            isTrue,
            reason: 'Unacknowledged notification $id must survive restart',
          );
        }

        // Second restart: acknowledged notification must NOT replay as
        // unacknowledged - proving AC3.
        // Restart by creating a NEW runtime with fresh adapter over the SAME
        // durable storage.
        final thirdHostAdapter = _MultiEmittingInMemoryHostAdapter();
        final thirdBootstrapPort = CommonCodeSessionBootstrapPortAdapter(
          sessionStore: sessionStore,
          host: CommonCodeSessionBootstrapHost(
            restoreSession: thirdHostAdapter.restoreSession,
            createSession: thirdHostAdapter.createSession,
            attachClient: thirdHostAdapter.attachClient,
          ),
        );
        final thirdRuntime = HostDesktopSessionRuntime(
          hostService: _BootstrappedHostService(
            hostService: thirdHostAdapter as HostService,
            bootstrapPort: thirdBootstrapPort,
          ),
          bootstrapPort: thirdBootstrapPort,
          snapshotStore: _MemoryLegacySnapshotStore(),
          persistSessionMutation: _createPersistSessionMutation(
            sessionStore,
            attachedClientId: desktopSessionRuntimeAttachedClientId,
          ),
        );
        Session? thirdSnapshot;
        watchError = null;
        thirdRuntime.bind(
          onSnapshot: (session) => thirdSnapshot = session,
          onWatchError: (error, stackTrace) => watchError = error,
        );

        await thirdRuntime.initialize();

        expect(
          watchError,
          isNull,
          reason:
              'Second restart watch must succeed (no active watch conflict)',
        );
        expect(
          thirdSnapshot,
          isNotNull,
          reason: 'Second restart must receive snapshot from persistence',
        );

        // AC3: The notification that was acknowledged before the second restart
        // must STILL be acknowledged after the third restart - it does not replay.
        final acknowledgedInThird = thirdSnapshot!.notifications.firstWhere(
          (notification) => notification.id == toAcknowledge.id,
        );
        expect(
          acknowledgedInThird.isAcknowledged,
          isTrue,
          reason:
              'AC3: Acknowledged notification must not replay as '
              'unacknowledged after subsequent restart',
        );

        // Unacknowledged notifications must still be present
        final localThirdSnapshot = thirdSnapshot!;
        for (final id in stillUnacknowledgedIds) {
          final found = localThirdSnapshot.notifications.any(
            (notification) =>
                notification.id == id && !notification.isAcknowledged,
          );
          expect(
            found,
            isTrue,
            reason: 'Unacknowledged notification $id must survive restart',
          );
        }
      },
    );

    test(
      'streamed transition preserves notification ids and acknowledgement flags verbatim',
      () async {
        final durableStorage = _MemoryDurableStorage();
        final hostAdapter = _MultiEmittingInMemoryHostAdapter();
        final sessionStore = DurableLocalSessionStore.fromPersistenceComponents(
          legacySnapshotStore: _MemoryLegacySnapshotStore(),
          durableStorage: durableStorage,
        );
        final bootstrapPort = CommonCodeSessionBootstrapPortAdapter(
          sessionStore: sessionStore,
          host: CommonCodeSessionBootstrapHost(
            restoreSession: hostAdapter.restoreSession,
            createSession: hostAdapter.createSession,
            attachClient: hostAdapter.attachClient,
          ),
        );
        final runtime = HostDesktopSessionRuntime(
          hostService: hostAdapter as HostService,
          bootstrapPort: bootstrapPort,
          snapshotStore: _MemoryLegacySnapshotStore(),
          persistSessionMutation: _createPersistSessionMutation(
            sessionStore,
            attachedClientId: desktopSessionRuntimeAttachedClientId,
          ),
        );
        Session? snapshot;
        runtime.bind(
          onSnapshot: (session) => snapshot = session,
          onWatchError: (error, stackTrace) {},
        );

        await runtime.initialize();
        await sessionStore.waitForPendingPersistence();

        // Emit a fresh session with known acknowledged+unacknowledged notifications
        // through the watch stream. This is the non-vacuous baseline for AC2.
        final streamedSnapshot = hostAdapter
            .emitStreamedSessionWithNotifications();
        await sessionStore.waitForPendingPersistence();

        // Capture the initial payload after the streamed emission
        final initialPayload = durableStorage.payload;
        expect(initialPayload, isNotNull);

        // Record the initial notifications from the streamed snapshot
        final initialNotificationMap = {
          for (final n in streamedSnapshot.notifications) n.id: n,
        };

        // Trigger a host-driven transition WITHOUT going through submitTurn.
        // This proves the watch path itself triggers persistence, not just
        // the explicit mutation handler.
        hostAdapter.advanceSessionToNextState();
        await sessionStore.waitForPendingPersistence();

        // Read back from durable storage
        final payloadAfter = durableStorage.payload;
        expect(payloadAfter, isNotNull);

        // Prove distinct write from the watch path
        expect(
          payloadAfter,
          isNot(equals(initialPayload)),
          reason: 'Watch path must trigger distinct write beyond initialize()',
        );

        final decoded = const SessionSnapshotCodec().decode(
          jsonDecode(payloadAfter!),
          desktopClientId: desktopSessionRuntimeAttachedClientId,
        );

        // Verify notification ids are preserved verbatim through the watch path
        // including isAcknowledged flags, turnId, and transition.
        for (final original in initialNotificationMap.values) {
          final persisted = decoded.notifications.firstWhere(
            (n) => n.id == original.id,
            orElse: () => throw StateError(
              'Notification ${original.id} not found after persistence',
            ),
          );
          expect(
            persisted.isAcknowledged,
            original.isAcknowledged,
            reason:
                'Notification ${original.id} isAcknowledged must be preserved',
          );
          expect(
            persisted.turnId,
            original.turnId,
            reason: 'Notification ${original.id} turnId must be preserved',
          );
          expect(
            persisted.transition,
            original.transition,
            reason: 'Notification ${original.id} transition must be preserved',
          );
        }
      },
    );
  });
}

CommonCodeSessionStore? _lastCreatedSessionStore;
HostService? _lastCreatedHostService;

HostService _createDurableHostAdapter({
  required Object? durableStorage,
  required SessionSnapshotStore snapshotStore,
  DurableLocalHostDiagnosticsPort? diagnosticsPort,
}) {
  final hostAdapter = InMemoryHostAdapter();
  final hostService = hostAdapter as HostService;
  final sessionStore = DurableLocalSessionStore.fromPersistenceComponents(
    legacySnapshotStore: snapshotStore,
    durableStorage: durableStorage,
  );
  _lastCreatedSessionStore = sessionStore;
  final bootstrapPort = CommonCodeSessionBootstrapPortAdapter(
    sessionStore: sessionStore,
    host: CommonCodeSessionBootstrapHost(
      restoreSession: hostAdapter.restoreSession,
      createSession: hostAdapter.createSession,
      attachClient: hostAdapter.attachClient,
    ),
    diagnosticsPort: diagnosticsPort,
  );
  _lastCreatedHostService = hostService;
  return _BootstrappedHostService(
    hostService: hostService,
    bootstrapPort: bootstrapPort,
  );
}

HostDesktopSessionRuntime _createDurableRuntime({
  required Object? durableStorage,
  required SessionSnapshotStore snapshotStore,
  DurableLocalHostDiagnosticsPort? diagnosticsPort,
}) {
  final hostService = _createDurableHostAdapter(
    durableStorage: durableStorage,
    snapshotStore: snapshotStore,
    diagnosticsPort: diagnosticsPort,
  );
  return HostDesktopSessionRuntime(
    hostService: hostService,
    bootstrapPort: (hostService as _BootstrappedHostService).bootstrapPort,
    snapshotStore: snapshotStore,
    persistSessionMutation: _createPersistSessionMutation(
      _lastCreatedSessionStore!,
      attachedClientId: desktopSessionRuntimeAttachedClientId,
      diagnosticsPort: diagnosticsPort,
    ),
  );
}

void Function(Session session) _createPersistSessionMutation(
  CommonCodeSessionStore sessionStore, {
  required String attachedClientId,
  DurableLocalHostDiagnosticsPort? diagnosticsPort,
}) {
  return (Session session) {
    sessionStore
        .queueSessionPersistence(session, attachedClientId: attachedClientId)
        .catchError((Object error, StackTrace stackTrace) {
          diagnosticsPort?.emit(
            DurableLocalHostDiagnostic(
              DurableLocalHostDiagnosticCode.durableWriteFailed,
              error: error,
              stackTrace: stackTrace,
            ),
          );
        });
  };
}

final class _BootstrappedHostService implements HostService {
  const _BootstrappedHostService({
    required HostService hostService,
    required this.bootstrapPort,
  }) : _hostService = hostService;

  final HostService _hostService;
  final CommonCodeSessionBootstrapPort bootstrapPort;

  @override
  Session acknowledgeNotification({
    required String sessionId,
    required String notificationId,
  }) => _hostService.acknowledgeNotification(
    sessionId: sessionId,
    notificationId: notificationId,
  );

  @override
  Session attachClient({required String sessionId, required Client client}) =>
      _hostService.attachClient(sessionId: sessionId, client: client);

  @override
  Session createSession({
    required String sessionId,
    required Host activeHost,
  }) =>
      _hostService.createSession(sessionId: sessionId, activeHost: activeHost);

  @override
  Session readSession(String sessionId) => _hostService.readSession(sessionId);

  @override
  Session restoreSession(Session session) =>
      _hostService.restoreSession(session);

  @override
  Session submitTurn({
    required String sessionId,
    required Client client,
    required String submittedText,
  }) => _hostService.submitTurn(
    sessionId: sessionId,
    client: client,
    submittedText: submittedText,
  );

  @override
  Stream<Session> watchSession(String sessionId) =>
      _hostService.watchSession(sessionId);
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

Session _completedSessionWithNotifications() {
  return _runningSessionWithNotifications().completeActiveTurn();
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

  final Session? storedSession;

  @override
  Future<Session?> readLatestSession({required String desktopClientId}) async {
    return storedSession;
  }

  @override
  Future<void> writeLatestSession(Session session) async {}
}

final class _MultiEmittingInMemoryHostAdapter implements HostService {
  _MultiEmittingInMemoryHostAdapter();

  final Map<String, Session> _sessions = <String, Session>{};
  final Map<String, StreamController<Session>> _controllers =
      <String, StreamController<Session>>{};

  /// Stages a queued turn with notifications, simulating a session that has
  /// a turn waiting to be processed. Call this before advanceSessionToNextState()
  /// to set up a non-empty notification baseline for preservation tests.
  void stageQueuedTurnWithNotifications() {
    for (final entry in _controllers.entries) {
      final session = _sessions[entry.key];
      if (session == null) continue;

      final turnClientId = session.clients.isNotEmpty
          ? session.clients.first.id
          : 'reviewer-client';
      final notification = SessionNotification.forTransition(
        sessionId: session.id,
        turnId: 'turn-1',
        transition: SessionNotificationTransition.queuedToRunning,
      );
      final updated = Session(
        id: session.id,
        activeHost: session.activeHost,
        clients: session.clients,
        promptThread: session.promptThread.append(
          Turn.queued(
            id: 'turn-1',
            clientId: turnClientId,
            submittedText: 'Staged turn',
          ),
        ),
        notifications: [...session.notifications, notification],
      );
      _sessions[entry.key] = updated;
    }
  }

  /// Emits a host-driven state transition directly through the watch stream
  /// without going through any mutation method (submitTurn, acknowledgeNotification).
  /// This simulates a transition that the host performs independently of client
  /// mutations, proving the watch path triggers persistence.
  void advanceSessionToNextState() {
    for (final entry in _controllers.entries) {
      final session = _sessions[entry.key];
      if (session == null) continue;

      Session updated;
      if (session.activeTurn == null) {
        // No active turn - stage a queued turn with a notification first.
        // This ensures the test has a non-empty notification baseline.
        stageQueuedTurnWithNotifications();
        // Re-fetch the session after staging
        final stagedSession = _sessions[entry.key]!;
        // Now advance the staged queued turn to running - this should emit
        // the queued->running notification
        updated = _advanceQueuedTurnToRunning(stagedSession);
      } else if (session.activeTurn!.status == TurnStatus.queued) {
        // Advance queued turn to running - emit queued->running notification
        updated = _advanceQueuedTurnToRunning(session);
      } else if (session.activeTurn!.status == TurnStatus.running) {
        // Advance running turn to completed - emit running->completed notification
        updated = _advanceRunningTurnToCompleted(session);
      } else {
        continue; // Already completed or failed
      }

      _sessions[entry.key] = updated;
      entry.value.add(updated);
    }
  }

  Session _advanceQueuedTurnToRunning(Session session) {
    return session.advanceActiveTurnToRunning();
  }

  Session _advanceRunningTurnToCompleted(Session session) {
    return session.completeActiveTurn();
  }

  /// Emits a fresh session with a known mix of acknowledged and unacknowledged
  /// notifications directly through the watch stream, then returns the emitted
  /// session. Use this to create a non-vacuous baseline for notification
  /// preservation tests.
  Session emitStreamedSessionWithNotifications() {
    for (final entry in _controllers.entries) {
      final session = _sessions[entry.key];
      if (session == null) continue;

      final turnId = session.promptThread.turns.isNotEmpty
          ? 'turn-${session.promptThread.turns.length + 1}'
          : 'turn-1';
      final turnClientId = session.clients.isNotEmpty
          ? session.clients.first.id
          : 'reviewer-client';

      // Create a session with both acknowledged and unacknowledged notifications
      // so the preservation assertion is non-vacuous (AC2).
      final notifications = <SessionNotification>[
        SessionNotification.forTransition(
          sessionId: session.id,
          turnId: turnId,
          transition: SessionNotificationTransition.queuedToRunning,
          isAcknowledged: false,
        ),
        SessionNotification.forTransition(
          sessionId: session.id,
          turnId: turnId,
          transition: SessionNotificationTransition.runningToCompleted,
          isAcknowledged: true,
        ),
      ];

      final queuedTurn = Turn.queued(
        id: turnId,
        clientId: turnClientId,
        submittedText: 'Streamed turn',
      );

      final updated = Session(
        id: session.id,
        activeHost: session.activeHost,
        clients: session.clients,
        promptThread: session.promptThread.append(queuedTurn),
        notifications: notifications,
      );

      _sessions[entry.key] = updated;
      entry.value.add(updated);
      return updated;
    }
    throw StateError('No active session controller to emit through');
  }

  @override
  Session acknowledgeNotification({
    required String sessionId,
    required String notificationId,
  }) {
    final session = _sessions[sessionId]!;
    var didAcknowledge = false;
    final updatedSession = Session(
      id: session.id,
      activeHost: session.activeHost,
      clients: session.clients,
      promptThread: session.promptThread,
      notifications: [
        for (final notification in session.notifications)
          if (notification.id == notificationId && !notification.isAcknowledged)
            () {
              didAcknowledge = true;
              return SessionNotification.forTransition(
                sessionId: session.id,
                turnId: notification.turnId,
                transition: notification.transition,
                isAcknowledged: true,
              );
            }()
          else
            notification,
      ],
    );

    if (!didAcknowledge) {
      return session;
    }

    _sessions[sessionId] = updatedSession;
    _controllers[sessionId]?.add(updatedSession);
    return updatedSession;
  }

  @override
  Session attachClient({required String sessionId, required Client client}) {
    final updated = _sessions[sessionId]!.attachClient(client);
    _sessions[sessionId] = updated;
    _controllers[sessionId]?.add(updated);
    return updated;
  }

  @override
  Session createSession({required String sessionId, required Host activeHost}) {
    final session = Session(id: sessionId, activeHost: activeHost);
    _sessions[sessionId] = session;
    return session;
  }

  @override
  Session readSession(String sessionId) {
    return _sessions[sessionId]!;
  }

  @override
  Session restoreSession(Session session) {
    _sessions[session.id] = session;
    return session;
  }

  @override
  Session submitTurn({
    required String sessionId,
    required Client client,
    required String submittedText,
  }) {
    final session = _sessions[sessionId]!;
    final turnNumber =
        session.promptThread.turns
            .where((t) => t.clientId == client.id)
            .length +
        1;
    final updated = session.startTurn(
      turnId: 'turn-$turnNumber',
      client: client,
      submittedText: submittedText,
    );
    _sessions[sessionId] = updated;
    // Emit to existing watch controller (host-driven transition)
    _controllers[sessionId]?.add(updated);
    return updated;
  }

  @override
  Stream<Session> watchSession(String sessionId) {
    if (_controllers.containsKey(sessionId)) {
      throw const HostServiceFailure(
        HostServiceFailureCode.activeSessionWatchAlreadyExists,
        'Session already has an active watch.',
      );
    }

    late final StreamController<Session> controller;
    controller = StreamController<Session>(
      sync: true,
      onListen: () {
        _controllers[sessionId] = controller;
        controller.add(_sessions[sessionId]!);
      },
      onCancel: () {
        _controllers.remove(sessionId);
      },
    );
    return controller.stream;
  }
}

final class _MemoryDurableStorage implements DurableSessionStore {
  _MemoryDurableStorage({this.payload, this.legacySeedEnabled = true});

  String? payload;
  bool legacySeedEnabled;

  @override
  Future<void> disableLegacySeed({required String desktopClientId}) async {
    legacySeedEnabled = false;
  }

  @override
  Future<bool> isLegacySeedEnabled({required String desktopClientId}) async {
    return legacySeedEnabled;
  }

  @override
  Future<String?> readSessionPayload() async => payload;

  @override
  Future<void> writeSessionPayload(String payload) async {
    this.payload = payload;
  }
}
