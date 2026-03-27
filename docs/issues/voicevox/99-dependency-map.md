# 依存マップ: 並列実装 vs 順序依存

## 依存関係図

```
Issue 01 (データモデル)    Issue 08 (JNI ブリッジ基盤)
  │                            │
  ├─→ Issue 02 (前処理)        │
  │     │                      │
  │     ├─→ Issue 03 (URL/記号/絵文字)
  │     │     │                │
  │     │     └─→ Issue 04 (文字数/辞書/NG)
  │     │                      │
  │     └─→ Issue 05 (重複抑制) │
  │                            │
  ├─→ Issue 06 (キュー管理)    │
  │                            │
  ├─→ Issue 07 (設定リポジトリ)│
  │                            │
  ├─→ Issue 12 (イベント通知)  └─→ Issue 09 (VoicevoxEngine)
  │                                  │
  ├─→ Issue 10 (WAV再生)             │
  │     │                            │
  │     └─→ Issue 11 (Audio Focus)   │
  │                                  │
  └───────────────────────────────────┘
            │
            ↓
      Issue 13 (SpeechController) ← 全コンポーネントを統合
            │
            ↓
      Issue 14 (Platform Channel Plugin)
            │
            ↓
      Issue 15 (Flutter Dart ラッパー)
```

## 並列実装可能なグループ

以下のグループは互いに依存がなく、**同時に着手可能**。

### グループ A: コメント整形系（Issue 01 完了後）

| Issue | 内容 | 所要感 |
|---|---|---|
| 02 | 前処理・スキップ判定 | 小 |
| 03 | URL・記号圧縮・絵文字 | 中（02 の後） |
| 04 | 文字数・辞書・NG | 中（03 の後） |
| 05 | 重複抑制 | 小（02 の後） |

### グループ B: キュー・設定・イベント（Issue 01 完了後）

| Issue | 内容 | 所要感 |
|---|---|---|
| 06 | キュー管理 | 小 |
| 07 | 設定リポジトリ | 小 |
| 12 | イベント通知 | 小 |

### グループ C: ネイティブエンジン（Issue 01 と独立可能）

| Issue | 内容 | 所要感 |
|---|---|---|
| 08 | JNI ブリッジ基盤 | 中〜大 |
| 09 | VoicevoxEngine | 大（08 の後） |

### グループ D: 音声再生（Issue 01 完了後）

| Issue | 内容 | 所要感 |
|---|---|---|
| 10 | WAV 再生 | 中 |
| 11 | Audio Focus | 小（10 の後） |

## 順序依存が強い Issue

以下は**前の Issue が完了しないと着手できない**。

```
Issue 01 → Issue 02 → Issue 03 → Issue 04   (整形の段階的構築)
Issue 08 → Issue 09                          (JNI → エンジン)
Issue 10 → Issue 11                          (再生 → Audio Focus)
全コンポーネント → Issue 13 → Issue 14 → Issue 15   (統合→Plugin→Dart)
```

## 推奨実装順序

### Phase 0: 基盤（最初に着手）

- **Issue 01**: Kotlin データモデル — 全 Issue の前提
- **Issue 08**: JNI ブリッジ基盤 — Issue 01 と並行可能、人間作業あり

### Phase 1: 並列可能（Issue 01 完了後）

同時に着手可能:
- **Issue 02 → 03 → 04**: 整形系（直列）
- **Issue 05**: 重複抑制
- **Issue 06**: キュー管理
- **Issue 07**: 設定リポジトリ
- **Issue 10**: WAV 再生
- **Issue 12**: イベント通知

### Phase 2: エンジン（Issue 08 完了後）

- **Issue 09**: VoicevoxEngine
- **Issue 11**: Audio Focus（Issue 10 完了後）

### Phase 3: 統合（Phase 1-2 完了後）

- **Issue 13**: SpeechController

### Phase 4: 連携（Issue 13 完了後）

- **Issue 14**: Platform Channel Plugin
- **Issue 15**: Flutter Dart ラッパー

## AI 実装適性まとめ

| Issue | AI向き | 人間確認が必要な論点 |
|---|---|---|
| 01 データモデル | ◎ | パッケージ名 (Q10) |
| 02 前処理 | ◎ | なし |
| 03 URL/記号/絵文字 | ◎ | 絵文字正規表現の精度 |
| 04 文字数/辞書/NG | ◎ | 初期辞書の内容 |
| 05 重複抑制 | ◎ | 連投閾値の設計 |
| 06 キュー管理 | ◎ | eviction 方式 (N2) |
| 07 設定リポジトリ | ◎ | なし |
| 08 JNI ブリッジ | △ | バージョン確定, .so 入手, ライセンス (Q1,Q3) |
| 09 VoicevoxEngine | △ | VVM 入手, 話者 ID (Q4), C++ API |
| 10 WAV 再生 | ○ | 一時ファイルパス |
| 11 Audio Focus | ○ | 喪失時挙動 (Q9) |
| 12 イベント通知 | ◎ | なし |
| 13 SpeechController | ○ | 非同期制御の安全性 |
| 14 Plugin | ○ | Channel 名 (Q10) |
| 15 Dart ラッパー | ◎ | Channel 名 (Q10) |

**凡例**: ◎ = AI に任せて問題ない / ○ = AI で可能だが要レビュー / △ = 人間の判断・作業が先に必要
