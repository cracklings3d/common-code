import 'dart:async';

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

  Stream<DesktopSessionSnapshot?> watch();

  Future<DesktopSessionSnapshot> submitTurn({required String submittedText});
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

  Future<void> _bootstrapIfNeeded() async {
    final service = _service ??= _hostService ?? createInMemoryHostService();

    if (_isBootstrapped) {
      return;
    }

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

  @override
  Future<DesktopSessionSnapshot?> load() async {
    final service = _service ??= _hostService ?? createInMemoryHostService();
    await _bootstrapIfNeeded();

    return DesktopSessionSnapshot(
      session: service.readSession(_sessionId),
      attachedClientId: _attachedClientId,
    );
  }

  @override
  Stream<DesktopSessionSnapshot?> watch() async* {
    final service = _service ??= _hostService ?? createInMemoryHostService();
    await _bootstrapIfNeeded();

    await for (final session in service.watchSession(_sessionId)) {
      yield DesktopSessionSnapshot(
        session: session,
        attachedClientId: _attachedClientId,
      );
    }
  }

  @override
  Future<DesktopSessionSnapshot> submitTurn({
    required String submittedText,
  }) async {
    final service = _service ??= _hostService ?? createInMemoryHostService();

    await _bootstrapIfNeeded();

    final session = service.submitTurn(
      sessionId: _sessionId,
      client: const Client(id: _attachedClientId),
      submittedText: submittedText,
    );

    return DesktopSessionSnapshot(
      session: session,
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
  final TextEditingController _draftController = TextEditingController();
  bool _isSubmitting = false;
  StreamSubscription<DesktopSessionSnapshot?>? _watchSubscription;

  @override
  void initState() {
    super.initState();
    _startSessionWatch();
  }

  Future<void> _startSessionWatch() async {
    await _watchSubscription?.cancel();

    if (!mounted) {
      return;
    }

    setState(() {
      _state = const SessionScreenLoading();
    });

    try {
      final stream = widget.sessionLoader.watch();
      _watchSubscription = stream.listen(
        (snapshot) {
          if (!mounted) {
            return;
          }

          setState(() {
            _state = switch (snapshot) {
              null => const SessionScreenEmpty(),
              final snapshot => SessionScreenData(snapshot),
            };
          });
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!mounted) {
            return;
          }

          setState(() {
            _state = SessionScreenError(error.toString());
          });
        },
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _state = SessionScreenError(error.toString());
      });
    }
  }

  Future<void> _submitTurn() async {
    final draftText = _draftController.text;

    setState(() {
      _isSubmitting = true;
    });

    try {
      await widget.sessionLoader.submitTurn(submittedText: draftText);
      if (!mounted) {
        return;
      }

      setState(() {
        _draftController.clear();
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _state = SessionScreenError(error.toString());
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _watchSubscription?.cancel();
    _draftController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('CommonCode Desktop'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: switch (_state) {
              SessionScreenLoading() => const _SessionLoadingView(),
              SessionScreenEmpty() => _SessionEmptyView(
                onRefresh: _startSessionWatch,
              ),
              SessionScreenError(:final message) => _SessionErrorView(
                message: message,
                onRetry: _startSessionWatch,
              ),
              SessionScreenData(:final snapshot) => _SessionDataView(
                snapshot: snapshot,
                draftController: _draftController,
                onRefresh: _startSessionWatch,
                onSubmitTurn: _submitTurn,
                isSubmitting: _isSubmitting,
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
          onPressed: () async {
            await onRefresh();
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
          onPressed: () async {
            await onRetry();
          },
          child: const Text('Retry'),
        ),
      ],
    );
  }
}

class _SessionDataView extends StatelessWidget {
  const _SessionDataView({
    required this.snapshot,
    required this.draftController,
    required this.onRefresh,
    required this.onSubmitTurn,
    required this.isSubmitting,
  });

  final DesktopSessionSnapshot snapshot;
  final TextEditingController draftController;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onSubmitTurn;
  final bool isSubmitting;

  @override
  Widget build(BuildContext context) {
    final session = snapshot.session;
    final inputClientId = session.inputClient?.id ?? 'none';
    final activeTurnId = session.activeTurn?.id ?? 'none';
    final hasActiveTurn = session.activeTurn != null;

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
        if (session.promptThread.turns.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Prompt Thread', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final turn in session.promptThread.turns) ...[
            Text('Turn ${turn.id}: ${turn.submittedText}'),
            Text('Status: ${turn.status.name}'),
            if (turn.failureSummary case final failureSummary?)
              Text('Failure: $failureSummary'),
            const SizedBox(height: 8),
          ],
        ],
        const SizedBox(height: 16),
        if (!hasActiveTurn) ...[
          TextField(
            controller: draftController,
            decoration: const InputDecoration(
              labelText: 'Next Turn',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: isSubmitting
                ? null
                : () async {
                    await onSubmitTurn();
                  },
            child: Text(isSubmitting ? 'Submitting...' : 'Submit Turn'),
          ),
        ] else ...[
          const Text(
            'Turn authoring is unavailable while the current active Turn remains in progress.',
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () async {
            await onRefresh();
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
