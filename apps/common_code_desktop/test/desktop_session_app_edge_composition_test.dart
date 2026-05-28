import 'dart:async';
import 'dart:convert';

import 'package:common_code_application/common_code_application.dart';
import 'package:common_code_desktop/src/desktop_session_app_edge_composition.dart';
import 'package:common_code_desktop/src/desktop_session_runtime.dart';
import 'package:common_code_domain/common_code_domain.dart';
import 'package:common_code_observability/common_code_observability.dart';
import 'package:common_code_persistence/common_code_persistence.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:host_core/host_core.dart';
import 'package:host_in_memory/host_in_memory.dart';

void main() {
  group('createDesktopSessionFacade', () {
    test(
      'composes restore, submit, acknowledge, persistence, and diagnostics',
      () async {
        final diagnostics = <DurableLocalHostDiagnosticCode>[];
        final durableStorage = _MemoryDurableStorage(
          payload: jsonEncode(
            const SessionSnapshotCodec().encode(
              _completedSessionWithNotification(),
            ),
          ),
        );
        final sessionStore = DurableLocalSessionStore.fromPersistenceComponents(
          legacySnapshotStore: _MemoryLegacySnapshotStore(),
          durableStorage: durableStorage,
        );
        final hostAdapter = InMemoryHostAdapter();
        final hostService = hostAdapter as HostService;
        final facade = createDesktopSessionFacade(
          hostService: hostService,
          bootstrapPort: CommonCodeSessionBootstrapPortAdapter(
            sessionStore: sessionStore,
            host: CommonCodeSessionBootstrapHost(
              restoreSession: hostAdapter.restoreSession,
              createSession: hostAdapter.createSession,
              attachClient: hostAdapter.attachClient,
            ),
            diagnosticsPort: DurableLocalHostDiagnosticsEmitter(
              (diagnostic) => diagnostics.add(diagnostic.code),
            ),
          ),
          persistSessionMutation: sessionStore.createPersistenceContinuation(
            attachedClientId: desktopSessionRuntimeAttachedClientId,
            onError: createDurableWriteFailureReporter(
              DurableLocalHostDiagnosticsEmitter(
                (diagnostic) => diagnostics.add(diagnostic.code),
              ),
            ),
          ),
        );

        await facade.initialize();

        expect(facade.state.status, CommonCodeSessionFacadeStatus.data);
        expect(
          facade.state.snapshot!.session.notifications.where(
            (notification) => !notification.isAcknowledged,
          ),
          hasLength(1),
        );
        expect(
          diagnostics,
          contains(DurableLocalHostDiagnosticCode.durableReadRestored),
        );

        await facade.submitTurn(submittedText: 'persist me');
        await sessionStore.waitForPendingPersistence();

        expect(
          hostService.readSession('restored-session').activeTurn?.submittedText,
          'persist me',
        );
        expect(await durableStorage.readSessionPayload(), isNotNull);
        expect(
          await durableStorage.isLegacySeedEnabled(
            desktopClientId: desktopSessionRuntimeAttachedClientId,
          ),
          isFalse,
        );

        final notificationId = facade.state.snapshot!.session.notifications
            .firstWhere((notification) => !notification.isAcknowledged)
            .id;
        await facade.acknowledgeNotification(notificationId: notificationId);

        expect(
          hostService
              .readSession('restored-session')
              .notifications
              .firstWhere((notification) => notification.id == notificationId)
              .isAcknowledged,
          isTrue,
        );

        await facade.dispose();
      },
    );
  });
}

Session _completedSessionWithNotification() {
  final session =
      Session(
            id: 'restored-session',
            activeHost: const Host(id: 'restored-host'),
            clients: const <Client>[
              Client(id: desktopSessionRuntimeAttachedClientId),
              Client(id: 'reviewer-client'),
            ],
          )
          .startTurn(
            turnId: 'turn-1',
            client: const Client(id: 'reviewer-client'),
            submittedText: 'Restored turn',
          )
          .advanceActiveTurnToRunning()
          .completeActiveTurn();

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
    ],
  );
}

final class _MemoryLegacySnapshotStore implements SessionSnapshotStore {
  @override
  Future<Session?> readLatestSession({required String desktopClientId}) async {
    return null;
  }

  @override
  Future<void> writeLatestSession(Session session) async {}
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
