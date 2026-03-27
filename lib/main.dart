import 'package:flutter/material.dart';

import 'domain/connection/connection_supervisor.dart';
import 'presentation/select/select_screen.dart';

void main() {
  runApp(const ComeruneApp());
}

class ComeruneApp extends StatefulWidget {
  const ComeruneApp({super.key});

  @override
  State<ComeruneApp> createState() => _ComeruneAppState();
}

class _ComeruneAppState extends State<ComeruneApp> {
  late final ConnectionSupervisor _connectionSupervisor =
      ConnectionSupervisor();

  @override
  void dispose() {
    _connectionSupervisor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'comerune',
      home: SelectScreen(connectionSupervisor: _connectionSupervisor),
    );
  }
}
