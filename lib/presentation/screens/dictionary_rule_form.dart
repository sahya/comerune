import 'package:flutter/material.dart';

import '../../comment_speech/src/models/replace_rule.dart';

/// A form dialog for adding or editing a single [ReplaceRule].
///
/// When [rule] is null, the form is in "add" mode.
/// When [rule] is provided, the form is in "edit" mode and pre-fills the fields.
///
/// Returns the edited [ReplaceRule] via `Navigator.pop` on save,
/// or `null` on cancel.
class DictionaryRuleForm extends StatefulWidget {
  const DictionaryRuleForm({
    super.key,
    this.rule,
  });

  /// The rule to edit. `null` means adding a new rule.
  final ReplaceRule? rule;

  @override
  State<DictionaryRuleForm> createState() => _DictionaryRuleFormState();
}

class _DictionaryRuleFormState extends State<DictionaryRuleForm> {
  late final TextEditingController _patternController;
  late final TextEditingController _replacementController;
  late bool _enabled;
  String? _patternError;

  bool get _isEditing => widget.rule != null;

  @override
  void initState() {
    super.initState();
    _patternController = TextEditingController(
      text: widget.rule?.pattern ?? '',
    );
    _replacementController = TextEditingController(
      text: widget.rule?.replacement ?? '',
    );
    _enabled = widget.rule?.enabled ?? true;
  }

  @override
  void dispose() {
    _patternController.dispose();
    _replacementController.dispose();
    super.dispose();
  }

  /// Validates the pattern field as a valid regular expression.
  /// Returns `true` if valid.
  bool _validatePattern() {
    final String pattern = _patternController.text.trim();
    if (pattern.isEmpty) {
      setState(() {
        _patternError = 'パターンを入力してください';
      });
      return false;
    }
    try {
      RegExp(pattern);
      setState(() {
        _patternError = null;
      });
      return true;
    } on FormatException {
      setState(() {
        _patternError = '無効な正規表現パターンです';
      });
      return false;
    }
  }

  void _onSave() {
    if (!_validatePattern()) {
      return;
    }

    final ReplaceRule result = ReplaceRule(
      pattern: _patternController.text.trim(),
      replacement: _replacementController.text,
      enabled: _enabled,
    );
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'ルール編集' : 'ルール追加'),
        actions: <Widget>[
          TextButton(
            key: const Key('rule-form-save-button'),
            onPressed: _onSave,
            child: const Text('保存'),
          ),
        ],
      ),
      body: ListView(
        key: const Key('rule-form-body'),
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          TextFormField(
            key: const Key('rule-pattern-field'),
            controller: _patternController,
            decoration: InputDecoration(
              labelText: 'パターン（正規表現）',
              hintText: r'例: [wｗ]{3,}',
              border: const OutlineInputBorder(),
              errorText: _patternError,
            ),
            onEditingComplete: _validatePattern,
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const Key('rule-replacement-field'),
            controller: _replacementController,
            decoration: const InputDecoration(
              labelText: '読み',
              hintText: '例: わらわら',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            key: const Key('rule-enabled-switch'),
            title: const Text('有効'),
            contentPadding: EdgeInsets.zero,
            value: _enabled,
            onChanged: (bool value) {
              setState(() {
                _enabled = value;
              });
            },
          ),
        ],
      ),
    );
  }
}
