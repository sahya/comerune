import '../settings/settings_store.dart';

/// オンボーディング表示済みフラグを管理するストア。
abstract class OnboardingStore {
  /// オンボーディングを表示済みかどうかを返す。
  bool isCompleted();

  /// オンボーディングを完了済みとしてマークする。
  Future<void> markCompleted();
}

class SharedPreferencesOnboardingStore implements OnboardingStore {
  const SharedPreferencesOnboardingStore({
    required SharedPreferencesLike prefs,
  }) : _prefs = prefs;

  final SharedPreferencesLike _prefs;

  static const String _kOnboardingCompleted = 'onboarding.completed';

  @override
  bool isCompleted() {
    return _prefs.getBool(_kOnboardingCompleted) ?? false;
  }

  @override
  Future<void> markCompleted() async {
    await _prefs.setBool(_kOnboardingCompleted, true);
  }
}
