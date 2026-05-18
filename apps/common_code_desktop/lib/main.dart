import 'package:common_code_domain/common_code_domain.dart';
import 'package:flutter/material.dart';
import 'package:host_core/host_core.dart';

void main() {
  runApp(CommonCodeDesktopApp());
}

class CommonCodeDesktopApp extends StatelessWidget {
  CommonCodeDesktopApp({super.key, DesktopSessionLoader? sessionLoader})
    : sessionLoader = sessionLoader ?? DesktopHostSessionLoader();

  final DesktopSessionLoader sessionLoader;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CommonCode Desktop',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: SessionScreen(sessionLoader: sessionLoader),
    );
  }
}

abstract interface class DesktopSessionLoader {
  Future<DesktopSessionSnapshot?> load();
}

final class DesktopSessionSnapshot {
  const DesktopSessionSnapshot({
    required this.session,
    required this.attachedClientId,
  });

  final Session session;
  final String attachedClientId;
}

final class DesktopHostSessionLoader implements DesktopSessionLoader {
  DesktopHostSessionLoader({HostService? hostService})
    : _hostService = hostService;

  final HostService? _hostService;

  static const _sessionId = 'desktop-session';
  static const _hostId = 'desktop-host';
  static const _attachedClientId = 'desktop-client';

  HostService? _service;
  bool _isBootstrapped = false;

  @override
  Future<DesktopSessionSnapshot?> load() async {
    final service = _service ??= _hostService ?? createInMemoryHostService();

    if (!_isBootstrapped) {
      service.createSession(
        sessionId: _sessionId,
        activeHost: const Host(id: _hostId),
      );
      service.attachClient(
        sessionId: _sessionId,
        client: const Client(id: _attachedClientId),
      );
      _isBootstrapped = true;
    }

    return DesktopSessionSnapshot(
      session: service.readSession(_sessionId),
      attachedClientId: _attachedClientId,
    );
  }
}

class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key, required this.sessionLoader});

  final DesktopSessionLoader sessionLoader;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  SessionScreenState _state = const SessionScreenLoading();

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  Future<void> _loadSession() async {
    setState(() {
      _state = const SessionScreenLoading();
    });

    try {
      final snapshot = await widget.sessionLoader.load();
      if (!mounted) {
        return;
      }

      setState(() {
        _state = switch (snapshot) {
          null => const SessionScreenEmpty(),
          final snapshot => SessionScreenData(snapshot),
        };
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _state = SessionScreenError(error.toString());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('CommonCode Desktop'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: switch (_state) {
              SessionScreenLoading() => const _SessionLoadingView(),
              SessionScreenEmpty() => _SessionEmptyView(
                onRefresh: _loadSession,
              ),
              SessionScreenError(:final message) => _SessionErrorView(
                message: message,
                onRetry: _loadSession,
              ),
              SessionScreenData(:final snapshot) => _SessionDataView(
                snapshot: snapshot,
                onRefresh: _loadSession,
              ),
            },
          ),
        ),
      ),
    );
  }
}

sealed class SessionScreenState {
  const SessionScreenState();
}

final class SessionScreenLoading extends SessionScreenState {
  const SessionScreenLoading();
}

final class SessionScreenEmpty extends SessionScreenState {
  const SessionScreenEmpty();
}

final class SessionScreenError extends SessionScreenState {
  const SessionScreenError(this.message);

  final String message;
}

final class SessionScreenData extends SessionScreenState {
  const SessionScreenData(this.snapshot);

  final DesktopSessionSnapshot snapshot;
}

class _SessionLoadingView extends StatelessWidget {
  const _SessionLoadingView();

  @override
  Widget build(BuildContext context) {
    return const _SessionSection(
      title: 'Loading session...',
      children: [
        Text('Reading the current Session from the desktop host service.'),
      ],
    );
  }
}

class _SessionEmptyView extends StatelessWidget {
  const _SessionEmptyView({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return _SessionSection(
      title: 'No session available.',
      children: [
        const Text('No Session was returned for the desktop app.'),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () {
            onRefresh();
          },
          child: const Text('Refresh Session'),
        ),
      ],
    );
  }
}

class _SessionErrorView extends StatelessWidget {
  const _SessionErrorView({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return _SessionSection(
      title: 'Failed to load session.',
      children: [
        Text(message),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () {
            onRetry();
          },
          child: const Text('Retry'),
        ),
      ],
    );
  }
}

class _SessionDataView extends StatelessWidget {
  const _SessionDataView({required this.snapshot, required this.onRefresh});

  final DesktopSessionSnapshot snapshot;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final session = snapshot.session;
    final inputClientId = session.inputClient?.id ?? 'none';
    final activeTurnId = session.activeTurn?.id ?? 'none';

    return _SessionSection(
      title: 'Live Session state',
      children: [
        Text('Session id: ${session.id}'),
        const SizedBox(height: 8),
        Text('Host id: ${session.activeHost.id}'),
        const SizedBox(height: 8),
        Text('Attached Client: ${snapshot.attachedClientId}'),
        const SizedBox(height: 8),
        Text('Input Client: $inputClientId'),
        const SizedBox(height: 8),
        Text('Prompt Thread turns: ${session.promptThread.turns.length}'),
        const SizedBox(height: 8),
        Text('Active Turn: $activeTurnId'),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () {
            onRefresh();
          },
          child: const Text('Refresh Session'),
        ),
      ],
    );
  }
}

class _SessionSection extends StatelessWidget {
  const _SessionSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}
