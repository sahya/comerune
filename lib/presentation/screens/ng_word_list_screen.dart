import 'package:flutter/material.dart';

import '../../application/settings/settings_store.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/ng_word_rule.dart';
import '../widgets/ng_local_notice.dart';
import '../widgets/text_input_dialog.dart';

/// Screen that displays and manages the list of NG word rules.
///
/// Users can add, toggle, and delete rules from this screen.
/// Changes are persisted via [SettingsStore].
class NgWordListScreen extends StatefulWidget {
  const NgWordListScreen({super.key, required this.settingsStore});

  final SettingsStore settingsStore;

  @override
  State<NgWordListScreen> createState() => _NgWordListScreenState();
}

class _NgWordListScreenState extends State<NgWordListScreen> {
  List<NgWordRule> _rules = const <NgWordRule>[];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  Future<void> _loadRules() async {
    final AppSettings settings = await widget.settingsStore.load();
    if (!mounted) {
      return;
    }
    setState(() {
      _rules = List<NgWordRule>.from(settings.ngWordRules);
      _isLoading = false;
    });
  }

  Future<void> _saveRules(List<NgWordRule> rules) async {
    final AppSettings current = await widget.settingsStore.load();
    final AppSettings updated = current.copyWith(ngWordRules: rules);
    await widget.settingsStore.save(updated);
    if (!mounted) {
      return;
    }
    setState(() {
      _rules = rules;
    });
  }

  Future<void> _toggleRule(int index) async {
    final List<NgWordRule> updated = List<NgWordRule>.from(_rules);
    final NgWordRule rule = updated[index];
    updated[index] = NgWordRule(pattern: rule.pattern, enabled: !rule.enabled);
    await _saveRules(updated);
  }

  Future<void> _deleteRule(int index) async {
    final NgWordRule rule = _rules[index];
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('NGワード削除'),
          content: Text('「${rule.pattern}」を削除しますか？'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('キャンセル'),
            ),
            TextButton(
              key: const Key('ng-word-delete-confirm-button'),
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

    final List<NgWordRule> updated = List<NgWordRule>.from(_rules)
      ..removeAt(index);
    await _saveRules(updated);

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('「${rule.pattern}」を削除しました')));
  }

  Future<void> _addRule() async {
    final String? input = await showTextInputDialog(
      context: context,
      title: 'NGワード追加',
      labelText: 'パターン（部分一致）',
      hintText: '例: スパム',
      textFieldKey: const Key('ng-word-add-input'),
      confirmButtonKey: const Key('ng-word-add-confirm-button'),
      confirmLabel: '追加',
    );

    if (input == null || input.isEmpty || !mounted) {
      return;
    }

    // Validate pattern syntax. Currently NG words are matched via
    // String.contains (substring match), but we validate as a regex
    // to reject obviously malformed input and for forward-compatibility.
    try {
      RegExp(input);
    } on FormatException {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('無効なパターンです')));
      return;
    }

    // Reject duplicate patterns.
    final bool duplicate = _rules.any((NgWordRule r) => r.pattern == input);
    if (duplicate) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('同じパターンが既に登録されています')));
      return;
    }

    final List<NgWordRule> updated = List<NgWordRule>.from(_rules)
      ..add(NgWordRule(pattern: input));
    await _saveRules(updated);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NGワード管理'),
        actions: <Widget>[
          IconButton(
            key: const Key('ng-word-add-button'),
            icon: const Icon(Icons.add),
            tooltip: 'NGワード追加',
            onPressed: _addRule,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const NgLocalNotice(key: Key('ng-word-local-notice')),
          const Divider(height: 1),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _rules.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        key: Key('ng-word-list-empty'),
                        'NGワードは登録されていません',
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
                  )
                : ListView.separated(
                    key: const Key('ng-word-list'),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _rules.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (BuildContext context, int index) {
                      final NgWordRule rule = _rules[index];
                      return ListTile(
                        key: Key('ng-word-tile-$index'),
                        leading: Switch(
                          key: Key('ng-word-toggle-$index'),
                          value: rule.enabled,
                          onChanged: (_) => _toggleRule(index),
                        ),
                        title: Text(
                          rule.pattern,
                          style: TextStyle(
                            fontSize: 14,
                            color: rule.enabled ? null : Colors.grey,
                          ),
                        ),
                        trailing: IconButton(
                          key: Key('ng-word-delete-$index'),
                          icon: const Icon(Icons.delete_outline),
                          tooltip: '削除',
                          onPressed: () => _deleteRule(index),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
