import 'package:common_code_domain/common_code_domain.dart';
import 'package:flutter/material.dart';
import 'package:host_core/host_core.dart';

void main() {
  runApp(const CommonCodeDesktopApp());
}

class CommonCodeDesktopApp extends StatelessWidget {
  const CommonCodeDesktopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CommonCode Desktop Scaffold',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: const ScaffoldScreen(),
    );
  }
}

class ScaffoldScreen extends StatelessWidget {
  const ScaffoldScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('CommonCode Desktop Scaffold'),
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
                'Windows-first Flutter workspace scaffold',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              Text('Domain package: ${commonCodeDomainDescriptor.label}'),
              const SizedBox(height: 8),
              Text('Host package: ${hostCoreDescriptor.label}'),
            ],
          ),
        ),
      ),
    );
  }
}
