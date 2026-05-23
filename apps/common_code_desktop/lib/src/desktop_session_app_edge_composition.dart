import 'dart:convert';

import 'package:common_code_application/common_code_application.dart';
import 'package:common_code_domain/common_code_domain.dart';
import 'package:host_core/host_core.dart';

import 'desktop_session_runtime_constants.dart';
import 'desktop_session_snapshot_codec.dart';
import 'desktop_session_snapshot_store.dart';
import 'durable_local_host_service.dart';

CommonCodeSessionFacade createDesktopSessionFacade({
  CommonCodeSessionDriver? driver,
  String attachedClientId = desktopSessionRuntimeAttachedClientId,
  Object? hostService,
  Object? snapshotStore,
  Object? durableStorage,
  Object Function()? hostServiceFactory,
  Object? diagnosticsSink,
  String defaultSessionId = desktopSessionRuntimeDefaultSessionId,
  String hostId = desktopSessionRuntimeHostId,
}) {
  return CommonCodeSessionFacade(
    driver:
        driver ??
        HostCoreDesktopSessionDriver(
          hostService: hostService as HostService?,
          snapshotStore: snapshotStore as DesktopSessionSnapshotStore?,
          durableStorage: durableStorage as DurableLocalHostStorage?,
          hostServiceFactory: hostServiceFactory == null
              ? null
              : () => hostServiceFactory() as HostService,
          diagnosticsSink: diagnosticsSink as DurableLocalHostDiagnosticsSink?,
          defaultSessionId: defaultSessionId,
          hostId: hostId,
          attachedClientId: attachedClientId,
        ),
    attachedClientId: attachedClientId,
  );
}

final class HostCoreDesktopSessionDriver implements CommonCodeSessionDriver {
  HostCoreDesktopSessionDriver({
    HostService? hostService,
    DesktopSessionSnapshotStore? snapshotStore,
    DurableLocalHostStorage? durableStorage,
    HostService Function()? hostServiceFactory,
    DurableLocalHostDiagnosticsSink? diagnosticsSink,
    String defaultSessionId = desktopSessionRuntimeDefaultSessionId,
    String hostId = desktopSessionRuntimeHostId,
    String attachedClientId = desktopSessionRuntimeAttachedClientId,
  }) : _hostService = hostService,
       _legacySnapshotStore =
           snapshotStore ?? SharedPreferencesDesktopSessionSnapshotStore(),
       _durableStorage =
           durableStorage ?? SharedPreferencesDurableLocalHostStorage(),
       _hostServiceFactory =
           hostServiceFactory ??
           (() => DurableLocalHostService(
             legacySnapshotStore:
                 snapshotStore ??
                 SharedPreferencesDesktopSessionSnapshotStore(),
             diagnosticsSink: diagnosticsSink,
           )),
       _defaultSessionId = defaultSessionId,
       _hostId = hostId,
       _attachedClientId = attachedClientId {
    _bootstrap = CommonCodeSessionBootstrap(
      sessionStore: _DesktopSessionStore(
        hostServiceFactory: _getService,
        legacySnapshotStore: _legacySnapshotStore,
        durableStorage: _durableStorage,
        diagnosticsSink: diagnosticsSink,
        desktopClientId: attachedClientId,
      ),
      identityContext: _DesktopIdentityContext(
        attachedClientId: attachedClientId,
      ),
    );
  }

  final HostService? _hostService;
  final DesktopSessionSnapshotStore _legacySnapshotStore;
  final DurableLocalHostStorage _durableStorage;
  final HostService Function() _hostServiceFactory;
  final String _defaultSessionId;
  final String _hostId;
  final String _attachedClientId;
  late final CommonCodeSessionBootstrap _bootstrap;

  HostService? _service;
  bool _isBootstrapped = false;
  String? _currentSessionId;

  @override
  Future<CommonCodeSessionBinding> ensureSession() async {
    await _bootstrapIfNeeded();
    return CommonCodeSessionBinding.attached(sessionId: _currentSessionId!);
  }

  @override
  Future<void> acknowledgeNotification({
    required String sessionId,
    required String notificationId,
  }) async {
    final service = _service ??= _hostService ?? _hostServiceFactory();
    await _bootstrapIfNeeded();

    service.acknowledgeNotification(
      sessionId: sessionId,
      notificationId: notificationId,
    );
  }

  @override
  Future<void> submitTurn({
    required String sessionId,
    required String attachedClientId,
    required String submittedText,
  }) async {
    final service = _service ??= _hostService ?? _hostServiceFactory();
    await _bootstrapIfNeeded();

    service.submitTurn(
      sessionId: sessionId,
      client: Client(id: attachedClientId),
      submittedText: submittedText,
    );
  }

  @override
  Stream<Session> watchSession(String sessionId) {
    final service = _getService();
    return service.watchSession(sessionId);
  }

  Future<void> _bootstrapIfNeeded() async {
    if (_isBootstrapped) {
      return;
    }

    final bootstrappedSession = await _bootstrap.ensureSession(
      defaultSessionId: _defaultSessionId,
      hostId: _hostId,
    );
    _currentSessionId = bootstrappedSession.id;
    _isBootstrapped = true;
  }

  HostService _getService() =>
      _service ??= _hostService ?? _hostServiceFactory();
}

enum _DesktopSessionRestoreSource { durable, legacy }

final class _DesktopSessionStore implements CommonCodeSessionStore {
  _DesktopSessionStore({
    required HostService Function() hostServiceFactory,
    required DesktopSessionSnapshotStore legacySnapshotStore,
    required DurableLocalHostStorage durableStorage,
    required this.desktopClientId,
    this.diagnosticsSink,
    DesktopSessionSnapshotJsonCodec codec =
        const DesktopSessionSnapshotJsonCodec(),
  }) : _hostServiceFactory = hostServiceFactory,
       _legacySnapshotStore = legacySnapshotStore,
       _durableStorage = durableStorage,
       _codec = codec;

  final HostService Function() _hostServiceFactory;
  final DesktopSessionSnapshotStore _legacySnapshotStore;
  final DurableLocalHostStorage _durableStorage;
  final DesktopSessionSnapshotJsonCodec _codec;
  final String desktopClientId;
  final DurableLocalHostDiagnosticsSink? diagnosticsSink;

  _DesktopSessionRestoreSource? _pendingRestoreSource;
  bool _shouldEmitFreshBootstrap = false;

  @override
  Future<Session?> readLatestSession() async {
    _pendingRestoreSource = null;
    _shouldEmitFreshBootstrap = false;

    try {
      final encodedDurableSession = await _durableStorage.readSessionPayload();
      if (encodedDurableSession == null) {
        _emit(DurableLocalHostDiagnosticCode.durableReadMissing);
        return _readLegacySession();
      }

      final decodedDurableSession = _decodeDurableSession(
        encodedDurableSession,
      );
      if (decodedDurableSession == null) {
        _emit(DurableLocalHostDiagnosticCode.durableReadCorruptOrInvalid);
        return _readLegacySession();
      }

      _pendingRestoreSource = _DesktopSessionRestoreSource.durable;
      return decodedDurableSession;
    } catch (error, stackTrace) {
      _emit(
        DurableLocalHostDiagnosticCode.durableReadFailed,
        error: error,
        stackTrace: stackTrace,
      );
      _shouldEmitFreshBootstrap = true;
      return null;
    }
  }

  @override
  Future<Session> restoreSession(Session session) async {
    final restoreSource = _pendingRestoreSource;
    _pendingRestoreSource = null;

    if (_shouldEmitFreshBootstrap) {
      _emit(DurableLocalHostDiagnosticCode.freshBootstrapActivated);
      _shouldEmitFreshBootstrap = false;
    }

    try {
      switch (restoreSource) {
        case _DesktopSessionRestoreSource.durable:
          final restoredSession = _hydrateSession(
            session,
            restoreSource: restoreSource,
          );
          _emit(DurableLocalHostDiagnosticCode.durableReadRestored);
          return restoredSession;
        case _DesktopSessionRestoreSource.legacy:
          await _persistDurableSession(session);
          final restoredLegacySession = _hydrateSession(
            session,
            restoreSource: restoreSource,
          );
          _emit(DurableLocalHostDiagnosticCode.legacySeedSucceeded);
          return restoredLegacySession;
        case null:
          final freshSession = _hydrateSession(session);
          try {
            await _persistDurableSession(freshSession);
          } catch (error, stackTrace) {
            _emit(
              DurableLocalHostDiagnosticCode.durableWriteFailed,
              error: error,
              stackTrace: stackTrace,
            );
          }
          return freshSession;
      }
    } catch (error, stackTrace) {
      switch (restoreSource) {
        case _DesktopSessionRestoreSource.durable:
          _emit(
            DurableLocalHostDiagnosticCode.durableRestoreFailed,
            error: error,
            stackTrace: stackTrace,
          );
          _shouldEmitFreshBootstrap = true;
          rethrow;
        case _DesktopSessionRestoreSource.legacy:
          _emit(
            DurableLocalHostDiagnosticCode.legacySeedFailed,
            error: error,
            stackTrace: stackTrace,
          );
          _shouldEmitFreshBootstrap = true;
          rethrow;
        case null:
          rethrow;
      }
    }
  }

  Session _hydrateSession(
    Session session, {
    _DesktopSessionRestoreSource? restoreSource,
  }) {
    final service = _hostServiceFactory();
    if (restoreSource == _DesktopSessionRestoreSource.durable &&
        service is DurableLocalHostService) {
      final durableService = service;
      return durableService.restoreBootstrappedSession(session);
    }

    return service.restoreSession(session);
  }

  Future<Session?> _readLegacySession() async {
    try {
      final isLegacySeedEnabled = await _durableStorage.isLegacySeedEnabled(
        desktopClientId: desktopClientId,
      );
      if (!isLegacySeedEnabled) {
        _emit(DurableLocalHostDiagnosticCode.legacySeedSkipped);
        _shouldEmitFreshBootstrap = true;
        return null;
      }

      _emit(DurableLocalHostDiagnosticCode.legacySeedActivated);
      final legacySession = await _legacySnapshotStore.readLatestSession(
        desktopClientId: desktopClientId,
      );
      if (legacySession == null) {
        _emit(DurableLocalHostDiagnosticCode.legacySeedFailed);
        _shouldEmitFreshBootstrap = true;
        return null;
      }

      _pendingRestoreSource = _DesktopSessionRestoreSource.legacy;
      return legacySession;
    } catch (error, stackTrace) {
      _emit(
        DurableLocalHostDiagnosticCode.legacySeedFailed,
        error: error,
        stackTrace: stackTrace,
      );
      _shouldEmitFreshBootstrap = true;
      return null;
    }
  }

  Session? _decodeDurableSession(String encodedSession) {
    try {
      return _codec.decode(
        jsonDecode(encodedSession),
        desktopClientId: desktopClientId,
      );
    } catch (_) {
      return null;
    }
  }

  void _emit(
    DurableLocalHostDiagnosticCode code, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    diagnosticsSink?.call(
      DurableLocalHostDiagnostic(code, error: error, stackTrace: stackTrace),
    );
  }

  Future<void> _persistDurableSession(Session session) async {
    await _durableStorage.writeSessionPayload(
      jsonEncode(_codec.encode(session)),
    );
    await _durableStorage.disableLegacySeed(desktopClientId: desktopClientId);
  }
}

final class _DesktopIdentityContext implements CommonCodeIdentityContext {
  const _DesktopIdentityContext({required String attachedClientId})
    : _attachedClientId = attachedClientId;

  final String _attachedClientId;

  @override
  Future<Client> resolveAttachedClient({required String sessionId}) async {
    return Client(id: _attachedClientId);
  }
}
