import 'package:flutter/material.dart';

import '../../application/settings/settings_store.dart';
import '../../domain/models/app_settings.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/empty_state_message.dart';

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
    final bool? confirmed = await showConfirmDialog(
      context: context,
      title: 'NG解除',
      content: 'ユーザーID「$userId」のNG登録を解除しますか？',
      confirmLabel: '解除',
      confirmButtonKey: const Key('ng-remove-confirm-button'),
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
              ? const EmptyStateMessage(
                  key: Key('ng-user-list-empty'),
                  message: 'NGユーザーIDは登録されていません',
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
