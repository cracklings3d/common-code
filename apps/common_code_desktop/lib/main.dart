import 'package:common_code_domain/common_code_domain.dart';
import 'package:flutter/material.dart';
import 'package:host_core/host_core.dart';

void main() {
  runApp(CommonCodeDesktopApp());
}

class CommonCodeDesktopApp extends StatelessWidget {
  CommonCodeDesktopApp({super.key, Session? sessionSnapshot})
    : sessionSnapshot = sessionSnapshot ?? bootstrapDesktopSessionSnapshot();

  final Session sessionSnapshot;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CommonCode Desktop',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: ScaffoldScreen(sessionSnapshot: sessionSnapshot),
    );
  }
}

Session bootstrapDesktopSessionSnapshot({HostService? hostService}) {
  final service = hostService ?? createInMemoryHostService();
  const sessionId = 'desktop-session';

  service.createSession(
    sessionId: sessionId,
    activeHost: const Host(id: 'desktop-host'),
  );
  service.attachClient(
    sessionId: sessionId,
    client: const Client(id: 'desktop-client'),
  );

  return service.readSession(sessionId);
}

class ScaffoldScreen extends StatelessWidget {
  const ScaffoldScreen({super.key, required this.sessionSnapshot});

  final Session sessionSnapshot;

  @override
  Widget build(BuildContext context) {
    final attachedClientIds = sessionSnapshot.clients
        .map((client) => client.id)
        .join(', ');

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('CommonCode Desktop'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Desktop host boundary proof',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              Text('Session id: ${sessionSnapshot.id}'),
              const SizedBox(height: 8),
              Text('Active host id: ${sessionSnapshot.activeHost.id}'),
              const SizedBox(height: 8),
              Text('Attached clients: ${sessionSnapshot.clients.length}'),
              const SizedBox(height: 8),
              Text('Attached client ids: $attachedClientIds'),
            ],
          ),
        ),
      ),
    );
  }
}
