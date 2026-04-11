import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/application/settings/settings_store.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/presentation/mixins/settings_screen_mixin.dart';
import 'package:comerune/presentation/screens/comment_display_settings_screen.dart';

import '../../helpers/in_memory_shared_preferences.dart';

void main() {
  group('SettingsScreenMixin', () {
    group('error state', () {
      testWidgets('shows error UI when settingsStore.load() throws', (
        WidgetTester tester,
      ) async {
        final _ThrowingSettingsStore store = _ThrowingSettingsStore();

        await tester.pumpWidget(
          MaterialApp(home: _ErrorTestScreen(settingsStore: store)),
        );
        await tester.pumpAndSettle();

        expect(find.text('設定の読み込みに失敗しました'), findsOneWidget);
        expect(find.text('再試行'), findsOneWidget);
      });

      testWidgets('tapping retry clears error and retries load', (
        WidgetTester tester,
      ) async {
        final _ThrowingSettingsStore store = _ThrowingSettingsStore();

        await tester.pumpWidget(
          MaterialApp(home: _ErrorTestScreen(settingsStore: store)),
        );
        await tester.pumpAndSettle();

        // Error UI should be visible.
        expect(find.text('設定の読み込みに失敗しました'), findsOneWidget);

        // Make the store succeed on next load.
        store.shouldThrow = false;

        await tester.tap(find.text('再試行'));
        await tester.pumpAndSettle();

        // Error UI should be gone and settings should be loaded.
        expect(find.text('設定の読み込みに失敗しました'), findsNothing);
        expect(find.text('再試行'), findsNothing);
        expect(find.text('設定読み込み完了'), findsOneWidget);
      });
    });

    group('initialSettings', () {
      testWidgets(
        'uses initialSettings directly without calling loadSettings',
        (WidgetTester tester) async {
          final InMemorySharedPreferences prefs = InMemorySharedPreferences();
          final SharedPreferencesSettingsStore store =
              SharedPreferencesSettingsStore(prefs: prefs);

          // Store has default settings (showUserName = true).
          // Provide initialSettings with showUserName = false to verify
          // that the screen uses initialSettings and not the store.
          final AppSettings initial = AppSettings.defaults.copyWith(
            showUserName: false,
          );

          await tester.pumpWidget(
            MaterialApp(
              home: CommentDisplaySettingsScreen(
                settingsStore: store,
                initialSettings: initial,
              ),
            ),
          );
          await tester.pumpAndSettle();

          // The switch should reflect the provided initialSettings value.
          final SwitchListTile showNameTile = tester.widget(
            find.byKey(const Key('show-user-name-switch')),
          );
          expect(showNameTile.value, isFalse);
        },
      );
    });

    group('markChanged', () {
      testWidgets('markChanged sets hasChanges to true', (
        WidgetTester tester,
      ) async {
        final _ThrowingSettingsStore store = _ThrowingSettingsStore()
          ..shouldThrow = false;
        final GlobalKey<_ErrorTestScreenState> screenKey =
            GlobalKey<_ErrorTestScreenState>();

        await tester.pumpWidget(
          MaterialApp(
            home: _ErrorTestScreen(key: screenKey, settingsStore: store),
          ),
        );
        await tester.pumpAndSettle();

        // Before calling markChanged, hasChanges should be false.
        expect(screenKey.currentState!.publicHasChanges, isFalse);

        // Call markChanged directly.
        screenKey.currentState!.triggerMarkChanged();

        // After calling markChanged, hasChanges should be true.
        expect(screenKey.currentState!.publicHasChanges, isTrue);
      });
    });

    group('PopScope', () {
      testWidgets('returns false when no changes were made', (
        WidgetTester tester,
      ) async {
        final SharedPreferencesSettingsStore store =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

        bool? popResult;

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (BuildContext context) {
                return Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () async {
                        final bool? result = await Navigator.of(context)
                            .push<bool>(
                              MaterialPageRoute<bool>(
                                builder: (_) => CommentDisplaySettingsScreen(
                                  settingsStore: store,
                                ),
                              ),
                            );
                        popResult = result;
                      },
                      child: const Text('open'),
                    ),
                  ),
                );
              },
            ),
          ),
        );

        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        // Verify we are on the settings screen.
        expect(find.text('コメント表示設定'), findsOneWidget);

        // Navigate back without making changes.
        await tester.pageBack();
        await tester.pumpAndSettle();

        expect(popResult, isFalse);
      });

      testWidgets('returns true when changes were made via updateAndSave', (
        WidgetTester tester,
      ) async {
        final SharedPreferencesSettingsStore store =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

        bool? popResult;

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (BuildContext context) {
                return Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () async {
                        final bool? result = await Navigator.of(context)
                            .push<bool>(
                              MaterialPageRoute<bool>(
                                builder: (_) => CommentDisplaySettingsScreen(
                                  settingsStore: store,
                                ),
                              ),
                            );
                        popResult = result;
                      },
                      child: const Text('open'),
                    ),
                  ),
                );
              },
            ),
          ),
        );

        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        // Toggle a switch to trigger updateAndSave.
        final SwitchListTile tile = tester.widget(
          find.byKey(const Key('show-user-name-switch')),
        );
        tile.onChanged!.call(!tile.value);
        await tester.pumpAndSettle();

        // Navigate back.
        await tester.pageBack();
        await tester.pumpAndSettle();

        expect(popResult, isTrue);
      });
    });
  });
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// A settings store that throws on [load] when [shouldThrow] is true.
class _ThrowingSettingsStore implements SettingsStore {
  bool shouldThrow = true;

  final SharedPreferencesSettingsStore _delegate =
      SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

  @override
  Future<AppSettings> load() async {
    if (shouldThrow) {
      throw Exception('simulated load failure');
    }
    return _delegate.load();
  }

  @override
  Future<void> save(AppSettings settings) => _delegate.save(settings);

  @override
  double? loadPreMuteVolume() => _delegate.loadPreMuteVolume();

  @override
  Future<void> savePreMuteVolume(double? volume) =>
      _delegate.savePreMuteVolume(volume);

  @override
  Future<String> exportAsJson() => _delegate.exportAsJson();

  @override
  Future<AppSettings> importFromJson(String jsonString) =>
      _delegate.importFromJson(jsonString);
}

/// Minimal StatefulWidget that uses [SettingsScreenMixin] for testing
/// error state behaviour.
class _ErrorTestScreen extends StatefulWidget {
  const _ErrorTestScreen({super.key, required this.settingsStore});

  final SettingsStore settingsStore;

  @override
  State<_ErrorTestScreen> createState() => _ErrorTestScreenState();
}

class _ErrorTestScreenState extends State<_ErrorTestScreen>
    with SettingsScreenMixin {
  @override
  SettingsStore get settingsStore => widget.settingsStore;

  @override
  void initState() {
    super.initState();
    loadSettings();
  }

  /// Expose [markChanged] for testing.
  void triggerMarkChanged() => markChanged();

  /// Expose [hasChanges] for testing.
  bool get publicHasChanges => hasChanges;

  @override
  Widget build(BuildContext context) {
    if (settingsError != null) {
      return Scaffold(body: buildSettingsError(context));
    }
    if (settings == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return const Scaffold(body: Center(child: Text('設定読み込み完了')));
  }
}
