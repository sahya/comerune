import 'package:flutter/material.dart';

import '../../data/user/user_attribute_store.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/empty_state_message.dart';

class NicknameListScreen extends StatefulWidget {
  const NicknameListScreen({
    super.key,
    required this.userAttributeStore,
    required this.broadcasterId,
  });

  final UserAttributeStore userAttributeStore;
  final String broadcasterId;

  @override
  State<NicknameListScreen> createState() => _NicknameListScreenState();
}

class _NicknameListScreenState extends State<NicknameListScreen> {
  Map<String, String> _nicknames = const <String, String>{};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNicknames();
  }

  Future<void> _loadNicknames() async {
    final Map<String, String> nicknames =
        await widget.userAttributeStore.loadNicknames(widget.broadcasterId);
    if (!mounted) {
      return;
    }
    setState(() {
      _nicknames = nicknames;
      _isLoading = false;
    });
  }

  Future<void> _editNickname(String userId, String currentNickname) async {
    final TextEditingController controller =
        TextEditingController(text: currentNickname);

    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('コテハン編集'),
          content: TextField(
            key: const Key('nickname-edit-field'),
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'コテハン',
              hintText: 'ニックネームを入力',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () => controller.clear(),
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('キャンセル'),
            ),
            TextButton(
              key: const Key('nickname-edit-save-button'),
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (result == null || !mounted) {
      return;
    }

    if (result.isEmpty) {
      await widget.userAttributeStore.removeNickname(
        broadcasterId: widget.broadcasterId,
        userId: userId,
      );
    } else {
      await widget.userAttributeStore.setNickname(
        broadcasterId: widget.broadcasterId,
        userId: userId,
        nickname: result,
      );
    }

    await _loadNicknames();
  }

  Future<void> _removeNickname(String userId) async {
    final bool? confirmed = await showConfirmDialog(
      context: context,
      title: 'コテハン削除',
      content: 'ユーザーID「$userId」のコテハンを削除しますか？',
      confirmButtonKey: const Key('nickname-remove-confirm-button'),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    await widget.userAttributeStore.removeNickname(
      broadcasterId: widget.broadcasterId,
      userId: userId,
    );
    await _loadNicknames();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('$userId のコテハンを削除しました')),
      );
  }

  @override
  Widget build(BuildContext context) {
    final List<MapEntry<String, String>> entries =
        _nicknames.entries.toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('コテハン管理'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : entries.isEmpty
              ? const EmptyStateMessage(
                  key: Key('nickname-list-empty'),
                  message: 'コテハンは登録されていません',
                )
              : ListView.separated(
                  key: const Key('nickname-list'),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) {
                    final MapEntry<String, String> entry = entries[index];
                    return ListTile(
                      key: Key('nickname-tile-$index'),
                      leading: const Icon(Icons.badge, size: 20),
                      title: Text(
                        entry.value,
                        style: const TextStyle(fontSize: 14),
                      ),
                      subtitle: Text(
                        'ID: ${entry.key}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          IconButton(
                            key: Key('nickname-edit-$index'),
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: '編集',
                            onPressed: () =>
                                _editNickname(entry.key, entry.value),
                          ),
                          IconButton(
                            key: Key('nickname-remove-$index'),
                            icon: const Icon(Icons.delete_outline),
                            tooltip: '削除',
                            onPressed: () => _removeNickname(entry.key),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
