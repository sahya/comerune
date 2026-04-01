import 'package:flutter/material.dart';

import '../../application/settings/settings_store.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/user_name_resolution.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/empty_state_message.dart';
import '../widgets/text_input_dialog.dart';

class FavoriteUserListScreen extends StatefulWidget {
  const FavoriteUserListScreen({
    super.key,
    required this.settingsStore,
    this.userNameResolution,
  });

  final SettingsStore settingsStore;
  final UserNameResolution? userNameResolution;

  @override
  State<FavoriteUserListScreen> createState() => _FavoriteUserListScreenState();
}

class _FavoriteUserListScreenState extends State<FavoriteUserListScreen> {
  List<String> _favoriteUserIds = const <String>[];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    widget.userNameResolution?.listenable.addListener(_onUserNameChanged);
    _loadFavoriteUserIds();
  }

  @override
  void didUpdateWidget(covariant FavoriteUserListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userNameResolution?.listenable !=
        widget.userNameResolution?.listenable) {
      oldWidget.userNameResolution?.listenable.removeListener(
        _onUserNameChanged,
      );
      widget.userNameResolution?.listenable.addListener(_onUserNameChanged);
    }
  }

  @override
  void dispose() {
    widget.userNameResolution?.listenable.removeListener(_onUserNameChanged);
    super.dispose();
  }

  void _onUserNameChanged() {
    setState(() {});
  }

  void _requestAllUserNameResolution() {
    final void Function(String)? request =
        widget.userNameResolution?.requestResolve;
    if (request == null) {
      return;
    }
    for (final String userId in _favoriteUserIds) {
      request(userId);
    }
  }

  Future<void> _loadFavoriteUserIds() async {
    final AppSettings settings = await widget.settingsStore.load();
    if (!mounted) {
      return;
    }
    setState(() {
      _favoriteUserIds = settings.favoriteUserIdSet.toList();
      _isLoading = false;
    });
    _requestAllUserNameResolution();
  }

  Future<void> _addFavoriteUserId() async {
    final String? userId = await showTextInputDialog(
      context: context,
      title: 'ユーザーID追加',
      hintText: 'ユーザーIDを入力',
      confirmLabel: '追加',
      textFieldKey: const Key('favorite-user-id-input'),
      confirmButtonKey: const Key('favorite-add-confirm-button'),
      keyboardType: TextInputType.number,
    );

    if (userId == null || userId.isEmpty || !mounted) {
      return;
    }

    if (int.tryParse(userId) == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('ユーザーIDは数値で入力してください')));
      return;
    }

    final AppSettings current = await widget.settingsStore.load();
    final AppSettings updated = current.addFavoriteUserId(userId);
    await widget.settingsStore.save(updated);

    if (!mounted) {
      return;
    }

    setState(() {
      _favoriteUserIds = updated.favoriteUserIdSet.toList();
    });

    widget.userNameResolution?.requestResolve(userId);

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$userId を追加しました')));
  }

  Future<void> _removeFavoriteUserId(String userId) async {
    final String? nickname = widget.userNameResolution?.resolve(userId);
    final bool? confirmed = await showConfirmDialog(
      context: context,
      title: 'ユーザー削除',
      content: nickname != null
          ? '$nickname ($userId) を削除しますか？'
          : 'ユーザーID「$userId」を削除しますか？',
      confirmLabel: '削除',
      confirmButtonKey: const Key('favorite-remove-confirm-button'),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    final AppSettings current = await widget.settingsStore.load();
    final AppSettings updated = current.removeFavoriteUserId(userId);
    await widget.settingsStore.save(updated);

    if (!mounted) {
      return;
    }

    setState(() {
      _favoriteUserIds = updated.favoriteUserIdSet.toList();
    });

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$userId を削除しました')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('お気に入りユーザー管理')),
      floatingActionButton: FloatingActionButton(
        key: const Key('favorite-add-button'),
        onPressed: _addFavoriteUserId,
        child: const Icon(Icons.person_add),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _favoriteUserIds.isEmpty
          ? const EmptyStateMessage(
              key: Key('favorite-user-list-empty'),
              message:
                  'お気に入りユーザーIDは登録されていません\n'
                  '右下のボタンからユーザーIDを追加すると\n'
                  '接続画面に放送中の番組が表示されます',
            )
          : ListView.separated(
              key: const Key('favorite-user-id-list'),
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _favoriteUserIds.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (BuildContext context, int index) {
                final String userId = _favoriteUserIds[index];
                final String? nickname = widget.userNameResolution?.resolve(
                  userId,
                );
                return ListTile(
                  key: Key('favorite-user-tile-$index'),
                  leading: const Icon(Icons.person, size: 20),
                  title: Text(
                    nickname != null ? '$nickname ($userId)' : userId,
                    style: const TextStyle(fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  trailing: IconButton(
                    key: Key('favorite-user-remove-$index'),
                    icon: const Icon(Icons.delete_outline),
                    tooltip: '削除',
                    onPressed: () => _removeFavoriteUserId(userId),
                  ),
                );
              },
            ),
    );
  }
}
