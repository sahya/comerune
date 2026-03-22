import 'package:flutter/material.dart';

import 'domain/connection/connection_supervisor.dart';
import 'presentation/select/select_screen.dart';

void main() {
  runApp(const ComeruneApp());
}

class ComeruneApp extends StatelessWidget {
  const ComeruneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'comerune',
      home: SelectScreen(connectionSupervisor: ConnectionSupervisor()),
    );
  }
}
