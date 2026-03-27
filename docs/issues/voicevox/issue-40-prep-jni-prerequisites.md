# Issue #40: JNI 実装の前提準備（人間作業）

## Goal

VOICEVOX Core 0.16.2 の配布物をダウンロードし、ヘッダファイルをリポジトリに配置する。
併せて、C++ 実装に必要な設計判断を確定させる。

この Issue は**人間が手動で行う作業**であり、AI 実装の前提条件を揃えることが目的。

## Scope

### 1. 配布物のダウンロードと配置

GitHub Releases から以下をダウンロード:
- `voicevox_core-android-arm64-0.16.2.zip`
- `voicevox_core-android-x86_64-0.16.2.zip`

展開して以下をリポジトリに配置:

```
android/src/main/cpp/include/
  voicevox_core.h              ← ヘッダファイル
android/src/main/jniLibs/
  arm64-v8a/libvoicevox_core.so
  x86_64/libvoicevox_core.so
```

### 2. ヘッダの確認とメモ

`voicevox_core.h` を読み、以下の情報をこの Issue のコメントまたは別ファイルにメモする:

- [ ] 初期化関数名（例: `voicevox_synthesizer_new`, `voicevox_open_jtalk_rc_new` 等）
- [ ] 初期化に必要な構造体名とそのフィールド
- [ ] モデルロード関数名（例: `voicevox_voice_model_file_open`, `voicevox_synthesizer_load_voice_model` 等）
- [ ] TTS / synthesis 関数名（例: `voicevox_synthesizer_tts` 等）
- [ ] TTS options 構造体の名前とフィールド（speed, pitch, intonation 等の設定方法）
- [ ] WAV 取得の戻り値形式（ポインタ + サイズか、別の形式か）
- [ ] WAV メモリ解放関数名
- [ ] エラーコード取得方法

### 3. 設計判断の確定

以下の未確定事項に回答する:

#### Q13: TTS 合成方式

- [ ] 方式1: TTS 一発呼び出し
- [ ] 方式2: `create_audio_query` → パラメータ編集 → synthesis

推奨: 初期版は方式1

#### Q14: speakerId の扱い

- [ ] Kotlin の `speakerId` を JNI 内でそのまま style id として使う
- [ ] 内部マッピングテーブルを設ける

推奨: 初期版は style id 固定値

#### Q15: 使用する VVM

- [ ] 使用する VVM ファイル名 / 話者名
- [ ] VVM の入手方法（assets 同梱 / 初回ダウンロード）
- [ ] VVM のライセンス確認済みか

### 4. OpenJTalk 辞書の配置

- [ ] `open_jtalk_dic_utf_8-1.11` を `android/src/main/assets/` に配置
- [ ] 辞書の入手元を記録

### 5. VVM の配置

- [ ] 選択した VVM を `android/src/main/assets/voice/` に配置

## Non-scope

- C++ コードの実装（Issue #41）
- Kotlin ラッパーの実装（Issue #42）
- ビルド確認（Issue #39 で実施済みの前提）

## Dependencies

- Issue #39（JNI ブリッジ基盤: CMake, Gradle 設定が済んでいること）

## Acceptance Criteria

1. `voicevox_core.h` がリポジトリの `android/src/main/cpp/include/` に存在する
2. `.so` ファイルが `jniLibs` の各 ABI ディレクトリに存在する
3. ヘッダから読み取った関数名・構造体名のメモが記録されている
4. Q13 / Q14 / Q15 の回答が記録されている
5. OpenJTalk 辞書が assets に配置されている
6. VVM が assets に配置されている
7. 上記すべてが 0.16.2 の同一リリース由来である

## AI 実装適性

- **AI 実装に向いていない**: ダウンロード、ヘッダ読解、設計判断は人間が行う
- **所要時間の目安**: ダウンロード・展開・配置で 30 分〜1 時間程度

## Implementation Notes

- ダウンロード元: https://github.com/VOICEVOX/voicevox_core/releases
- 0.16 系は配布物の構成が変わっている（`include/` と `lib/` に分離）ため、ZIP 内の構成を確認すること
- ヘッダのメモは `docs/issues/voicevox/` 配下に別ファイルで残してもよい
- このメモが Issue 08c の入力になるため、正確さが重要
