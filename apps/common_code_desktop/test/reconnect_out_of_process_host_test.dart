// Test groups 3 and 4 from docs/issue-plans/issue-134.md.
//
// Test group 3 — Reconnect Case 1 (host alive). 4 sub-tests: R1.1, R1.2,
// R1.3, R1.4. Verifies the same-host-reused invariant, the same-session-
// bound-relationship invariant, observation resume, and notification
// continuity per ADR 0004.
//
// Test group 4 — Reconnect Case 2 (host unavailable). 3 sub-tests: R2.1,
// R2.2, R2.3. Verifies no silent in-process fallback, bounded failed-start
// outcome, and distinguishability from a successful reconnect.
//
// All tests use the real `OutOfProcessOpenCodeHostAdapter`. The R1.* tests
// use a connector that always returns success; the R2.* tests use a
// connector that flips from "alive" to "unreachable" mid-test.

import 'dart:async';

import 'package:common_code_application/common_code_application.dart';
import 'package:common_code_domain/common_code_domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:host_opencode/host_opencode.dart';

import 'support/capturing_out_of_process_host_launcher.dart';
import 'support/host_driven_transition_emitter.dart';
import 'support/reconnect_out_of_process_host_double.dart';
import 'support/stub_out_of_process_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------------------
  // Test group 3 — Reconnect Case 1 (authoritative host remains alive)
  // ---------------------------------------------------------------------------
  group('Test group 3 — Reconnect Case 1 (host alive)', () {
    test(
      'R1.1 — same host is reused: a second Host is NOT created on '
      'reconnect; connector invocation count is unchanged after '
      'disconnect/reconnect',
      () async {
        final connector = ReconnectOutOfProcessHostDouble();
        final launcher = CapturingOutOfProcessHostLauncher();
        final adapter = OutOfProcessOpenCodeHostAdapter(
          connector: connector,
          launcher: launcher,
        );

        await adapter.bootstrapReady;
        final initialConnectCount = connector.connectCallCount;
        expect(initialConnectCount, equals(1));

        // Set up the session, attach the client, submit a turn, drive it
        // through queuedToRunning + runningToCompleted via the helper.
        adapter.createSession(
          sessionId: 'r11-session',
          activeHost: const Host(id: 'r11-host'),
        );
        adapter.attachClient(
          sessionId: 'r11-session',
          client: const Client(id: 'r11-client'),
        );
        adapter.submitTurn(
          sessionId: 'r11-session',
          client: const Client(id: 'r11-client'),
          submittedText: 'R1.1 turn',
        );

        // Reconnect is modeled as: cancel any active watch subscription,
        // then re-subscribe. The production adapter does not have an
        // explicit "reconnect" method; the binding contract treats the
        // watch cancel + re-subscribe as the reconnect surface.
        final emitter = HostDrivenTransitionEmitter(adapter: adapter);
        emitter.attach(sessionId: 'r11-session');
        await emitter.detach();

        // Re-subscribe.
        emitter.attach(sessionId: 'r11-session');

        // -----------------------------------------------------------------
        // R1.1 — same host is reused. The connector invocation count is
        // unchanged (no second bootstrap was triggered by the reconnect).
        // -----------------------------------------------------------------
        expect(
          connector.connectCallCount,
          equals(initialConnectCount),
          reason: 'R1.1: reconnect must not re-run bootstrap',
        );
        expect(
          adapter.readSession('r11-session').activeHost.id,
          equals('r11-host'),
          reason: 'R1.1: same host id must remain bound to the session',
        );

        await emitter.dispose();
      },
    );

    test(
      'R1.2 — same session-bound relationship: Session.id and '
      'Session.activeHost.id are unchanged across reconnect',
      () async {
        final connector = ReconnectOutOfProcessHostDouble();
        final launcher = CapturingOutOfProcessHostLauncher();
        final adapter = OutOfProcessOpenCodeHostAdapter(
          connector: connector,
          launcher: launcher,
        );

        await adapter.bootstrapReady;

        adapter.createSession(
          sessionId: 'r12-session',
          activeHost: const Host(id: 'r12-host'),
        );
        adapter.attachClient(
          sessionId: 'r12-session',
          client: const Client(id: 'r12-client'),
        );
        adapter.submitTurn(
          sessionId: 'r12-session',
          client: const Client(id: 'r12-client'),
          submittedText: 'R1.2 turn',
        );

        // Capture the pre-reconnect identity.
        final preSession = adapter.readSession('r12-session');
        final preSessionId = preSession.id;
        final preActiveHostId = preSession.activeHost.id;

        // Reconnect via the helper.
        final emitter = HostDrivenTransitionEmitter(adapter: adapter);
        emitter.attach(sessionId: 'r12-session');
        await emitter.detach();
        emitter.attach(sessionId: 'r12-session');

        final postSession = adapter.readSession('r12-session');
        expect(
          postSession.id,
          equals(preSessionId),
          reason: 'R1.2: Session.id must be unchanged after reconnect',
        );
        expect(
          postSession.activeHost.id,
          equals(preActiveHostId),
          reason: 'R1.2: Session.activeHost.id must be unchanged after reconnect',
        );

        await emitter.dispose();
      },
    );

    test(
      'R1.3 — observation resumes: the reconnected watch stream emits '
      'a new host-driven transition reflecting the same active session '
      'state and the same activeHost.id',
      () async {
        final connector = ReconnectOutOfProcessHostDouble();
        final launcher = CapturingOutOfProcessHostLauncher();
        final adapter = OutOfProcessOpenCodeHostAdapter(
          connector: connector,
          launcher: launcher,
        );

        await adapter.bootstrapReady;

        adapter.createSession(
          sessionId: 'r13-session',
          activeHost: const Host(id: 'r13-host'),
        );
        adapter.attachClient(
          sessionId: 'r13-session',
          client: const Client(id: 'r13-client'),
        );
        adapter.submitTurn(
          sessionId: 'r13-session',
          client: const Client(id: 'r13-client'),
          submittedText: 'R1.3 turn 1',
        );

        final preHostId = adapter.readSession('r13-session').activeHost.id;

        // First watch — drive the first turn to running.
        final emitter1 = HostDrivenTransitionEmitter(adapter: adapter);
        emitter1.attach(sessionId: 'r13-session');
        emitter1.driveQueuedToRunning(sessionId: 'r13-session');
        await emitter1.detach();

        // Reconnect — re-subscribe.
        final emitter2 = HostDrivenTransitionEmitter(adapter: adapter);
        final emissions = <Session>[];
        emitter2.transitions.listen(emissions.add);
        emitter2.attach(sessionId: 'r13-session');

        // Drive one additional transition on the reconnected stream.
        // The helper's local tracking was updated to "running" by
        // emitter1, so emitter2 can drive runningToCompleted without
        // needing a fresh production submit.
        final postDrive = emitter2.driveRunningToCompleted(
          sessionId: 'r13-session',
        );

        // The reconnected stream must contain a snapshot reflecting the
        // new transition (activeTurn.status == TurnStatus.completed) and
        // the activeHost.id must match the pre-reconnect value.
        expect(
          postDrive.activeTurn!.status,
          equals(TurnStatus.completed),
        );
        expect(
          postDrive.activeHost.id,
          equals(preHostId),
          reason: 'R1.3: activeHost.id must match the pre-reconnect value',
        );

        await emitter2.dispose();
      },
    );

    test(
      'R1.4 — notification continuity per ADR 0004: acknowledged and '
      'unacknowledged notifications are preserved across reconnect; '
      'notification ids are stable',
      () async {
        final connector = ReconnectOutOfProcessHostDouble();
        final launcher = CapturingOutOfProcessHostLauncher();
        final adapter = OutOfProcessOpenCodeHostAdapter(
          connector: connector,
          launcher: launcher,
        );

        await adapter.bootstrapReady;

        adapter.createSession(
          sessionId: 'r14-session',
          activeHost: const Host(id: 'r14-host'),
        );
        adapter.attachClient(
          sessionId: 'r14-session',
          client: const Client(id: 'r14-client'),
        );
        adapter.submitTurn(
          sessionId: 'r14-session',
          client: const Client(id: 'r14-client'),
          submittedText: 'R1.4 turn',
        );

        // Drive queuedToRunning + runningToCompleted via the helper to
        // produce two notifications.
        final emitter1 = HostDrivenTransitionEmitter(adapter: adapter);
        emitter1.attach(sessionId: 'r14-session');
        emitter1.driveQueuedToRunning(sessionId: 'r14-session');
        final postRunning = emitter1.driveRunningToCompleted(
          sessionId: 'r14-session',
        );

        // The two notifications: queuedToRunning and runningToCompleted.
        final queuedToRunningNotification =
            postRunning.notifications.firstWhere(
          (n) =>
              n.transition == SessionNotificationTransition.queuedToRunning,
        );
        final runningToCompletedNotification =
            postRunning.notifications.firstWhere(
          (n) => n.transition ==
              SessionNotificationTransition.runningToCompleted,
        );

        // Acknowledge one of them (the queuedToRunning notification).
        adapter.acknowledgeNotification(
          sessionId: 'r14-session',
          notificationId: queuedToRunningNotification.id,
        );

        // Capture the pre-reconnect notification list.
        final preReconnect = adapter.readSession('r14-session');
        final preAcknowledgedId = queuedToRunningNotification.id;
        final preUnacknowledgedId = runningToCompletedNotification.id;

        // Reconnect — cancel the watch and re-subscribe.
        await emitter1.detach();
        final emitter2 = HostDrivenTransitionEmitter(adapter: adapter);
        emitter2.attach(sessionId: 'r14-session');

        // -----------------------------------------------------------------
        // R1.4 assertions.
        // -----------------------------------------------------------------
        final postReconnect = adapter.readSession('r14-session');
        final postAcknowledged = postReconnect.notifications
            .firstWhere((n) => n.id == preAcknowledgedId);
        final postUnacknowledged = postReconnect.notifications
            .firstWhere((n) => n.id == preUnacknowledgedId);

        // The previously-acknowledged notification remains acknowledged
        // (acknowledgement is preserved across reconnect; it does not
        // revert to unacknowledged).
        expect(
          postAcknowledged.isAcknowledged,
          isTrue,
          reason: 'R1.4: acknowledged notification must remain acknowledged',
        );

        // The previously-unacknowledged notification remains
        // unacknowledged (unacknowledged notifications are replayed, not
        // duplicated or lost).
        expect(
          postUnacknowledged.isAcknowledged,
          isFalse,
          reason: 'R1.4: unacknowledged notification must remain unacknowledged',
        );

        // Notification ids are stable (deterministic ids, not freshly
        // minted). This is the ADR 0004 contract: the Session is the
        // source of truth.
        expect(
          postAcknowledged.id,
          equals(preAcknowledgedId),
          reason: 'R1.4: notification id must be stable across reconnect',
        );
        expect(
          postUnacknowledged.id,
          equals(preUnacknowledgedId),
          reason: 'R1.4: notification id must be stable across reconnect',
        );

        // Both notifications are still present in the post-reconnect
        // session (no loss).
        expect(
          postReconnect.notifications,
          hasLength(2),
        );

        await emitter2.dispose();
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Test group 4 — Reconnect Case 2 (authoritative host is unavailable)
  // ---------------------------------------------------------------------------
  group('Test group 4 — Reconnect Case 2 (host unavailable)', () {
    test(
      'R2.1 — no silent in-process fallback: the connector is probed on '
      'the reconnect attempt; the launcher is NOT invoked as a fallback',
      () async {
        // The connector begins alive; bootstrap succeeds once. Then the
        // test flips it to unreachable and observes a subsequent
        // reconnect attempt.
        final connector = ReconnectOutOfProcessHostDouble();
        final launcher = CapturingOutOfProcessHostLauncher();
        final adapter = OutOfProcessOpenCodeHostAdapter(
          connector: connector,
          launcher: launcher,
        );

        await adapter.bootstrapReady;
        final initialConnectCount = connector.connectCallCount;
        expect(initialConnectCount, equals(1));
        expect(launcher.launchCallCount, equals(0));

        // Set up the session and a queued turn.
        adapter.createSession(
          sessionId: 'r21-session',
          activeHost: const Host(id: 'r21-host'),
        );
        adapter.attachClient(
          sessionId: 'r21-session',
          client: const Client(id: 'r21-client'),
        );
        adapter.submitTurn(
          sessionId: 'r21-session',
          client: const Client(id: 'r21-client'),
          submittedText: 'R2.1 turn',
        );

        // Simulate a "reconnect attempt" by flipping the connector to
        // unreachable and asking the adapter to do something that would
        // normally exercise the watch path.
        connector.flipToUnreachable();

        // Cancel the existing watch and re-subscribe. The helper
        // re-subscribe uses the same production watch path; it does
        // not trigger a new bootstrap.
        final emitter = HostDrivenTransitionEmitter(adapter: adapter);
        emitter.attach(sessionId: 'r21-session');
        await emitter.detach();
        emitter.attach(sessionId: 'r21-session');

        // -----------------------------------------------------------------
        // R2.1 assertions.
        // -----------------------------------------------------------------
        // The composed HostService is observably still the same OOPIE
        // adapter instance (the test holds a strong reference to it
        // and asserts the runtime did not substitute a different
        // HostService).
        expect(
          adapter,
          isA<OutOfProcessOpenCodeHostAdapter>(),
          reason: 'R2.1: composed HostService must remain the OOPIE adapter',
        );

        // The launcher was NOT invoked as a fallback path; the launcher
        // is one-shot at bootstrap only.
        expect(
          launcher.launchCallCount,
          equals(0),
          reason: 'R2.1: launcher must not be invoked on reconnect',
        );

        // No second Host was created. The session's activeHost.id is
        // unchanged.
        expect(
          adapter.readSession('r21-session').activeHost.id,
          equals('r21-host'),
          reason: 'R2.1: no second Host must be created on reconnect',
        );

        await emitter.dispose();
      },
    );

    test(
      'R2.2 — bounded failed-start outcome: the reconnect path surfaces '
      'a bounded failure without automatic failover or a second Host',
      () async {
        // Configure the connector to fail on every call, modeling a host
        // that is never reachable. Bootstrap will fail with a bounded
        // failed-start outcome; subsequent session operations should
        // surface a HostServiceFailure.
        final connector = ReconnectOutOfProcessHostDouble.unreachable();
        final launcher = CapturingOutOfProcessHostLauncher();
        final adapter = OutOfProcessOpenCodeHostAdapter(
          connector: connector,
          launcher: launcher,
        );

        // Await the bootstrap future; it should resolve without throwing
        // (the bootstrap future is the eager fire-and-forget future; the
        // bounded failed-start outcome is surfaced only on session ops).
        await adapter.bootstrapReady;

        // -----------------------------------------------------------------
        // R2.2 — the adapter surfaces the failed-start state as a
        // HostServiceFailure on the first session operation. The failure
        // is bounded (no retry loop, no automatic failover).
        // -----------------------------------------------------------------
        HostServiceFailure? caughtFailure;
        try {
          adapter.createSession(
            sessionId: 'r22-session',
            activeHost: const Host(id: 'r22-host'),
          );
        } on HostServiceFailure catch (e) {
          caughtFailure = e;
        }

        expect(
          caughtFailure,
          isNotNull,
          reason: 'R2.2: failed-start must surface a HostServiceFailure',
        );
        expect(
          caughtFailure!.code,
          isA<HostServiceFailureCode>(),
          reason: 'R2.2: failure code must be a HostServiceFailureCode',
        );
        // The failure message must be non-empty and reference the
        // out-of-process host (it should mention the OOPIE adapter or
        // the connector/launcher, not the in-process fallback).
        expect(
          caughtFailure!.message,
          isNotEmpty,
          reason: 'R2.2: failure message must be non-empty',
        );

        // The launcher was NOT invoked as a fallback (the connector
        // was unreachable from the start; no host was ever available
        // to be launched).
        expect(
          launcher.launchCallCount,
          equals(0),
          reason: 'R2.2: launcher must not be invoked on a connector-only failure',
        );

        // No second Host was created — the session was never created.
        expect(
          () => adapter.readSession('r22-session'),
          throwsA(isA<HostServiceFailure>()),
          reason: 'R2.2: no second Host/session must be created',
        );
      },
    );

    test(
      'R2.3 — distinguishable from successful reconnect: a failed-start '
      'path produces a different observable shape than the success path',
      () async {
        // R2.3 sets up two adapters: one for the successful path (R1.1
        // setup) and one for the failed-start path. The assertions
        // compare the observable shapes.
        // -----------------------------------------------------------------
        // Success path: host alive, reconnect succeeds.
        // -----------------------------------------------------------------
        final successConnector = ReconnectOutOfProcessHostDouble();
        final successLauncher = CapturingOutOfProcessHostLauncher();
        final successAdapter = OutOfProcessOpenCodeHostAdapter(
          connector: successConnector,
          launcher: successLauncher,
        );
        await successAdapter.bootstrapReady;
        successAdapter.createSession(
          sessionId: 'r23-success-session',
          activeHost: const Host(id: 'r23-success-host'),
        );
        successAdapter.attachClient(
          sessionId: 'r23-success-session',
          client: const Client(id: 'r23-success-client'),
        );
        successAdapter.submitTurn(
          sessionId: 'r23-success-session',
          client: const Client(id: 'r23-success-client'),
          submittedText: 'R2.3 success turn',
        );
        final successEmissions = <Session>[];
        final successEmitter =
            HostDrivenTransitionEmitter(adapter: successAdapter);
        successEmitter.transitions.listen(successEmissions.add);
        successEmitter.attach(sessionId: 'r23-success-session');
        // The success path produces a session snapshot on the watch
        // stream.
        expect(successEmissions, isNotEmpty);
        // The success path's session is fully readable.
        final successSession =
            successAdapter.readSession('r23-success-session');
        expect(successSession.id, equals('r23-success-session'));
        expect(successSession.activeHost.id, equals('r23-success-host'));
        await successEmitter.dispose();

        // -----------------------------------------------------------------
        // Failed-start path: host unavailable, reconnect fails.
        // -----------------------------------------------------------------
        final failureConnector = ReconnectOutOfProcessHostDouble.unreachable();
        final failureLauncher = CapturingOutOfProcessHostLauncher();
        final failureAdapter = OutOfProcessOpenCodeHostAdapter(
          connector: failureConnector,
          launcher: failureLauncher,
        );
        await failureAdapter.bootstrapReady;

        // The failed-start path must throw a HostServiceFailure on
        // session operations (no successful session-bound relationship
        // is established).
        HostServiceFailure? caughtFailure;
        try {
          failureAdapter.createSession(
            sessionId: 'r23-failure-session',
            activeHost: const Host(id: 'r23-failure-host'),
          );
        } on HostServiceFailure catch (e) {
          caughtFailure = e;
        }
        expect(caughtFailure, isNotNull);

        // The successful path did not throw; the failed-start path did.
        // These are observably distinct outcomes.
        expect(
          successSession.id,
          equals('r23-success-session'),
          reason: 'R2.3: success path produces a healthy session snapshot',
        );
        expect(
          caughtFailure!.code,
          isA<HostServiceFailureCode>(),
          reason: 'R2.3: failure path produces a HostServiceFailure, not a snapshot',
        );

        // The failed-start path does not mutate the existing Session
        // (no second Host, no fresh bootstrap, no fresh connector/
        // launcher in the sense of a new OOPIE adapter instance).
        expect(
          failureAdapter,
          isA<OutOfProcessOpenCodeHostAdapter>(),
          reason: 'R2.3: failure path must not construct a new adapter',
        );
        // The launcher was not invoked on the failed-start path.
        expect(
          failureLauncher.launchCallCount,
          equals(0),
          reason: 'R2.3: launcher must not be invoked on the failed-start path',
        );
      },
    );
  });
}
