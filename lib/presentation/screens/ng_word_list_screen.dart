import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import '../../data/filter/broadcaster_ng_store.dart';
import '../../domain/models/ng_word_rule.dart';
import '../widgets/ng_local_notice.dart';
import '../widgets/text_input_dialog.dart';

/// Issue #727: per-scope NG word management.
///
/// When [broadcasterId] is null the screen edits the template — the seed
/// list copied into any future broadcaster's first-access state.
/// When non-null it edits the specific broadcaster's slot through
/// [BroadcasterNgStore].
class NgWordListScreen extends StatefulWidget {
  const NgWordListScreen({
    super.key,
    required this.broadcasterNgStore,
    required this.broadcasterId,
    required this.scopeLabel,
  });

  final BroadcasterNgStore broadcasterNgStore;

  /// `null` = template scope.
  final String? broadcasterId;

  final String scopeLabel;

  @override
  State<NgWordListScreen> createState() => _NgWordListScreenState();
}

class _NgWordListScreenState extends State<NgWordListScreen> {
  static const int _maxScopeTitleLength = 20;

  List<NgWordRule> _rules = const <NgWordRule>[];
  bool _isLoading = true;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  Future<List<NgWordRule>> _readRules() async {
    final String? broadcasterId = widget.broadcasterId;
    if (broadcasterId == null) {
      return widget.broadcasterNgStore.loadTemplateNgWordRules();
    }
    return widget.broadcasterNgStore.loadNgWordRules(broadcasterId);
  }

  Future<void> _writeRules(List<NgWordRule> rules) async {
    final String? broadcasterId = widget.broadcasterId;
    if (broadcasterId == null) {
      await widget.broadcasterNgStore.saveTemplateNgWordRules(rules);
    } else {
      await widget.broadcasterNgStore.saveNgWordRules(broadcasterId, rules);
    }
  }

  Future<void> _loadRules() async {
    if (_loadFailed || !_isLoading) {
      setState(() {
        _isLoading = true;
        _loadFailed = false;
      });
    }
    try {
      final List<NgWordRule> rules = await _readRules();
      if (!mounted) {
        return;
      }
      setState(() {
        _rules = List<NgWordRule>.from(rules);
        _isLoading = false;
        _loadFailed = false;
      });
    } on Object catch (e, st) {
      developer.log(
        'NgWordListScreen: failed to load NG word rules',
        name: 'ng_word_list_screen',
        error: e,
        stackTrace: st,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _saveRules(List<NgWordRule> rules) async {
    await _writeRules(rules);
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

  /// Keeps the AppBar title short for long broadcaster scope labels. The
  /// bottom subtitle keeps the full label.
  String _truncateForTitle(String label) {
    if (label.length <= _maxScopeTitleLength) {
      return label;
    }
    return '${label.substring(0, _maxScopeTitleLength)}…';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('NGワード — ${_truncateForTitle(widget.scopeLabel)}'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Padding(
            key: const Key('ng-word-scope-label'),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.broadcasterId == null
                    ? 'テンプレート（新規放送者の初期値）'
                    : 'スコープ: ${widget.scopeLabel}',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
        ),
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
                : _loadFailed
                ? Center(
                    key: const Key('ng-word-list-error'),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Text(
                            'NG リストの読込みに失敗しました',
                            style: TextStyle(fontSize: 14),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            key: const Key('ng-word-list-retry'),
                            onPressed: _loadRules,
                            child: const Text('再試行'),
                          ),
                        ],
                      ),
                    ),
                  )
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
