import 'package:flutter/material.dart';

import '../../domain/connection/connection_supervisor.dart';
import '../../domain/utils/lv_parser.dart';
import '../comment/comment_screen.dart';

class SelectScreen extends StatefulWidget {
  const SelectScreen({
    required this.connectionSupervisor,
    this.commentScreenBuilder,
    super.key,
  });

  final ConnectionSupervisor connectionSupervisor;
  final Widget Function(String lv)? commentScreenBuilder;

  @override
  State<SelectScreen> createState() => _SelectScreenState();
}

class _SelectScreenState extends State<SelectScreen> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _controller.addListener(_onInputChanged);
    widget.connectionSupervisor.addListener(_onSupervisorChanged);
  }

  @override
  void didUpdateWidget(covariant SelectScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectionSupervisor != widget.connectionSupervisor) {
      oldWidget.connectionSupervisor.removeListener(_onSupervisorChanged);
      widget.connectionSupervisor.addListener(_onSupervisorChanged);
    }
  }

  @override
  void dispose() {
    widget.connectionSupervisor.removeListener(_onSupervisorChanged);
    _controller
      ..removeListener(_onInputChanged)
      ..dispose();
    super.dispose();
  }

  void _onInputChanged() {
    setState(() {});
  }

  void _onSupervisorChanged() {
    setState(() {});
  }

  bool get _isConnectionInProgress {
    switch (widget.connectionSupervisor.status) {
      case ConnectionStatus.connectingSessionWs:
      case ConnectionStatus.resolvingEndpoints:
      case ConnectionStatus.streamingNdgr:
      case ConnectionStatus.streamingLegacy:
      case ConnectionStatus.reconnecting:
        return true;
      case ConnectionStatus.idle:
      case ConnectionStatus.stopped:
      case ConnectionStatus.ended:
      case ConnectionStatus.failed:
        return false;
    }
  }

  bool get _canAttemptConnection {
    if (_controller.text.trim().isEmpty || _isConnectionInProgress) {
      return false;
    }

    switch (widget.connectionSupervisor.status) {
      case ConnectionStatus.idle:
      case ConnectionStatus.stopped:
      case ConnectionStatus.failed:
      case ConnectionStatus.ended:
        return true;
      case ConnectionStatus.connectingSessionWs:
      case ConnectionStatus.resolvingEndpoints:
      case ConnectionStatus.streamingNdgr:
      case ConnectionStatus.streamingLegacy:
      case ConnectionStatus.reconnecting:
        return false;
    }
  }

  void _onSubmit(String _) {
    _connect();
  }

  void _connect() {
    if (!_canAttemptConnection) {
      return;
    }

    FocusScope.of(context).unfocus();

    final String? lv = LvParser.extract(_controller.text);
    if (lv == null) {
      widget.connectionSupervisor.recordError(ConnectionErrorCode.lvParseFailed);
      final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('放送IDが見つかりません')),
        );
      return;
    }

    final ConnectionStatus status = widget.connectionSupervisor.status;
    final bool started;
    if (status == ConnectionStatus.failed || status == ConnectionStatus.ended) {
      started = widget.connectionSupervisor.retryConnectionFromTerminal();
    } else {
      started = widget.connectionSupervisor.startConnection();
    }

    if (!started || !mounted) {
      return;
    }

    final Widget destination =
        widget.commentScreenBuilder?.call(lv) ??
        CommentScreen(
          lv: lv,
          connectionSupervisor: widget.connectionSupervisor,
        );

    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => destination),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('comerune')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              key: const Key('select_screen_input'),
              controller: _controller,
              enabled: !_isConnectionInProgress,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              onSubmitted: _onSubmit,
              decoration: const InputDecoration(
                hintText: 'lv番号またはURLを入力',
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                key: const Key('select_screen_connect_button'),
                onPressed: _canAttemptConnection ? _connect : null,
                child: const Text('接続開始'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
