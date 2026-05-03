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
    this.broadcasterNamesSnapshot,
  });

  final BroadcasterNgStore broadcasterNgStore;

  /// When provided, the broadcaster currently held by this notifier is
  /// decorated with a 「現在接続中」 badge so the user can tell which slot
  /// long-press writes will land in.
  final ValueNotifier<String?>? broadcasterIdNotifier;

  /// Optional name resolver. Returns a display name for the given
  /// broadcaster ID. When null or returns null/empty, only the raw ID is
  /// shown; otherwise the tile title is rendered as `名前(ID)`.
  ///
  /// Prefer wiring [broadcasterNamesSnapshot] when the underlying store can
  /// produce the full mapping cheaply: per-tile resolver calls re-parse
  /// SharedPreferences on every invocation, while a snapshot is read once
  /// per build and looked up in O(1).
  final String? Function(String broadcasterId)? broadcasterNameResolver;

  /// Optional thunk that returns a `broadcasterId → name` snapshot. Called
  /// once per build (and once per pull-to-refresh) so the picker can render
  /// names for every tile via O(1) map lookups instead of N resolver calls.
  ///
  /// When BOTH this and [broadcasterNameResolver] are provided, the snapshot
  /// wins. Embedders that only have a per-id resolver can keep passing
  /// [broadcasterNameResolver] for backward compatibility.
  final Map<String, String> Function()? broadcasterNamesSnapshot;

  @override
  State<BroadcasterNgListScreen> createState() =>
      _BroadcasterNgListScreenState();
}

class _BroadcasterNgListScreenState extends State<BroadcasterNgListScreen> {
  late List<String> _broadcasterIds;
  Map<String, String>? _namesSnapshot;

  @override
  void initState() {
    super.initState();
    _broadcasterIds = widget.broadcasterNgStore.listBroadcasters();
    _namesSnapshot = _readSnapshot();
  }

  /// Reads a fresh snapshot of `broadcasterId → name` mappings if the
  /// embedder supplied one. Failures are swallowed (with a log entry) so
  /// the picker can still render IDs even when the optional name source
  /// is unavailable.
  Map<String, String>? _readSnapshot() {
    final Map<String, String> Function()? thunk =
        widget.broadcasterNamesSnapshot;
    if (thunk == null) {
      return null;
    }
    try {
      return thunk();
    } on Object catch (e, st) {
      developer.log(
        'BroadcasterNgListScreen: names snapshot read failed; '
        'falling back to per-id resolver (if any).',
        name: 'broadcaster_ng_list_screen',
        error: e,
        stackTrace: st,
      );
      return null;
    }
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
    final Map<String, String>? snapshot = _readSnapshot();
    setState(() {
      _broadcasterIds = ids;
      _namesSnapshot = snapshot;
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
  /// when no source resolves it to a non-empty value.
  ///
  /// Resolution order:
  /// 1. The cached snapshot from [BroadcasterNgListScreen.broadcasterNamesSnapshot]
  ///    (O(1) map lookup; preferred when available).
  /// 2. The per-id resolver from [BroadcasterNgListScreen.broadcasterNameResolver]
  ///    (kept for backward compatibility with embedders that don't supply a
  ///    snapshot thunk).
  String? _resolvedName(String broadcasterId) {
    final Map<String, String>? snap = _namesSnapshot;
    if (snap != null) {
      final String? cached = snap[broadcasterId];
      if (cached == null || cached.isEmpty) {
        return null;
      }
      return cached;
    }
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
                  title: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
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
      appBar: AppBar(title: const Text('放送者別 NG 設定')),
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
