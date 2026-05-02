import 'package:flutter/material.dart';

import '../../data/filter/broadcaster_ng_store.dart';
import 'ng_user_list_screen.dart';
import 'ng_word_list_screen.dart';

/// Issue #727: per-scope hub screen that exposes "NG users" and "NG words"
/// management for a single broadcaster (or the template seed).
///
/// `broadcasterId == null` means the template scope: edits there seed any
/// future broadcaster's first-access state.
class BroadcasterNgDetailScreen extends StatelessWidget {
  const BroadcasterNgDetailScreen({
    super.key,
    required this.broadcasterNgStore,
    required this.broadcasterId,
    required this.scopeLabel,
  });

  final BroadcasterNgStore broadcasterNgStore;

  /// `null` = template scope; non-null = a specific broadcaster's slot.
  final String? broadcasterId;

  /// Display label shown in the AppBar / banner. For broadcaster scopes
  /// this is typically the broadcaster ID (or a resolved name); for the
  /// template scope it should be a localized "テンプレート" or similar.
  final String scopeLabel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String bannerText = broadcasterId == null
        ? 'これはテンプレート（新規放送者の初期値）の編集です。既存の放送者には影響しません。'
        : 'この変更は「$scopeLabel」の NG 設定にのみ適用されます。';

    return Scaffold(
      appBar: AppBar(title: Text('NG設定 — $scopeLabel')),
      body: ListView(
        key: const Key('broadcaster-ng-detail-list'),
        children: <Widget>[
          Container(
            key: const Key('broadcaster-ng-detail-scope-banner'),
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: theme.colorScheme.surfaceContainerHighest,
            child: Text(bannerText, style: theme.textTheme.bodySmall),
          ),
          const Divider(height: 1),
          ListTile(
            key: const Key('broadcaster-ng-detail-users-tile'),
            leading: const Icon(Icons.person_off),
            title: const Text('NGユーザーID管理'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => NgUserListScreen(
                    broadcasterNgStore: broadcasterNgStore,
                    broadcasterId: broadcasterId,
                    scopeLabel: scopeLabel,
                  ),
                ),
              );
            },
          ),
          ListTile(
            key: const Key('broadcaster-ng-detail-words-tile'),
            leading: const Icon(Icons.block),
            title: const Text('NGワード管理'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => NgWordListScreen(
                    broadcasterNgStore: broadcasterNgStore,
                    broadcasterId: broadcasterId,
                    scopeLabel: scopeLabel,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
