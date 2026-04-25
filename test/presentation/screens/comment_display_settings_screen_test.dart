import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/application/settings/settings_store.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/presentation/screens/comment_display_settings_screen.dart';
import 'package:comerune/presentation/strings/app_strings.dart';

import '../../helpers/in_memory_shared_preferences.dart';
import '../../helpers/settings_test_helpers.dart';

const Key _listKey = Key('comment-display-settings-list');

void main() {
  group('CommentDisplaySettingsScreen', () {
    testWidgets('toggles showUserName and persists value', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      // Default is true
      AppSettings loaded = await settingsStore.load();
      expect(loaded.showUserName, isTrue);

      await toggleSwitchByKey(
        tester,
        _listKey,
        const Key('show-user-name-switch'),
      );

      loaded = await settingsStore.load();
      expect(loaded.showUserName, isFalse);
    });

    testWidgets(
      'keeps resolveUserName switch enabled when showUserName is off',
      (WidgetTester tester) async {
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

        await tester.pumpWidget(_buildScreen(settingsStore));
        await tester.pumpAndSettle();

        // Turn off showUserName
        await toggleSwitchByKey(
          tester,
          _listKey,
          const Key('show-user-name-switch'),
        );

        // resolveUserName switch should remain enabled and be toggleable.
        final SwitchListTile resolveTile = tester.widget(
          find.byKey(
            const Key('resolve-user-name-switch'),
            skipOffstage: false,
          ),
        );
        expect(resolveTile.onChanged, isNotNull);

        AppSettings loaded = await settingsStore.load();
        expect(loaded.resolveUserName, isTrue);

        await toggleSwitchByKey(
          tester,
          _listKey,
          const Key('resolve-user-name-switch'),
        );
        loaded = await settingsStore.load();
        expect(loaded.resolveUserName, isFalse);
        expect(loaded.showUserName, isFalse);
      },
    );

    testWidgets('auto-save comment log toggle persists value when turned off', (
      WidgetTester tester,
    ) async {
      // Pre-set auto-save to ON so we can test turning it OFF
      // (turning ON requires a file picker which cannot be mocked easily).
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      await prefs.setBool('settings.comment.autoSaveCommentLog', true);
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: prefs);

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      // Verify initial state is ON
      AppSettings loaded = await settingsStore.load();
      expect(loaded.autoSaveCommentLog, isTrue);

      // Toggle OFF
      await toggleSwitchByKey(
        tester,
        _listKey,
        const Key('auto-save-comment-log-switch'),
      );

      loaded = await settingsStore.load();
      expect(loaded.autoSaveCommentLog, isFalse);
    });

    testWidgets('past comment count dropdown persists selected value', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      // Default should be count500 (initial fetch target).
      AppSettings loaded = await settingsStore.load();
      expect(loaded.pastCommentFetchCount, PastCommentFetchCount.count500);

      // Scroll to and open the dropdown. `ensureVisible` is called explicitly
      // after `scrollToKeyInList` so that later additions to the list do not
      // leave the dropdown partially clipped, which would cause the subsequent
      // tap to miss the hit-box.
      await scrollToKeyInList(
        tester,
        _listKey,
        const Key('past-comment-count-dropdown'),
      );
      await tester.ensureVisible(
        find.byKey(const Key('past-comment-count-dropdown')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('past-comment-count-dropdown')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      // Select '1000' option in the dropdown overlay. The default is now
      // 500, so selecting a different value proves the UI actually
      // persists a transition (not just re-selects the default).
      await tester.tap(find.text('1000').last);
      await tester.pumpAndSettle();

      loaded = await settingsStore.load();
      expect(loaded.pastCommentFetchCount, PastCommentFetchCount.count1000);
    });

    testWidgets(
      'past comment count dropdown shows description text below selector '
      '(#668)',
      (WidgetTester tester) async {
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

        await tester.pumpWidget(_buildScreen(settingsStore));
        await tester.pumpAndSettle();

        // Scroll the description into view so the assertion is not skipped
        // by offstage rendering (the list is long and the helper text sits
        // just below the selector).
        await scrollToKeyInList(
          tester,
          _listKey,
          const Key('past-comment-count-description'),
        );

        // The description must come from AppStrings (no hardcoded Japanese
        // in the screen file) and it must be rendered as a visible Text.
        // The buffer size is pulled from the domain constant so that
        // future changes to `timelineLiveCommentBufferSize` flow through
        // without editing the description string.
        expect(
          find.byKey(const Key('past-comment-count-description')),
          findsOneWidget,
        );
        expect(
          find.text(
            AppStrings.commentDisplaySettings.pastCommentFetchCountDescription(
              liveCommentBufferSize: timelineLiveCommentBufferSize,
            ),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('toggles commentTwoLineEnabled and persists value', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      AppSettings loaded = await settingsStore.load();
      expect(loaded.commentTwoLineEnabled, isFalse);

      await scrollToKeyInList(
        tester,
        _listKey,
        const Key('comment-two-line-switch'),
      );
      await toggleSwitchByKey(
        tester,
        _listKey,
        const Key('comment-two-line-switch'),
      );

      loaded = await settingsStore.load();
      expect(loaded.commentTwoLineEnabled, isTrue);
    });

    testWidgets('toggles commentZebraStripingEnabled and persists value', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      AppSettings loaded = await settingsStore.load();
      expect(loaded.commentZebraStripingEnabled, isFalse);

      await scrollToKeyInList(
        tester,
        _listKey,
        const Key('comment-zebra-striping-switch'),
      );
      await toggleSwitchByKey(
        tester,
        _listKey,
        const Key('comment-zebra-striping-switch'),
      );

      loaded = await settingsStore.load();
      expect(loaded.commentZebraStripingEnabled, isTrue);
    });

    testWidgets('toggles showOperatorComment and persists value', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      AppSettings loaded = await settingsStore.load();
      expect(loaded.showOperatorComment, isTrue);

      await expandExpansionTileByKey(
        tester,
        _listKey,
        const Key('message-type-expansion-tile'),
      );
      await toggleFilterChipByKey(
        tester,
        _listKey,
        const Key('show-operator-comment-chip'),
      );

      loaded = await settingsStore.load();
      expect(loaded.showOperatorComment, isFalse);
    });

    testWidgets('toggles showSystemMessage and persists value', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      AppSettings loaded = await settingsStore.load();
      expect(loaded.showSystemMessage, isTrue);

      await expandExpansionTileByKey(
        tester,
        _listKey,
        const Key('message-type-expansion-tile'),
      );
      await toggleFilterChipByKey(
        tester,
        _listKey,
        const Key('show-system-message-chip'),
      );

      loaded = await settingsStore.load();
      expect(loaded.showSystemMessage, isFalse);
    });

    testWidgets('toggles showEmotion and persists value', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      AppSettings loaded = await settingsStore.load();
      expect(loaded.showEmotion, isTrue);

      await expandExpansionTileByKey(
        tester,
        _listKey,
        const Key('message-type-expansion-tile'),
      );
      await toggleFilterChipByKey(
        tester,
        _listKey,
        const Key('show-emotion-chip'),
      );

      loaded = await settingsStore.load();
      expect(loaded.showEmotion, isFalse);
    });

    testWidgets('toggles showGiftComment and persists value (default ON)', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      AppSettings loaded = await settingsStore.load();
      expect(loaded.showGiftComment, isTrue);

      await expandExpansionTileByKey(
        tester,
        _listKey,
        const Key('message-type-expansion-tile'),
      );
      await toggleFilterChipByKey(
        tester,
        _listKey,
        const Key('show-gift-comment-chip'),
      );

      loaded = await settingsStore.load();
      expect(loaded.showGiftComment, isFalse);
    });

    testWidgets('toggles showNicoadComment and persists value (default ON)', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      AppSettings loaded = await settingsStore.load();
      expect(loaded.showNicoadComment, isTrue);

      await expandExpansionTileByKey(
        tester,
        _listKey,
        const Key('message-type-expansion-tile'),
      );
      await toggleFilterChipByKey(
        tester,
        _listKey,
        const Key('show-nicoad-comment-chip'),
      );

      loaded = await settingsStore.load();
      expect(loaded.showNicoadComment, isFalse);
    });

    testWidgets(
      'message type subtitle shows enabled count and updates on toggle',
      (WidgetTester tester) async {
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

        await tester.pumpWidget(_buildScreen(settingsStore));
        await tester.pumpAndSettle();

        await scrollToKeyInList(
          tester,
          _listKey,
          const Key('message-type-expansion-tile'),
        );

        expect(find.text('5 / 5 表示中'), findsOneWidget);

        await expandExpansionTileByKey(
          tester,
          _listKey,
          const Key('message-type-expansion-tile'),
        );
        await toggleFilterChipByKey(
          tester,
          _listKey,
          const Key('show-operator-comment-chip'),
        );

        expect(find.text('4 / 5 表示中'), findsOneWidget);
      },
    );

    testWidgets(
      'toggles emphasizeGiftNicoadComment and persists value (default ON)',
      (WidgetTester tester) async {
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

        await tester.pumpWidget(_buildScreen(settingsStore));
        await tester.pumpAndSettle();

        // Default must be ON.
        AppSettings loaded = await settingsStore.load();
        expect(loaded.emphasizeGiftNicoadComment, isTrue);

        await scrollToKeyInList(
          tester,
          _listKey,
          const Key('emphasize-gift-nicoad-switch'),
        );
        await toggleSwitchByKey(
          tester,
          _listKey,
          const Key('emphasize-gift-nicoad-switch'),
        );

        loaded = await settingsStore.load();
        expect(loaded.emphasizeGiftNicoadComment, isFalse);
      },
    );

    testWidgets('disables statistics child toggles when parent toggle is off', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      // Parent is off by default; child toggles should be disabled.
      await scrollToKeyInList(
        tester,
        _listKey,
        const Key('statistics-viewer-comment-switch'),
      );
      SwitchListTile viewerTile = tester.widget(
        find.byKey(
          const Key('statistics-viewer-comment-switch'),
          skipOffstage: false,
        ),
      );
      expect(viewerTile.onChanged, isNull);

      await scrollToKeyInList(
        tester,
        _listKey,
        const Key('statistics-active-user-switch'),
      );
      SwitchListTile activeTile = tester.widget(
        find.byKey(
          const Key('statistics-active-user-switch'),
          skipOffstage: false,
        ),
      );
      expect(activeTile.onChanged, isNull);

      // Turn on parent.
      await toggleSwitchByKey(
        tester,
        _listKey,
        const Key('statistics-enabled-switch'),
      );

      // Child toggles should now be enabled.
      await scrollToKeyInList(
        tester,
        _listKey,
        const Key('statistics-viewer-comment-switch'),
      );
      viewerTile = tester.widget(
        find.byKey(
          const Key('statistics-viewer-comment-switch'),
          skipOffstage: false,
        ),
      );
      expect(viewerTile.onChanged, isNotNull);

      await scrollToKeyInList(
        tester,
        _listKey,
        const Key('statistics-active-user-switch'),
      );
      activeTile = tester.widget(
        find.byKey(
          const Key('statistics-active-user-switch'),
          skipOffstage: false,
        ),
      );
      expect(activeTile.onChanged, isNotNull);
    });
  });

  _ngDisplayToggleTests();
}

/// Per-subcategory test parameters so the same ON/OFF flow runs against
/// all four toggles without duplicating assertions.
class _NgToggleCase {
  const _NgToggleCase({
    required this.name,
    required this.toggleKey,
    required this.prefsKey,
    required this.isOn,
  });

  final String name;
  final Key toggleKey;
  final String prefsKey;
  final bool Function(AppSettings s) isOn;
}

const List<_NgToggleCase> _ngToggleCases = <_NgToggleCase>[
  _NgToggleCase(
    name: 'violence',
    toggleKey: Key('show-violent-comment-switch'),
    prefsKey: 'settings.comment.showViolentComment',
    isOn: _violenceOn,
  ),
  _NgToggleCase(
    name: 'sexual',
    toggleKey: Key('show-sexual-comment-switch'),
    prefsKey: 'settings.comment.showSexualComment',
    isOn: _sexualOn,
  ),
  _NgToggleCase(
    name: 'discrimination',
    toggleKey: Key('show-discrimination-comment-switch'),
    prefsKey: 'settings.comment.showDiscriminationComment',
    isOn: _discriminationOn,
  ),
  _NgToggleCase(
    name: 'minors',
    toggleKey: Key('show-minors-comment-switch'),
    prefsKey: 'settings.comment.showMinorsRelatedComment',
    isOn: _minorsOn,
  ),
];

bool _violenceOn(AppSettings s) => s.showViolentComment;
bool _sexualOn(AppSettings s) => s.showSexualComment;
bool _discriminationOn(AppSettings s) => s.showDiscriminationComment;
bool _minorsOn(AppSettings s) => s.showMinorsRelatedComment;

void _ngDisplayToggleTests() {
  group('NG display toggles (#615)', () {
    testWidgets('expansion tile is collapsed initially', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('show-violent-comment-switch')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('ng-display-expansion-tile')),
        findsOneWidget,
      );
    });

    testWidgets('expansion tile can be opened to reveal all 4 toggles', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      await expandExpansionTileByKey(
        tester,
        _listKey,
        const Key('ng-display-expansion-tile'),
      );

      for (final _NgToggleCase tc in _ngToggleCases) {
        expect(
          find.byKey(tc.toggleKey),
          findsOneWidget,
          reason: '${tc.name} toggle must render when expanded',
        );
      }
    });

    testWidgets('all 4 toggles default to OFF in AppSettings', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      final AppSettings loaded = await settingsStore.load();
      for (final _NgToggleCase tc in _ngToggleCases) {
        expect(tc.isOn(loaded), isFalse, reason: tc.name);
      }
    });

    testWidgets('subtitle shows "0 / 4 表示中" when all off', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      await scrollToKeyInList(
        tester,
        _listKey,
        const Key('ng-display-expansion-tile'),
      );

      expect(find.textContaining('0 / 4 表示中'), findsOneWidget);
    });

    for (final _NgToggleCase tc in _ngToggleCases) {
      testWidgets(
        '${tc.name}: OFF->ON shows the warning dialog (not persisted yet)',
        (WidgetTester tester) async {
          final SharedPreferencesSettingsStore settingsStore =
              SharedPreferencesSettingsStore(
                prefs: InMemorySharedPreferences(),
              );

          await tester.pumpWidget(_buildScreen(settingsStore));
          await tester.pumpAndSettle();

          await expandExpansionTileByKey(
            tester,
            _listKey,
            const Key('ng-display-expansion-tile'),
          );
          await toggleSwitchByKey(tester, _listKey, tc.toggleKey);
          await tester.pumpAndSettle();

          expect(
            find.byKey(const Key('display-subcategory-warning-dialog')),
            findsOneWidget,
          );
          final AppSettings mid = await settingsStore.load();
          expect(tc.isOn(mid), isFalse);
        },
      );

      testWidgets('${tc.name}: cancelling the dialog keeps the toggle OFF', (
        WidgetTester tester,
      ) async {
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

        await tester.pumpWidget(_buildScreen(settingsStore));
        await tester.pumpAndSettle();

        await expandExpansionTileByKey(
          tester,
          _listKey,
          const Key('ng-display-expansion-tile'),
        );
        await toggleSwitchByKey(tester, _listKey, tc.toggleKey);
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('display-subcategory-warning-cancel-button')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('display-subcategory-warning-dialog')),
          findsNothing,
        );
        final AppSettings loaded = await settingsStore.load();
        expect(tc.isOn(loaded), isFalse);
      });

      testWidgets('${tc.name}: confirming the dialog persists ON', (
        WidgetTester tester,
      ) async {
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

        await tester.pumpWidget(_buildScreen(settingsStore));
        await tester.pumpAndSettle();

        await expandExpansionTileByKey(
          tester,
          _listKey,
          const Key('ng-display-expansion-tile'),
        );
        await toggleSwitchByKey(tester, _listKey, tc.toggleKey);
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('display-subcategory-warning-confirm-button')),
        );
        await tester.pumpAndSettle();

        final AppSettings loaded = await settingsStore.load();
        expect(tc.isOn(loaded), isTrue);
      });

      testWidgets(
        '${tc.name}: ON->OFF does not show the dialog and persists immediately',
        (WidgetTester tester) async {
          final InMemorySharedPreferences prefs = InMemorySharedPreferences();
          await prefs.setBool(tc.prefsKey, true);
          final SharedPreferencesSettingsStore settingsStore =
              SharedPreferencesSettingsStore(prefs: prefs);

          await tester.pumpWidget(_buildScreen(settingsStore));
          await tester.pumpAndSettle();

          await expandExpansionTileByKey(
            tester,
            _listKey,
            const Key('ng-display-expansion-tile'),
          );
          await toggleSwitchByKey(tester, _listKey, tc.toggleKey);
          await tester.pumpAndSettle();

          expect(
            find.byKey(const Key('display-subcategory-warning-dialog')),
            findsNothing,
            reason: 'ON->OFF must never show the warning dialog',
          );
          final AppSettings loaded = await settingsStore.load();
          expect(tc.isOn(loaded), isFalse);
        },
      );
    }

    testWidgets('minors dialog shows the reinforced 強化版 wording', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      await expandExpansionTileByKey(
        tester,
        _listKey,
        const Key('ng-display-expansion-tile'),
      );
      await toggleSwitchByKey(
        tester,
        _listKey,
        const Key('show-minors-comment-switch'),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('児童や未成年に関する不適切な表現'), findsOneWidget);
    });

    testWidgets('non-minors dialog uses the 通常版 wording', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      await expandExpansionTileByKey(
        tester,
        _listKey,
        const Key('ng-display-expansion-tile'),
      );
      await toggleSwitchByKey(
        tester,
        _listKey,
        const Key('show-violent-comment-switch'),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('配信画面への映り込みに注意'), findsOneWidget);
      expect(find.textContaining('児童や未成年'), findsNothing);
    });

    testWidgets('subtitle count updates after confirming one toggle', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      await expandExpansionTileByKey(
        tester,
        _listKey,
        const Key('ng-display-expansion-tile'),
      );
      await toggleSwitchByKey(
        tester,
        _listKey,
        const Key('show-violent-comment-switch'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('display-subcategory-warning-confirm-button')),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('1 / 4 表示中'), findsOneWidget);
    });
  });
}

Widget _buildScreen(SettingsStore settingsStore) {
  return MaterialApp(
    home: CommentDisplaySettingsScreen(settingsStore: settingsStore),
  );
}
