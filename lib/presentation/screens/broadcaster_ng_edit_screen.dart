import 'package:flutter/material.dart';

import '../../data/filter/broadcaster_ng_store.dart';
import 'ng_user_list_view.dart';
import 'ng_word_list_view.dart';

/// Issue #727: per-scope NG editor with a tabbed UI for NG users / NG
/// words. Reachable from [BroadcasterNgListScreen] (the picker) — no
/// intermediate "hub" screen.
///
/// `broadcasterId == null` means the template scope: edits seed any
/// future broadcaster's first-access state. A small banner is shown in
/// that case so the user knows they are editing the seed list.
///
/// `scopeLabel` is the display name shown in the AppBar title (broadcaster
/// name or「テンプレート」).
class BroadcasterNgEditScreen extends StatelessWidget {
  const BroadcasterNgEditScreen({
    super.key,
    required this.broadcasterNgStore,
    required this.broadcasterId,
    required this.scopeLabel,
  });

  final BroadcasterNgStore broadcasterNgStore;

  /// `null` = template scope; non-null = a specific broadcaster's slot.
  final String? broadcasterId;

  /// Display label shown in the AppBar title.
  final String scopeLabel;

  static const int _maxScopeTitleLength = 20;

  /// Keeps the AppBar title short for long broadcaster scope labels.
  String _truncateForTitle(String label) {
    if (label.length <= _maxScopeTitleLength) {
      return label;
    }
    return '${label.substring(0, _maxScopeTitleLength)}…';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isTemplate = broadcasterId == null;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('NG設定 — ${_truncateForTitle(scopeLabel)}'),
          bottom: const TabBar(
            key: Key('broadcaster-ng-edit-tab-bar'),
            tabs: <Tab>[
              Tab(
                key: Key('broadcaster-ng-edit-users-tab'),
                icon: Icon(Icons.person_off),
                text: 'NGユーザー',
              ),
              Tab(
                key: Key('broadcaster-ng-edit-words-tab'),
                icon: Icon(Icons.block),
                text: 'NGワード',
              ),
            ],
          ),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (isTemplate)
              Container(
                key: const Key('broadcaster-ng-edit-template-banner'),
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: theme.colorScheme.surfaceContainerHighest,
                child: Text(
                  'テンプレート: 新規放送者の初期値として使われます',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            Expanded(
              child: TabBarView(
                key: const Key('broadcaster-ng-edit-tab-view'),
                children: <Widget>[
                  NgUserListView(
                    broadcasterNgStore: broadcasterNgStore,
                    broadcasterId: broadcasterId,
                  ),
                  NgWordListView(
                    broadcasterNgStore: broadcasterNgStore,
                    broadcasterId: broadcasterId,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
