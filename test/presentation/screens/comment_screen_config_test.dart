import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/presentation/screens/comment_screen_config.dart';

/// Regression tests for the `CommentFilterConfig` -> `ContentFilterConfig` +
/// `MessageTypeVisibilityConfig` split (issue #457).
///
/// The split changes only the in-memory widget parameter shape, not the
/// persistence format (AppSettings SharedPreferences keys are untouched).
/// These tests pin down the defaults and field distribution so a future
/// change cannot silently drift either class away from the pre-split
/// behavior, and so users who export their settings on a pre-split build
/// and import them on a post-split build continue to observe identical
/// defaults for any key that happened to be absent from their export.
void main() {
  group(
    'ContentFilterConfig defaults (backward compatibility with pre-split)',
    () {
      test(
        'matches pre-split CommentFilterConfig defaults bit-identically',
        () {
          const ContentFilterConfig filter = ContentFilterConfig();

          expect(filter.ngUserIds, isEmpty);
          expect(filter.ngWords, isEmpty);
          expect(filter.presetNgWords, isEmpty);
          expect(filter.starPrefixHidingEnabled, isFalse);
          expect(filter.slashPrefixSkipEnabled, isTrue);
          expect(filter.emphasizeGiftNicoadComment, isTrue);
          expect(filter.userColorMap, isEmpty);
          expect(filter.userNicknameMap, isEmpty);
          expect(filter.ngProtectionNotificationEnabled, isFalse);
        },
      );

      test('non-default values are preserved', () {
        const ContentFilterConfig filter = ContentFilterConfig(
          ngUserIds: <String>{'u1', 'u2'},
          ngWords: <String>['spam'],
          presetNgWords: <String>['preset'],
          starPrefixHidingEnabled: true,
          slashPrefixSkipEnabled: false,
          emphasizeGiftNicoadComment: false,
          userColorMap: <String, int>{'u1': 0xFF0000FF},
          userNicknameMap: <String, String>{'u1': 'nick'},
          ngProtectionNotificationEnabled: true,
        );

        expect(filter.ngUserIds, <String>{'u1', 'u2'});
        expect(filter.ngWords, <String>['spam']);
        expect(filter.presetNgWords, <String>['preset']);
        expect(filter.starPrefixHidingEnabled, isTrue);
        expect(filter.slashPrefixSkipEnabled, isFalse);
        expect(filter.emphasizeGiftNicoadComment, isFalse);
        expect(filter.userColorMap, <String, int>{'u1': 0xFF0000FF});
        expect(filter.userNicknameMap, <String, String>{'u1': 'nick'});
        expect(filter.ngProtectionNotificationEnabled, isTrue);
      });
    },
  );

  group(
    'MessageTypeVisibilityConfig defaults (backward compatibility with pre-split)',
    () {
      test(
        'matches pre-split CommentFilterConfig defaults bit-identically',
        () {
          const MessageTypeVisibilityConfig vis = MessageTypeVisibilityConfig();

          expect(vis.showOperatorComment, isTrue);
          expect(vis.showSystemMessage, isTrue);
          expect(vis.showEmotion, isTrue);
          expect(vis.showGiftComment, isTrue);
          expect(vis.showNicoadComment, isTrue);
        },
      );

      test('non-default values are preserved', () {
        const MessageTypeVisibilityConfig vis = MessageTypeVisibilityConfig(
          showOperatorComment: false,
          showSystemMessage: false,
          showEmotion: false,
          showGiftComment: false,
          showNicoadComment: false,
        );

        expect(vis.showOperatorComment, isFalse);
        expect(vis.showSystemMessage, isFalse);
        expect(vis.showEmotion, isFalse);
        expect(vis.showGiftComment, isFalse);
        expect(vis.showNicoadComment, isFalse);
      });
    },
  );

  group('Field distribution across the split', () {
    test('ContentFilterConfig carries content/user-based filter fields', () {
      // Compile-time cross-check: these accessors must exist on
      // ContentFilterConfig. If any is moved, this test fails to compile.
      const ContentFilterConfig filter = ContentFilterConfig();
      // ignore: unnecessary_statements
      filter.ngUserIds;
      // ignore: unnecessary_statements
      filter.ngWords;
      // ignore: unnecessary_statements
      filter.presetNgWords;
      // ignore: unnecessary_statements
      filter.starPrefixHidingEnabled;
      // ignore: unnecessary_statements
      filter.slashPrefixSkipEnabled;
      // ignore: unnecessary_statements
      filter.emphasizeGiftNicoadComment;
      // ignore: unnecessary_statements
      filter.userColorMap;
      // ignore: unnecessary_statements
      filter.userNicknameMap;
      // ignore: unnecessary_statements
      filter.ngProtectionNotificationEnabled;
    });

    test(
      'MessageTypeVisibilityConfig carries message-type display toggles',
      () {
        const MessageTypeVisibilityConfig vis = MessageTypeVisibilityConfig();
        // ignore: unnecessary_statements
        vis.showOperatorComment;
        // ignore: unnecessary_statements
        vis.showSystemMessage;
        // ignore: unnecessary_statements
        vis.showEmotion;
        // ignore: unnecessary_statements
        vis.showGiftComment;
        // ignore: unnecessary_statements
        vis.showNicoadComment;
      },
    );
  });
}
