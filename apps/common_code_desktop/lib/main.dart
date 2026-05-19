import 'package:flutter/material.dart';

import 'src/desktop_session_controller.dart';

void main() {
  runApp(CommonCodeDesktopApp());
}

class CommonCodeDesktopApp extends StatelessWidget {
  CommonCodeDesktopApp({super.key, DesktopSessionController? sessionController})
    : sessionController = sessionController ?? DesktopSessionController(),
      _ownsSessionController = sessionController == null;

  final DesktopSessionController sessionController;
  final bool _ownsSessionController;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CommonCode Desktop',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: SessionScreen(
        sessionController: sessionController,
        disposeSessionController: _ownsSessionController,
      ),
    );
  }
}

class SessionScreen extends StatefulWidget {
  const SessionScreen({
    super.key,
    required this.sessionController,
    required this.disposeSessionController,
  });

  final DesktopSessionController sessionController;
  final bool disposeSessionController;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  final TextEditingController _draftController = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.sessionController.initialize();
  }

  Future<void> _refreshSession() {
    try {
      return widget.sessionController.refresh();
    } catch (_) {
      return Future<void>.value();
    }
  }

  Future<void> _submitTurn() async {
    final draftText = _draftController.text;

    try {
      await widget.sessionController.submitTurn(submittedText: draftText);
      if (!mounted) {
        return;
      }

      _draftController.clear();
    } catch (_) {
      // The controller already exposes a renderable error state.
    }
  }

  @override
  void dispose() {
    if (widget.disposeSessionController) {
      widget.sessionController.dispose();
    }
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
      body: AnimatedBuilder(
        animation: widget.sessionController,
        builder: (context, child) {
          final state = widget.sessionController.state;

          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: switch (state.status) {
                  DesktopSessionControllerStatus.loading =>
                    const _SessionLoadingView(),
                  DesktopSessionControllerStatus.empty => _SessionEmptyView(
                    onRefresh: _refreshSession,
                  ),
                  DesktopSessionControllerStatus.error => _SessionErrorView(
                    message: state.message!,
                    onRetry: _refreshSession,
                  ),
                  DesktopSessionControllerStatus.data => _SessionDataView(
                    snapshot: state.snapshot!,
                    draftController: _draftController,
                    onRefresh: _refreshSession,
                    onSubmitTurn: _submitTurn,
                    isSubmitting: state.isSubmitting,
                  ),
                },
              ),
            ),
          );
        },
      ),
    );
  }
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
    final attachedClientIds = session.clients
        .map((client) => client.id)
        .join(', ');

    return _SessionSection(
      title: 'Live Session state',
      children: [
        Text('Session id: ${session.id}'),
        const SizedBox(height: 8),
        Text('Host id: ${session.activeHost.id}'),
        const SizedBox(height: 8),
        Text('Attached Client: ${snapshot.attachedClientId}'),
        const SizedBox(height: 8),
        Text('Attached Clients: $attachedClientIds'),
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
