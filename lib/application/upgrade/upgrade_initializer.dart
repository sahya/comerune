import 'dart:developer';

import '../settings/settings_store.dart';

/// APK アップデートインストール時のデータライフサイクルカテゴリ。
///
/// SharedPreferences の各キーはこのいずれかに分類される。
/// [UpgradeInitializer] がアップデートを検知した際に、
/// [ephemeral] なキーのみ初期化し [persistent] なキーは保持する。
enum StorageKeyCategory {
  /// ユーザーが設定した値。アップデート後も保持される。
  ///
  /// 例: テーマ設定、TTS 設定、NG ワード、お気に入りユーザー、
  /// 読み上げ辞書、コメント表示設定、ユーザー属性（ニックネーム・色）。
  persistent,

  /// 一時的なランタイム状態。アップデート時に初期化される。
  ///
  /// 例: ミュート前の音量（ミュート解除時に復元するための一時値）。
  ephemeral,
}

/// APK アップデートインストール時に一時的な状態を初期化する。
///
/// ## 概要
///
/// Android の APK アップデートでは SharedPreferences がそのまま引き継がれる。
/// ユーザー設定（テーマ・読み上げ・フィルタ等）は保持すべきだが、
/// 一時的なランタイム状態（ミュート前の音量等）は初期化すべき場合がある。
///
/// このクラスは初期化バージョンを管理し、バージョン変更時に
/// [ephemeralKeys] に登録されたキーのみを削除する。
///
/// ## 保持されるキー（persistent）
///
/// - `settings.*`（[ephemeralKeys] に含まれるものを除く）
///   - 読み上げ設定（speechEngine, voicevox.*, bouyomi.*）
///   - コメント設定（showUserName, fontSize, twoLine 等）
///   - フィルタ設定（ngWords, ngWordRules, ngUserIds, omitUrl 等）
///   - お気に入りユーザー（favoriteUserIds）
///   - 読み上げ辞書（dictionaryRules）
///   - 統計設定（statistics.*）
///   - キュー設定（queue.*）
///   - VOICEVOX 利用規約同意（voicevox.termsAccepted）
/// - `usercolor.*`（配信者ごとのユーザー属性）
/// - `onboarding.completed`（オンボーディング完了フラグ）
/// - `app.migrationVersion`（マイグレーション管理）
///
/// ## 初期化されるキー（ephemeral）
///
/// [ephemeralKeys] を参照。一時的な状態のみが対象。
///
/// ## キーの追加方法
///
/// 新しいキーを初期化対象にする場合:
/// 1. [ephemeralKeys] にキーを追加する
/// 2. [currentVersion] をインクリメントする
/// 3. 次回アップデート時にそのキーが初期化される
class UpgradeInitializer {
  UpgradeInitializer({required SharedPreferencesLike prefs}) : _prefs = prefs;

  final SharedPreferencesLike _prefs;

  static const String _versionKey = 'app.initializationVersion';

  /// この値をインクリメントすると次回アップデート時に
  /// [ephemeralKeys] のキーが初期化される。
  static const int currentVersion = 1;

  /// アップデート時に初期化される一時的な状態のキー。
  ///
  /// **追加してよいもの:**
  /// - 一時的なランタイム状態（ミュート前の音量など）
  /// - キャッシュされた中間値
  ///
  /// **追加してはいけないもの:**
  /// - ユーザー設定（テーマ、TTS、フィルタ設定）
  /// - 法的同意（VOICEVOX 利用規約）
  /// - 認証データ（ユーザーセッション）
  /// - ユーザー作成データ（ニックネーム、色、NG ワード、読み上げ辞書）
  /// - お気に入りユーザー
  static const List<String> ephemeralKeys = <String>[
    // ミュート前の音量。ミュート解除時に復元するための一時値であり、
    // アップデート後に古い値が残ると音量が意図しない値に復元される
    // 可能性があるため初期化する。
    'settings.voicevox.preMuteVolume',
  ];

  /// 指定されたキーの [StorageKeyCategory] を返す。
  static StorageKeyCategory categoryOf(String key) {
    if (ephemeralKeys.contains(key)) {
      return StorageKeyCategory.ephemeral;
    }
    return StorageKeyCategory.persistent;
  }

  /// アップデート初期化を実行する。
  ///
  /// アップデートを検知した場合は [ephemeralKeys] を削除し `true` を返す。
  /// 既に最新バージョンの場合は何もせず `false` を返す。
  ///
  /// エフェメラルキーの削除はバージョン更新より先に行われるため、
  /// 途中でクラッシュしても次回起動時に再実行される（安全側に倒す設計）。
  Future<bool> run() async {
    final int storedVersion = _prefs.getInt(_versionKey) ?? 0;

    if (storedVersion >= currentVersion) {
      return false;
    }

    log(
      'Running upgrade initialization from v$storedVersion to v$currentVersion',
      name: 'UpgradeInitializer',
    );

    for (final String key in ephemeralKeys) {
      await _prefs.remove(key);
    }

    await _prefs.setInt(_versionKey, currentVersion);

    log(
      'Upgrade initialization complete (cleared ${ephemeralKeys.length} '
      'ephemeral keys)',
      name: 'UpgradeInitializer',
    );

    return true;
  }
}
