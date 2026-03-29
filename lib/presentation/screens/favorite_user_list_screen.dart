import 'package:flutter/material.dart';

import '../../application/settings/settings_store.dart';
import '../../domain/models/app_settings.dart';

class FavoriteUserListScreen extends StatefulWidget {
  const FavoriteUserListScreen({
    super.key,
    required this.settingsStore,
  });

  final SettingsStore settingsStore;

  @override
  State<FavoriteUserListScreen> createState() => _FavoriteUserListScreenState();
}

class _FavoriteUserListScreenState extends State<FavoriteUserListScreen> {
  List<String> _favoriteUserIds = const <String>[];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFavoriteUserIds();
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

    final AppSettings current = await widget.settingsStore.load();
    final AppSettings updated = current.addFavoriteUserId(userId);
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
        SnackBar(content: Text('$userId を追加しました')),
      );
  }

  Future<void> _removeFavoriteUserId(String userId) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('ユーザー削除'),
          content: Text('ユーザーID「$userId」を削除しますか？'),
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
                    return ListTile(
                      key: Key('favorite-user-tile-$index'),
                      leading: const Icon(Icons.person, size: 20),
                      title: Text(
                        userId,
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
