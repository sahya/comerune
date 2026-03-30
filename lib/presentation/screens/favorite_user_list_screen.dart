import 'package:flutter/material.dart';

import '../../application/settings/settings_store.dart';
import '../../domain/models/app_settings.dart';

class FavoriteUserListScreen extends StatefulWidget {
  const FavoriteUserListScreen({
    super.key,
    required this.settingsStore,
    this.resolveUserName,
    this.requestUserNameResolve,
    this.userNameListenable,
  });

  final SettingsStore settingsStore;
  final String? Function(String userId)? resolveUserName;
  final void Function(String userId)? requestUserNameResolve;
  final Listenable? userNameListenable;

  @override
  State<FavoriteUserListScreen> createState() => _FavoriteUserListScreenState();
}

class _FavoriteUserListScreenState extends State<FavoriteUserListScreen> {
  List<String> _favoriteUserIds = const <String>[];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    widget.userNameListenable?.addListener(_onUserNameChanged);
    _loadFavoriteUserIds();
  }

  @override
  void didUpdateWidget(covariant FavoriteUserListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userNameListenable != widget.userNameListenable) {
      oldWidget.userNameListenable?.removeListener(_onUserNameChanged);
      widget.userNameListenable?.addListener(_onUserNameChanged);
    }
  }

  @override
  void dispose() {
    widget.userNameListenable?.removeListener(_onUserNameChanged);
    super.dispose();
  }

  void _onUserNameChanged() {
    setState(() {});
  }

  void _requestAllUserNameResolution() {
    final void Function(String)? request = widget.requestUserNameResolve;
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
    final TextEditingController controller = TextEditingController();
    final String? userId = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('ユーザーID追加'),
          content: TextField(
            key: const Key('favorite-user-id-input'),
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              hintText: 'ユーザーIDを入力',
            ),
            autofocus: true,
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('キャンセル'),
            ),
            TextButton(
              key: const Key('favorite-add-confirm-button'),
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('追加'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (userId == null || userId.isEmpty || !mounted) {
      return;
    }

    if (int.tryParse(userId) == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('ユーザーIDは数値で入力してください')),
        );
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

    widget.requestUserNameResolve?.call(userId);

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('$userId を追加しました')),
      );
  }

  Future<void> _removeFavoriteUserId(String userId) async {
    final String? nickname = widget.resolveUserName?.call(userId);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('ユーザー削除'),
          content: Text(
            nickname != null
                ? '$nickname（$userId）を削除しますか？'
                : 'ユーザーID「$userId」を削除しますか？',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('キャンセル'),
            ),
            TextButton(
              key: const Key('favorite-remove-confirm-button'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('削除'),
            ),
          ],
        );
      },
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
      ..showSnackBar(
        SnackBar(content: Text('$userId を削除しました')),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('お気に入りユーザー管理'),
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('favorite-add-button'),
        onPressed: _addFavoriteUserId,
        child: const Icon(Icons.person_add),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _favoriteUserIds.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      key: Key('favorite-user-list-empty'),
                      'お気に入りユーザーIDは登録されていません\n'
                      '右下のボタンからユーザーIDを追加すると\n'
                      '接続画面に放送中の番組が表示されます',
                      style: TextStyle(fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.separated(
                  key: const Key('favorite-user-id-list'),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _favoriteUserIds.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) {
                    final String userId = _favoriteUserIds[index];
                    final String? nickname =
                        widget.resolveUserName?.call(userId);
                    return ListTile(
                      key: Key('favorite-user-tile-$index'),
                      leading: const Icon(Icons.person, size: 20),
                      title: Text(
                        nickname != null ? '$nickname ($userId)' : userId,
                        style: const TextStyle(fontSize: 14),
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
