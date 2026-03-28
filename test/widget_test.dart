import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/application/settings/settings_store.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/main.dart';

void main() {
  testWidgets('ComeruneApp boots to select screen',
      (WidgetTester tester) async {
    final SettingsStore settingsStore = SharedPreferencesSettingsStore(
      prefs: _InMemorySharedPreferences(),
    );

    await tester.pumpWidget(
      ComeruneApp(
        settingsStore: settingsStore,
        initialSettings: AppSettings.defaults,
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('select_screen_input')), findsOneWidget);
    expect(
      find.byKey(const Key('select_screen_connect_button')),
      findsOneWidget,
    );
    expect(find.text('接続開始'), findsOneWidget);
  });
}

class _InMemorySharedPreferences implements SharedPreferencesLike {
  final Map<String, Object> _values = <String, Object>{};

  @override
  bool? getBool(String key) => _values[key] as bool?;

  @override
  double? getDouble(String key) => _values[key] as double?;

  @override
  int? getInt(String key) => _values[key] as int?;

  @override
  String? getString(String key) => _values[key] as String?;

  @override
  Future<bool> setBool(String key, bool value) async {
    _values[key] = value;
    return true;
  }

  @override
  Future<bool> setDouble(String key, double value) async {
    _values[key] = value;
    return true;
  }

  @override
  Future<bool> setInt(String key, int value) async {
    _values[key] = value;
    return true;
  }

  @override
  Future<bool> setString(String key, String value) async {
    _values[key] = value;
    return true;
  }
}
