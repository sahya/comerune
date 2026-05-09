import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import '../../data/filter/broadcaster_ng_store.dart';
import '../../domain/models/ng_word_rule.dart';
import '../strings/app_strings.dart';
import '../widgets/ng_local_notice.dart';
import '../widgets/text_input_dialog.dart';

/// Issue #727: per-scope NG word management view.
///
/// When [broadcasterId] is null the view edits the template — the seed
/// list copied into any future broadcaster's first customization.
/// When non-null it edits the specific broadcaster's slot through
/// [BroadcasterNgStore].
///
/// This widget does **not** provide its own `Scaffold` / `AppBar`: it is
/// intended to be embedded inside [BroadcasterNgEditScreen] under a tab,
/// which owns the chrome.
class NgWordListView extends StatefulWidget {
  const NgWordListView({
    super.key,
    required this.broadcasterNgStore,
    required this.broadcasterId,
  });

  final BroadcasterNgStore broadcasterNgStore;

  /// `null` = template scope.
  final String? broadcasterId;

  @override
  State<NgWordListView> createState() => _NgWordListViewState();
}

class _NgWordListViewState extends State<NgWordListView> {
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
        'NgWordListView: failed to load NG word rules',
        name: 'ng_word_list_view',
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
    final NgWordListStrings strings = AppStrings.ngWordList;
    final NgWordRule rule = _rules[index];
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(strings.deleteDialogTitle),
          content: Text(strings.deleteDialogContent(rule.pattern)),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(strings.deleteDialogCancel),
            ),
            TextButton(
              key: const Key('ng-word-delete-confirm-button'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(strings.deleteDialogConfirm),
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
      ..showSnackBar(
        SnackBar(content: Text(strings.deletedSnackBar(rule.pattern))),
      );
  }

  Future<void> _addRule() async {
    final NgWordListStrings strings = AppStrings.ngWordList;
    final String? input = await showTextInputDialog(
      context: context,
      title: strings.addDialogTitle,
      labelText: strings.addDialogFieldLabel,
      hintText: strings.addDialogFieldHint,
      textFieldKey: const Key('ng-word-add-input'),
      confirmButtonKey: const Key('ng-word-add-confirm-button'),
      confirmLabel: strings.addDialogConfirm,
    );

    if (input == null || input.isEmpty || !mounted) {
      return;
    }

    // Validate pattern syntax. Currently NG words are matched via
    // String.contains (substring match), but we validate as a regex
    // to reject obviously malformed input and for forward-compatibility.
    try {
      RegExp(input);
    } on FormatException catch (e, st) {
      // The user-facing snackbar is intentionally vague ("無効なパターン
      // です") to avoid leaking regex parser internals (see
      // NgWordListStrings.invalidPatternSnackBar doc). Log the
      // FormatException to dev logs so the failure is debuggable in
      // local development without surfacing details to end users.
      developer.log(
        'NgWordListView: rejected invalid regex pattern',
        name: 'ng_word_list_view',
        error: e,
        stackTrace: st,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(strings.invalidPatternSnackBar)));
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
        ..showSnackBar(
          SnackBar(content: Text(strings.duplicatePatternSnackBar)),
        );
      return;
    }

    final List<NgWordRule> updated = List<NgWordRule>.from(_rules)
      ..add(NgWordRule(pattern: input));
    await _saveRules(updated);
  }

  @override
  Widget build(BuildContext context) {
    final NgWordListStrings strings = AppStrings.ngWordList;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const NgLocalNotice(key: Key('ng-word-local-notice')),
        const Divider(height: 1),
        // The "add" affordance lives inline at the top of the list, since
        // the parent screen's AppBar is shared across both tabs and a
        // FAB would require GlobalKey/ValueNotifier plumbing across the
        // tab boundary that exceeds the readability win.
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              key: const Key('ng-word-add-button'),
              onPressed: _addRule,
              icon: const Icon(Icons.add),
              label: Text(strings.addButton),
            ),
          ),
        ),
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
                        Text(
                          strings.loadFailedMessage,
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          key: const Key('ng-word-list-retry'),
                          onPressed: _loadRules,
                          child: Text(strings.retryButton),
                        ),
                      ],
                    ),
                  ),
                )
              : _rules.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      key: const Key('ng-word-list-empty'),
                      strings.emptyMessage,
                      style: const TextStyle(fontSize: 14),
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
                        tooltip: strings.deleteTooltip,
                        onPressed: () => _deleteRule(index),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
