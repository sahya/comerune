import 'package:flutter/material.dart';

import '../../data/filter/broadcaster_ng_store.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/empty_state_message.dart';
import '../widgets/ng_local_notice.dart';

/// Issue #727: per-scope NG user ID management.
///
/// When [broadcasterId] is null the screen edits the template — the seed
/// list copied into any future broadcaster's first-access state.
/// When non-null it edits the specific broadcaster's slot through
/// [BroadcasterNgStore].
///
/// TODO(#727): the existing screen historically only supports delete.
/// Adding a flow that lets users append a new NG user from this screen
/// is tracked in a follow-up issue; long-press on a comment in
/// [SelectScreen] remains the canonical "add" entry point for now.
class NgUserListScreen extends StatefulWidget {
  const NgUserListScreen({
    super.key,
    required this.broadcasterNgStore,
    required this.broadcasterId,
    required this.scopeLabel,
  });

  final BroadcasterNgStore broadcasterNgStore;

  /// `null` = template scope (seed for new broadcasters).
  final String? broadcasterId;

  /// Display label used in the AppBar subtitle / title.
  final String scopeLabel;

  @override
  State<NgUserListScreen> createState() => _NgUserListScreenState();
}

class _NgUserListScreenState extends State<NgUserListScreen> {
  List<String> _ngUserIds = const <String>[];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNgUserIds();
  }

  Future<void> _loadNgUserIds() async {
    final Set<String> ids = await _readIds();
    if (!mounted) {
      return;
    }
    setState(() {
      _ngUserIds = ids.toList();
      _isLoading = false;
    });
  }

  Future<Set<String>> _readIds() async {
    final String? broadcasterId = widget.broadcasterId;
    if (broadcasterId == null) {
      return widget.broadcasterNgStore.loadTemplateNgUserIds();
    }
    return widget.broadcasterNgStore.loadNgUserIds(broadcasterId);
  }

  Future<void> _removeNgUserId(String userId) async {
    final bool? confirmed = await showConfirmDialog(
      context: context,
      title: 'NG解除',
      content: 'ユーザーID「$userId」のNG登録を解除しますか？',
      confirmLabel: '解除',
      confirmButtonKey: const Key('ng-remove-confirm-button'),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    final String? broadcasterId = widget.broadcasterId;
    if (broadcasterId == null) {
      // Template scope: persist the filtered set verbatim.
      final Set<String> current = await widget.broadcasterNgStore
          .loadTemplateNgUserIds();
      final List<String> filtered = current
          .where((String id) => id != userId)
          .toList();
      await widget.broadcasterNgStore.saveTemplateNgUserIds(filtered);
    } else {
      await widget.broadcasterNgStore.removeNgUserId(broadcasterId, userId);
    }

    if (!mounted) {
      return;
    }

    final Set<String> updated = await _readIds();
    if (!mounted) {
      return;
    }

    setState(() {
      _ngUserIds = updated.toList();
    });

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$userId のNGを解除しました')));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('NGユーザーID — ${widget.scopeLabel}'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Padding(
            key: const Key('ng-user-scope-label'),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.broadcasterId == null
                    ? 'テンプレート（新規放送者の初期値）'
                    : 'スコープ: ${widget.scopeLabel}',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const NgLocalNotice(key: Key('ng-user-local-notice')),
          const Divider(height: 1),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _ngUserIds.isEmpty
                ? const EmptyStateMessage(
                    key: Key('ng-user-list-empty'),
                    message: 'NGユーザーIDは登録されていません',
                  )
                : ListView.separated(
                    key: const Key('ng-user-id-list'),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _ngUserIds.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (BuildContext context, int index) {
                      final String userId = _ngUserIds[index];
                      return ListTile(
                        key: Key('ng-user-tile-$index'),
                        leading: const Icon(Icons.person_off, size: 20),
                        title: Text(
                          userId,
                          style: const TextStyle(fontSize: 14),
                        ),
                        trailing: IconButton(
                          key: Key('ng-user-remove-$index'),
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'NG解除',
                          onPressed: () => _removeNgUserId(userId),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
