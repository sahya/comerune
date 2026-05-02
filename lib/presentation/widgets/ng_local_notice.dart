import 'package:flutter/material.dart';

/// Displays an in-screen notice clarifying that the NG list shown only
/// affects this app's local comment filtering and is **not** linked with
/// niconico's own NG features (e.g. broadcaster-side NG users / NG words).
///
/// Used on `NgUserListView` and `NgWordListView` to prevent users from
/// expecting their NG entries here to propagate to the niconico service.
class NgLocalNotice extends StatelessWidget {
  const NgLocalNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.info_outline,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
            semanticLabel: 'NG設定の範囲のお知らせ',
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'このNG設定はこのアプリ内のコメントフィルタにのみ使われます。'
              'ニコニコのサービスとは連携していません。',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
