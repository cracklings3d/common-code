import 'package:common_code_domain/common_code_domain.dart';
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
    final turns = session.promptThread.turns;
    final authoringPresentation = _AuthoringPresentation.fromSnapshot(snapshot);

    return _SessionSection(
      title: 'Prompt Thread',
      children: [
        _SessionContextChrome(
          snapshot: snapshot,
          authoringPresentation: authoringPresentation,
        ),
        const SizedBox(height: 16),
        if (turns.isEmpty)
          const _PromptThreadEmptyState()
        else
          for (var index = 0; index < turns.length; index++) ...[
            _PromptThreadTurnCard(
              turn: turns[index],
              attachedClientId: snapshot.attachedClientId,
            ),
            if (index < turns.length - 1) const SizedBox(height: 12),
          ],
        const SizedBox(height: 16),
        _NextTurnComposer(
          draftController: draftController,
          onSubmitTurn: onSubmitTurn,
          isSubmitting: isSubmitting,
          authoringPresentation: authoringPresentation,
        ),
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

enum _AuthoringMode { available, crossClientReadOnly, localActiveTurnLockout }

final class _AuthoringPresentation {
  const _AuthoringPresentation._({
    required this.mode,
    this.currentInputClientId,
  });

  factory _AuthoringPresentation.fromSnapshot(DesktopSessionSnapshot snapshot) {
    final session = snapshot.session;
    final inputClientId = session.inputClient?.id;

    if (inputClientId == null) {
      return const _AuthoringPresentation._(mode: _AuthoringMode.available);
    }

    if (inputClientId == snapshot.attachedClientId) {
      return _AuthoringPresentation._(
        mode: _AuthoringMode.localActiveTurnLockout,
        currentInputClientId: inputClientId,
      );
    }

    return _AuthoringPresentation._(
      mode: _AuthoringMode.crossClientReadOnly,
      currentInputClientId: inputClientId,
    );
  }

  final _AuthoringMode mode;
  final String? currentInputClientId;

  bool get composerVisible => mode != _AuthoringMode.localActiveTurnLockout;

  bool get composerEnabled => mode == _AuthoringMode.available;

  String get modeLabel => switch (mode) {
    _AuthoringMode.available => 'available',
    _AuthoringMode.crossClientReadOnly =>
      'read-only while Client $currentInputClientId owns input',
    _AuthoringMode.localActiveTurnLockout =>
      'locked while this desktop client turn is queued or running',
  };

  String? get composerMessage => switch (mode) {
    _AuthoringMode.available => null,
    _AuthoringMode.crossClientReadOnly =>
      'This desktop presentation is read-only while Client '
          '$currentInputClientId owns input.',
    _AuthoringMode.localActiveTurnLockout =>
      'Next-turn authoring is unavailable while the current turn remains '
          'queued or running.',
  };
}

class _SessionContextChrome extends StatelessWidget {
  const _SessionContextChrome({
    required this.snapshot,
    required this.authoringPresentation,
  });

  final DesktopSessionSnapshot snapshot;
  final _AuthoringPresentation authoringPresentation;

  @override
  Widget build(BuildContext context) {
    final session = snapshot.session;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Session context',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Text('Local desktop Client: ${snapshot.attachedClientId}'),
          Text('Current Input Client: ${session.inputClient?.id ?? 'none'}'),
          Text('Authoring Mode: ${authoringPresentation.modeLabel}'),
          const SizedBox(height: 12),
          Text(
            'Attached Clients',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final client in session.clients)
                _AttachedClientChip(
                  clientId: client.id,
                  isLocal: client.id == snapshot.attachedClientId,
                  isInput: client.id == session.inputClient?.id,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AttachedClientChip extends StatelessWidget {
  const _AttachedClientChip({
    required this.clientId,
    required this.isLocal,
    required this.isInput,
  });

  final String clientId;
  final bool isLocal;
  final bool isInput;

  @override
  Widget build(BuildContext context) {
    final qualifiers = <String>[if (isLocal) 'local', if (isInput) 'input'];
    final label = qualifiers.isEmpty
        ? clientId
        : '$clientId (${qualifiers.join(', ')})';

    return Chip(label: Text(label));
  }
}

class _NextTurnComposer extends StatelessWidget {
  const _NextTurnComposer({
    required this.draftController,
    required this.onSubmitTurn,
    required this.isSubmitting,
    required this.authoringPresentation,
  });

  final TextEditingController draftController;
  final Future<void> Function() onSubmitTurn;
  final bool isSubmitting;
  final _AuthoringPresentation authoringPresentation;

  @override
  Widget build(BuildContext context) {
    final message = authoringPresentation.composerMessage;

    if (!authoringPresentation.composerVisible) {
      return Text(message!);
    }

    final isReadOnly = !authoringPresentation.composerEnabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (message != null) ...[Text(message), const SizedBox(height: 12)],
        TextField(
          controller: draftController,
          enabled: !isReadOnly,
          readOnly: isReadOnly,
          decoration: InputDecoration(
            labelText: isReadOnly ? 'Next Turn (read-only)' : 'Next Turn',
            border: const OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: isReadOnly || isSubmitting
              ? null
              : () async {
                  await onSubmitTurn();
                },
          child: Text(
            isSubmitting
                ? 'Submitting...'
                : isReadOnly
                ? 'Submit Turn (read-only)'
                : 'Submit Turn',
          ),
        ),
      ],
    );
  }
}

class _PromptThreadEmptyState extends StatelessWidget {
  const _PromptThreadEmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('No turns yet'),
          SizedBox(height: 8),
          Text('Submit the next turn to start this Prompt Thread.'),
        ],
      ),
    );
  }
}

class _PromptThreadTurnCard extends StatelessWidget {
  const _PromptThreadTurnCard({
    required this.turn,
    required this.attachedClientId,
  });

  final Turn turn;
  final String attachedClientId;

  @override
  Widget build(BuildContext context) {
    final isAttachedClientTurn = turn.clientId == attachedClientId;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isAttachedClientTurn
            ? Theme.of(context).colorScheme.surfaceContainerHighest
            : Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isAttachedClientTurn
                ? 'This desktop client'
                : 'Client ${turn.clientId}',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          Text(
            turn.submittedText,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text('Status: ${turn.status.name}'),
          if (turn.failureSummary case final String failureSummary) ...[
            const SizedBox(height: 8),
            Text('Failure: $failureSummary'),
          ],
        ],
      ),
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
