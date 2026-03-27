import 'package:flutter/material.dart';

import '../../domain/connection/connection_supervisor.dart';

class CommentScreen extends StatelessWidget {
  const CommentScreen({
    required this.lv,
    required this.connectionSupervisor,
    super.key,
  });

  final String lv;
  final ConnectionSupervisor connectionSupervisor;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(lv)),
      body: const Center(child: Text('CommentScreen')),
    );
  }
}
