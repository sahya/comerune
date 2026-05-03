import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import '../../data/filter/broadcaster_ng_store.dart';
import '../widgets/ng_local_notice.dart';
import 'broadcaster_ng_edit_screen.dart';

/// Issue #727: picker screen that lists every broadcaster the user has a
/// per-broadcaster NG slot for.
///
/// Tapping a row pushes [BroadcasterNgEditScreen] for that scope.
///
/// The template scope (seed for newly-encountered broadcasters) is an
/// internal concept and is intentionally NOT exposed as a tile here — the
/// migrator and `_ensureInitialized` paths use it implicitly.
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
  /// broadcaster ID. When null or returns null/empty, only the raw ID is
  /// shown; otherwise the tile title is rendered as `名前(ID)`.
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
      if (mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(const SnackBar(content: Text('放送者一覧の更新に失敗しました')));
      }
      return;
    }
    setState(() {
      _broadcasterIds = ids;
    });
  }

  void _openEditor(String? broadcasterId, String scopeLabel) {
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => BroadcasterNgEditScreen(
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

  /// Returns the resolved broadcaster name for [broadcasterId], or `null`
  /// when the resolver is missing or yields an empty / null value.
  String? _resolvedName(String broadcasterId) {
    final String? resolved = widget.broadcasterNameResolver?.call(
      broadcasterId,
    );
    if (resolved == null || resolved.isEmpty) {
      return null;
    }
    return resolved;
  }

  /// Tile title format: `名前(ID)` when the name is resolvable, raw `ID`
  /// otherwise. Avoids ever rendering `()` for empty / unknown names.
  String _displayTileTitle(String broadcasterId) {
    final String? name = _resolvedName(broadcasterId);
    if (name == null) {
      return broadcasterId;
    }
    return '$name($broadcasterId)';
  }

  /// Edit-screen scope label: just the **name** when known, the **ID**
  /// when not. The combined `name(id)` form is intentionally NOT used
  /// here — the AppBar shows just the broadcaster name to keep the title
  /// short and human-readable.
  String _editorScopeLabel(String broadcasterId) {
    return _resolvedName(broadcasterId) ?? broadcasterId;
  }

  @override
  Widget build(BuildContext context) {
    final ValueNotifier<String?>? notifier = widget.broadcasterIdNotifier;
    final ThemeData theme = Theme.of(context);

    Widget buildList(String? activeId) {
      final List<String> ids = _broadcasterIds;
      return RefreshIndicator(
        key: const Key('broadcaster-ng-list-refresh'),
        onRefresh: _refresh,
        child: ListView(
          key: const Key('broadcaster-ng-list-view'),
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: <Widget>[
            if (ids.isEmpty)
              Padding(
                key: const Key('broadcaster-ng-list-empty'),
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'まだ放送者ごとの NG 設定はありません',
                      style: TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'コメント画面で長押しして NG 登録すると、その放送者の設定として記録されます',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              )
            else
              ...List<Widget>.generate(ids.length, (int index) {
                final String id = ids[index];
                final bool isActive = activeId != null && activeId == id;
                final String title = _displayTileTitle(id);
                final String scopeLabel = _editorScopeLabel(id);
                return ListTile(
                  key: Key('broadcaster-ng-list-broadcaster-tile-$index'),
                  leading: const Icon(Icons.person),
                  title: Text(title),
                  subtitle: isActive
                      ? const Text(
                          '現在接続中',
                          key: Key('broadcaster-ng-active-badge'),
                        )
                      : null,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openEditor(id, scopeLabel),
                );
              }),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('NG フィルタ')),
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
