import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import '../../data/filter/broadcaster_ng_store.dart';
import '../widgets/ng_local_notice.dart';
import 'broadcaster_ng_detail_screen.dart';

/// Issue #727: picker screen that lists every broadcaster the user has a
/// per-broadcaster NG slot for, plus a fixed "template" entry that seeds
/// any future broadcaster's first-access state.
///
/// Tapping a row pushes [BroadcasterNgDetailScreen] for that scope.
///
/// TODO(#727): broadcaster name resolution is out of scope for the initial
/// PR — tiles currently show the raw broadcaster ID. A follow-up issue
/// will plumb a resolver (e.g. `UserNameResolution`) so the picker can
/// display friendly names.
class BroadcasterNgListScreen extends StatefulWidget {
  const BroadcasterNgListScreen({
    super.key,
    required this.broadcasterNgStore,
    this.broadcasterIdNotifier,
    this.broadcasterNameResolver,
  });

  final BroadcasterNgStore broadcasterNgStore;

  /// When provided, the broadcaster currently held by this notifier is
  /// decorated with a 「現在接続中」 badge so the user can tell which slot
  /// long-press writes will land in.
  final ValueNotifier<String?>? broadcasterIdNotifier;

  /// Optional name resolver. Returns a display name for the given
  /// broadcaster ID. When null or returns null, the raw ID is shown.
  final String? Function(String broadcasterId)? broadcasterNameResolver;

  @override
  State<BroadcasterNgListScreen> createState() =>
      _BroadcasterNgListScreenState();
}

class _BroadcasterNgListScreenState extends State<BroadcasterNgListScreen> {
  late List<String> _broadcasterIds;

  @override
  void initState() {
    super.initState();
    _broadcasterIds = widget.broadcasterNgStore.listBroadcasters();
  }

  Future<void> _refresh() async {
    // Defensive: `listBroadcasters` is sync today and the in-tree
    // implementation can't throw, but harden against future
    // implementations / optional integrations by logging and falling
    // back to the previous list rather than blowing up the UI.
    List<String> ids;
    try {
      ids = widget.broadcasterNgStore.listBroadcasters();
    } on Object catch (e, st) {
      developer.log(
        'BroadcasterNgListScreen: listBroadcasters() failed; '
        'keeping previous list.',
        name: 'broadcaster_ng_list_screen',
        error: e,
        stackTrace: st,
      );
      return;
    }
    setState(() {
      _broadcasterIds = ids;
    });
  }

  void _openDetail(String? broadcasterId, String scopeLabel) {
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => BroadcasterNgDetailScreen(
              broadcasterNgStore: widget.broadcasterNgStore,
              broadcasterId: broadcasterId,
              scopeLabel: scopeLabel,
            ),
          ),
        )
        .then((_) {
          if (mounted) {
            _refresh();
          }
        });
  }

  String _displayName(String broadcasterId) {
    final String? resolved = widget.broadcasterNameResolver?.call(
      broadcasterId,
    );
    if (resolved != null && resolved.isNotEmpty) {
      return resolved;
    }
    return broadcasterId;
  }

  @override
  Widget build(BuildContext context) {
    final ValueNotifier<String?>? notifier = widget.broadcasterIdNotifier;

    Widget buildList(String? activeId) {
      final List<String> ids = _broadcasterIds;
      return RefreshIndicator(
        key: const Key('broadcaster-ng-list-refresh'),
        onRefresh: _refresh,
        child: ListView(
          key: const Key('broadcaster-ng-list-view'),
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: <Widget>[
            ListTile(
              key: const Key('broadcaster-ng-template-tile'),
              leading: const Icon(Icons.tune),
              title: const Text('テンプレート（新規放送者の初期値）'),
              subtitle: const Text('新しく見る放送者の初期値として使われます'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openDetail(null, 'テンプレート'),
            ),
            const Divider(height: 1),
            if (ids.isEmpty)
              const Padding(
                key: Key('broadcaster-ng-list-empty'),
                padding: EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'まだ放送者ごとの NG 設定はありません',
                      style: TextStyle(fontSize: 14),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'コメント画面で長押しして NG 登録すると、その放送者の設定として記録されます',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              )
            else
              ...List<Widget>.generate(ids.length, (int index) {
                final String id = ids[index];
                final bool isActive = activeId != null && activeId == id;
                final String name = _displayName(id);
                return ListTile(
                  key: Key('broadcaster-ng-list-broadcaster-tile-$index'),
                  leading: const Icon(Icons.person),
                  title: Text(name),
                  subtitle: isActive
                      ? const Text(
                          '現在接続中',
                          key: Key('broadcaster-ng-active-badge'),
                        )
                      : null,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openDetail(id, name),
                );
              }),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('放送者別 NG 一覧')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const NgLocalNotice(key: Key('broadcaster-ng-list-local-notice')),
          const Divider(height: 1),
          Expanded(
            child: notifier == null
                ? buildList(null)
                : ValueListenableBuilder<String?>(
                    valueListenable: notifier,
                    builder: (BuildContext context, String? activeId, _) {
                      return buildList(activeId);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
