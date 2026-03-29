import 'package:flutter/material.dart';

import '../../application/settings/settings_store.dart';
import '../../domain/models/app_settings.dart';

class NgUserListScreen extends StatefulWidget {
  const NgUserListScreen({super.key, required this.settingsStore});

  final SettingsStore settingsStore;

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
    final AppSettings settings = await widget.settingsStore.load();
    if (!mounted) {
      return;
    }
    setState(() {
      _ngUserIds = settings.ngUserIdSet.toList();
      _isLoading = false;
    });
  }

  Future<void> _removeNgUserId(String userId) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('NG解除'),
          content: Text('ユーザーID「$userId」のNG登録を解除しますか？'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('キャンセル'),
            ),
            TextButton(
              key: const Key('ng-remove-confirm-button'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('解除'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    final AppSettings current = await widget.settingsStore.load();
    final AppSettings updated = current.removeNgUserId(userId);
    await widget.settingsStore.save(updated);

    if (!mounted) {
      return;
    }

    setState(() {
      _ngUserIds = updated.ngUserIdSet.toList();
    });

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$userId のNGを解除しました')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('NGユーザーID管理')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _ngUserIds.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  key: Key('ng-user-list-empty'),
                  'NGユーザーIDは登録されていません',
                  style: TextStyle(fontSize: 14),
                ),
              ),
            )
          : ListView.separated(
              key: const Key('ng-user-id-list'),
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _ngUserIds.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (BuildContext context, int index) {
                final String userId = _ngUserIds[index];
                return ListTile(
                  key: Key('ng-user-tile-$index'),
                  leading: const Icon(Icons.person_off, size: 20),
                  title: Text(userId, style: const TextStyle(fontSize: 14)),
                  trailing: IconButton(
                    key: Key('ng-user-remove-$index'),
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'NG解除',
                    onPressed: () => _removeNgUserId(userId),
                  ),
                );
              },
            ),
    );
  }
}
