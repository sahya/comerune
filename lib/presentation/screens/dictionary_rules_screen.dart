import 'package:flutter/material.dart';

import '../../application/settings/settings_store.dart';
import '../../comment_speech/src/models/replace_rule.dart';
import '../../domain/models/app_settings.dart';
import 'dictionary_rule_form.dart';

/// Screen that displays and manages the list of dictionary replacement rules.
///
/// Users can add, edit, toggle, and delete rules from this screen.
/// Changes are persisted via [SettingsStore].
class DictionaryRulesScreen extends StatefulWidget {
  const DictionaryRulesScreen({super.key, required this.settingsStore});

  final SettingsStore settingsStore;

  @override
  State<DictionaryRulesScreen> createState() => _DictionaryRulesScreenState();
}

class _DictionaryRulesScreenState extends State<DictionaryRulesScreen> {
  List<ReplaceRule> _rules = const <ReplaceRule>[];
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
      _rules = List<ReplaceRule>.from(settings.dictionaryRules);
      _isLoading = false;
    });
  }

  Future<void> _saveRules(List<ReplaceRule> rules) async {
    final AppSettings current = await widget.settingsStore.load();
    final AppSettings updated = current.copyWith(dictionaryRules: rules);
    await widget.settingsStore.save(updated);
    if (!mounted) {
      return;
    }
    setState(() {
      _rules = rules;
    });
  }

  Future<void> _toggleRule(int index) async {
    final List<ReplaceRule> updated = List<ReplaceRule>.from(_rules);
    final ReplaceRule rule = updated[index];
    updated[index] = ReplaceRule(
      pattern: rule.pattern,
      replacement: rule.replacement,
      enabled: !rule.enabled,
    );
    await _saveRules(updated);
  }

  Future<void> _deleteRule(int index) async {
    final ReplaceRule rule = _rules[index];
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('ルール削除'),
          content: Text('パターン「${rule.pattern}」を削除しますか？'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('キャンセル'),
            ),
            TextButton(
              key: const Key('rule-delete-confirm-button'),
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

    final List<ReplaceRule> updated = List<ReplaceRule>.from(_rules)
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
    final ReplaceRule? result = await Navigator.of(context).push(
      MaterialPageRoute<ReplaceRule>(
        builder: (_) => const DictionaryRuleForm(),
      ),
    );

    if (result == null || !mounted) {
      return;
    }

    final List<ReplaceRule> updated = List<ReplaceRule>.from(_rules)
      ..add(result);
    await _saveRules(updated);
  }

  Future<void> _editRule(int index) async {
    final ReplaceRule? result = await Navigator.of(context).push(
      MaterialPageRoute<ReplaceRule>(
        builder: (_) => DictionaryRuleForm(rule: _rules[index]),
      ),
    );

    if (result == null || !mounted) {
      return;
    }

    final List<ReplaceRule> updated = List<ReplaceRule>.from(_rules);
    updated[index] = result;
    await _saveRules(updated);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('読み上げ辞書'),
        actions: <Widget>[
          IconButton(
            key: const Key('dictionary-add-button'),
            icon: const Icon(Icons.add),
            tooltip: 'ルール追加',
            onPressed: _addRule,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _rules.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  key: Key('dictionary-rules-empty'),
                  '辞書ルールは登録されていません',
                  style: TextStyle(fontSize: 14),
                ),
              ),
            )
          : ListView.separated(
              key: const Key('dictionary-rules-list'),
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _rules.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (BuildContext context, int index) {
                final ReplaceRule rule = _rules[index];
                final bool isProtected = isDefaultNicoDictionaryRule(rule);
                return ListTile(
                  key: Key('dictionary-rule-tile-$index'),
                  leading: Switch(
                    key: Key('dictionary-rule-toggle-$index'),
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
                  subtitle: Text(
                    rule.replacement,
                    style: TextStyle(
                      fontSize: 12,
                      color: rule.enabled ? null : Colors.grey,
                    ),
                  ),
                  trailing: IconButton(
                    key: Key('dictionary-rule-delete-$index'),
                    icon: Icon(
                      isProtected ? Icons.lock_outline : Icons.delete_outline,
                    ),
                    tooltip: isProtected
                        ? '既定の辞書ルールは削除できません。設定画面で無効化してください'
                        : '削除',
                    onPressed: isProtected ? null : () => _deleteRule(index),
                  ),
                  onTap: isProtected ? null : () => _editRule(index),
                );
              },
            ),
    );
  }
}
