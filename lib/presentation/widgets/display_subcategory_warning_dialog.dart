import 'package:flutter/material.dart';

import '../../domain/models/ng_display_subcategory.dart';

/// Shows the warning dialog displayed every time the user flips a
/// "read-skipped comment visibility" toggle from OFF to ON.
///
/// The dialog is intentionally shown on every OFF→ON transition (not just the
/// first one) so the user is reminded of the streaming-overlay risk each time
/// they opt back in. See issue #615 for the rationale — there is intentionally
/// no "don't show again" checkbox.
///
/// Returns `true` when the user taps the confirm button, `false` otherwise
/// (cancel, back gesture, barrier dismiss, unmounted before completion).
///
/// [subcategory] selects the copy variant:
///   * [NgDisplaySubcategory.minors] uses the reinforced wording that calls
///     out the heightened platform-policy risk.
///   * All other subcategories use the standard wording.
///
/// Pure async helper — no state, no side effects beyond the dialog itself —
/// so tests can drive it without instantiating the settings screen.
Future<bool> showDisplaySubcategoryWarningDialog({
  required BuildContext context,
  required NgDisplaySubcategory subcategory,
}) async {
  final _DisplayWarningCopy copy = _copyFor(subcategory);
  final bool isMinors = subcategory == NgDisplaySubcategory.minors;
  final bool? result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (BuildContext dialogContext) {
      final ThemeData theme = Theme.of(dialogContext);
      // Use the AlertDialog icon slot (Material 3) so the warning is rendered
      // with proper layout instead of inline emoji in the title text.
      // Minors uses error color to convey heightened severity; the other
      // categories use the primary color so we don't over-stigmatize them.
      final Color iconColor = isMinors
          ? theme.colorScheme.error
          : theme.colorScheme.primary;
      return AlertDialog(
        key: const Key('display-subcategory-warning-dialog'),
        icon: Icon(Icons.warning_amber_rounded, color: iconColor, size: 32),
        title: Semantics(
          header: true,
          child: Text(copy.title, textAlign: TextAlign.center),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (int i = 0; i < copy.paragraphs.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(height: 12),
                Text(copy.paragraphs[i]),
              ],
              const SizedBox(height: 16),
              Text('（音声読み上げは引き続き行われません）', style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            key: const Key('display-subcategory-warning-cancel-button'),
            autofocus: true,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            key: const Key('display-subcategory-warning-confirm-button'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('有効化'),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

class _DisplayWarningCopy {
  const _DisplayWarningCopy({required this.title, required this.paragraphs});

  final String title;
  final List<String> paragraphs;
}

_DisplayWarningCopy _copyFor(NgDisplaySubcategory subcategory) {
  switch (subcategory) {
    case NgDisplaySubcategory.violence:
      return const _DisplayWarningCopy(
        title: '配信画面への映り込みに注意',
        paragraphs: <String>[
          '有効にすると、暴力表現を含むコメントが画面に表示されます。',
          '配信中は視聴者にこの内容が映る可能性があり、'
              '配信プラットフォームの規約に抵触する恐れもあります。',
        ],
      );
    case NgDisplaySubcategory.sexual:
      return const _DisplayWarningCopy(
        title: '配信画面への映り込みに注意',
        paragraphs: <String>[
          '有効にすると、性的表現を含むコメントが画面に表示されます。',
          '配信中は視聴者にこの内容が映る可能性があり、'
              '配信プラットフォームの規約に抵触する恐れもあります。',
        ],
      );
    case NgDisplaySubcategory.discrimination:
      return const _DisplayWarningCopy(
        title: '配信画面への映り込みに注意',
        paragraphs: <String>[
          '有効にすると、差別・ヘイト表現を含むコメントが画面に表示されます。',
          '配信中は視聴者にこの内容が映る可能性があり、'
              '配信プラットフォームの規約に抵触する恐れもあります。',
        ],
      );
    case NgDisplaySubcategory.minors:
      return const _DisplayWarningCopy(
        title: '未成年関連表現を含むコメントの表示',
        paragraphs: <String>[
          'このカテゴリには児童や未成年に関する不適切な表現が含まれる可能性があります。',
          'これらのコメントは表示しても法的問題にはなりませんが、'
              '配信中に映ると視聴者に強い不快感を与え、'
              '配信プラットフォームの規約違反となる可能性が他のカテゴリより高くなります。',
        ],
      );
  }
}

/// Display label for each subcategory. Delegates to the canonical
/// [NgDisplaySubcategory.displayLabelJa] getter so the dialog body, the
/// action-sheet banner and the settings toggles all share the exact same
/// phrasing (single source of truth lives on the enum).
String displaySubcategoryLabel(NgDisplaySubcategory subcategory) =>
    subcategory.displayLabelJa;
