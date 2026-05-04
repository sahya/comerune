# 拡張機能ガイド (`integrations/`)

このドキュメントは、本リポジトリをフォークした開発者が、自分専用の **optional integration** を追加するための手順とコントラクトをまとめたものです。

最終更新: 各拡張ポイント追加時に併せて更新。

---

## 0. 概要

### 目的

ホスト本体の公開コードに含めにくい実装（公開ドキュメントが揃っていない領域に依存する処理など）を、**ホストとは独立した別パッケージ**として分離して持ち込めるようにする仕組みです。

- ホスト本体は **contract（abstract class / SlotId）のみ** を持ちます
- 実装は `integrations/<name>/` 配下に配置する別 Dart パッケージ（pub `path` 依存）として外に切り出します
- `integrations/` が空でも、**build / analyze / test / 起動** が通常通り成功します
- 実装は `git submodule` として管理することを想定していますが、ローカル `path` でも動作します

### 信頼境界

このメカニズムは「**自分または信頼するフォーク開発者**」を前提にしています。

- 拡張は任意の Dart コードを実行できるため、**未知の第三者が書いた integration を取り込むことは想定していません**
- セキュリティ層・サンドボックス層は提供しません（拡張＝依存追加と同等の信頼判断が必要）
- 第三者拡張をサポートする場合は別途 manifest + DSL ベースの仕組みを再設計する必要があります

### 関連ルール

本ガイドは [`AGENTS.md`](../AGENTS.md) の **Optional Reference Two-Stage Fallback** ルールを正規化したものです。実装中の判断に迷ったときは AGENTS.md の該当節を参照してください。

---

## 1. 追加手順

### 1-1. submodule を追加する

```bash
# integrations/ 直下に新規 submodule を追加
git submodule add <your-private-repo-url> integrations/<name>
```

**重要な運用ルール**:

- **`.gitmodules` には URL を書かない運用**を採用しています（公開リポジトリに submodule の存在自体を残さないため）
  - リポジトリ直下の `.gitignore` で `integrations/*` を ignore 対象にしているため、submodule のディレクトリエントリも含めて公開には載りません
  - ただし `integrations/.gitkeep` のみは追跡されます
- **`<name>` には `pubspec.yaml` の `name:` フィールドと完全に同じ文字列**を使ってください（ディスカバリ時に検証されます）
- 命名は **snake_case のみ**（`^[a-z_][a-z0-9_]*$`）
- Dart 予約語（`class`, `void`, `null`, `await` 等）と Dart / Flutter のビルトインパッケージ名（`dart`, `flutter`, `flutter_test`, `meta`）は使えません

### 1-2. 自動生成を実行

```bash
make ext-gen
```

このターゲットは 2 つのスクリプトを順に実行します:

- `scripts/gen_extension_overrides.dart` → `pubspec_overrides.yaml` を再生成（または不在時に削除）
- `scripts/gen_extension_registry.dart` → `lib/extension/generated/registry.g.dart` を再生成

両方とも **拡張側コードを評価せず**、`pubspec.yaml` の `name:` 行のみを読み取ります。

### 1-3. 依存解決とビルド

```bash
flutter pub get
flutter run
```

`pubspec.lock` に変化が出る場合、それは `integrations/<name>/` を path 依存として解決した結果です。コミットするかどうかはチームのポリシーに従ってください（`pubspec_overrides.yaml` 自体は `.gitignore` 対象、再生成可能なので通常は commit しません）。

---

## 2. submodule の最小構造

```
integrations/<name>/
├── pubspec.yaml
└── lib/
    └── <name>.dart
```

### 2-1. `pubspec.yaml` の最小例

```yaml
name: <name>            # ディレクトリ名と完全一致させること
description: Optional integration for <name>.
version: 0.1.0
publish_to: "none"      # 拡張は pub.dev に公開しない

environment:
  sdk: ">=3.11.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter
  # 必要に応じてホストと同じバージョンの依存を pin で追加
```

### 2-2. `lib/<name>.dart` の最小例

```dart
import 'package:flutter/widgets.dart';

// ホスト本体の contract をそのまま使う
import 'package:comerune/extension/comerune_extension.dart';
import 'package:comerune/extension/extension_registry.dart';
import 'package:comerune/extension/extension_result.dart';
import 'package:comerune/extension/services/broadcast_control_extension.dart';
import 'package:comerune/extension/slot_ids.dart';

/// 必須: ホストの自動生成 registry が呼び出すトップレベル関数。
ComeruneExtension createExtension() => _MyIntegration();

class _MyIntegration extends ComeruneExtension {
  const _MyIntegration();

  /// 任意: COMERUNE_EXT_DISABLED で識別するための名前。
  /// 省略時は `runtimeType.toString()` ですが、release ビルドの
  /// `--obfuscate` で mangled 化されるため、override を強く推奨します。
  @override
  String get name => 'my_integration';

  @override
  void register(ExtensionRegistry registry) {
    // 1) service の登録（host の呼出箇所は ExtensionServiceInvoker
    //    経由で呼び出します）
    final _MyBroadcastControl control = _MyBroadcastControl();
    registry.registerService<BroadcastControlExtension>(control);

    // 2) slot への widget 追加（PopupMenuEntry<Object> 必須）。
    //    onTap は extension 側で完結し、登録した service を直接呼ぶ
    //    パターンが最も簡潔です。
    registry.registerSlotWidgets(
      SlotIds.broadcasterScreenActions,
      <Widget>[
        PopupMenuItem<Object>(
          value: const Object(),
          onTap: () => control.extendBroadcast(
            by: const Duration(minutes: 30),
          ),
          child: const Text('放送を延長'),
        ),
      ],
    );
  }
}

class _MyBroadcastControl extends BroadcastControlExtension {
  @override
  Future<ExtensionResult<void>> extendBroadcast({
    required Duration by,
  }) async {
    // 実装（HTTP 呼び出し / 内部状態の更新など）
    return const ExtensionResultOk<void>(null);
  }
}
```

### 2-3. 命名規約

- **内部 API 名・私的識別子・特定サービス名を含めない**: `niconico_*` / `ndgr_*` のようなサービス固有名はホスト側もコメント・ログ・命名で避けています。拡張側も `optional_*` / `integration_*` 等の汎用名を推奨します
- **`<name>` は snake_case 必須**: pub のパッケージ名規約と一致
- **ディレクトリ名 == pubspec name**: ディスカバリスクリプトが両者の一致を強制します

---

## 3. Slot カタログ

ホストが現在公開している UI スロットの一覧です。各スロットの **型と表示位置の契約** を必ず確認してください。

### 3-1. `SlotIds.broadcasterScreenActions`

| 項目 | 内容 |
|---|---|
| **表示位置** | コメント画面 AppBar のオーバーフローメニュー内、「配信を終了」直後・divider の前 |
| **表示条件** | ログイン中ユーザーが番組の放送者であること（broadcaster gate）。それ以外では拡張 widget は描画されません |
| **要求型** | **`PopupMenuEntry<Object>`**（典型的には `PopupMenuItem<Object>`）|
| **デフォルト order** | `hostFirst`（ホストの「配信を終了」が先、拡張 widget はその後ろに append） |
| **onTap の責務** | 拡張側で完結。ホストは非ホスト値を no-op として無視 |

#### 型に関する注意

Dart の generic は invariant のため、**`PopupMenuItem<int>` / `PopupMenuItem<MyEnum>` / `PopupMenuItem<void>` 等は登録しても silently drop されます**。型は必ず `PopupMenuItem<Object>` を使ってください。`value:` には任意の Object を渡せます。

---

## 4. Service カタログ

ホストが公開している service contract の一覧です。

### 4-1. `BroadcastControlExtension`

放送制御系の拡張用 service contract。

```dart
abstract class BroadcastControlExtension {
  Future<ExtensionResult<void>> extendBroadcast({required Duration by});
}
```

- ホストは built-in 実装を持ちません
- 呼出側のデフォルト policy は `extensionFirstFallback` で、`hostFallback` は `null` で呼ばれます。**拡張未登録時はそのまま `ExtensionResultUnsupported` が返り**、関連 UI（ボタン等）は描画されません
- ホストが将来同名のメソッドに対する built-in 実装を持つ場合、呼出側で `hostFallback` を渡せば `extensionFirstFallback` の本来の挙動（拡張優先・失敗時 host にフォールバック）が活きます

### 4-2. `ExtensionResult<T>` (sealed)

すべての service 呼び出しの戻り値を sealed class で受けます:

| 値 | 意味 |
|---|---|
| `ExtensionResultOk<T>(T value)` | 拡張が正常に値を返した |
| `ExtensionResultUnsupported<T>()` | 拡張未登録、または拡張が「未対応」と明示的に返した |
| `ExtensionResultFailure<T>(Object cause)` | 拡張内で例外が発生（host 側で正規化済み）|

**重要**: `ExtensionResultFailure.cause` を **caller 側で直接ログ出力しないこと**。ホストの `logExtensionDiagnostic` ヘルパは release で原因をマスクしますが、caller が `print(result.cause)` すると release でも内部情報が漏れる可能性があります。

### 4-3. 呼び出し方

call site では `ExtensionServiceInvoker.invoke` を経由するのが標準です:

```dart
final ExtensionResult<void> result =
    await ExtensionServiceInvoker.invoke<BroadcastControlExtension, void>(
      registry,
      callExtension: (BroadcastControlExtension s) =>
          s.extendBroadcast(by: const Duration(minutes: 30)),
      // 必要なら hostFallback も渡せる（host が代替実装を持つ場合）
    );

switch (result) {
  case ExtensionResultOk<void>():
    // 成功
  case ExtensionResultUnsupported<void>():
    // 拡張未登録 / 未対応
  case ExtensionResultFailure<void>():
    // 拡張内で例外（debug でのみ詳細ログ）
}
```

policy デフォルトは `extensionFirstFallback`。host fallback がない場合は拡張のみが走り、失敗時は Failure / Unsupported が caller に伝わります。

---

## 5. dart-define 上書きリファレンス（debug 限定）

開発時に拡張の挙動を即座に切り替えるための `--dart-define` 群です。

| キー | 効果 |
|---|---|
| `COMERUNE_EXT_DISABLED=name1,name2` | 該当 extension の `register` を skip（`ComeruneExtension.name` で照合） |
| `COMERUNE_EXT_POLICY=hostOnly\|hostFirstFallback\|extensionFirstFallback\|extensionOnly` | グローバル service policy を上書き |
| `COMERUNE_EXT_POLICY_BROADCAST_CONTROL_EXTENSION=...` | `BroadcastControlExtension` のみの policy 上書き（per-contract が global より優先） |
| `COMERUNE_EXT_SLOT_ORDER=hostFirst\|extensionFirst\|hostOnly\|extensionOnly` | グローバル slot order を上書き |
| `COMERUNE_EXT_SLOT_ORDER_BROADCASTER_SCREEN_ACTIONS=...` | `broadcasterScreenActions` slot のみの order 上書き |

### 例

```bash
# 拡張をまとめて無効化して baseline を確認（register 自体を skip）
flutter run --dart-define=COMERUNE_EXT_DISABLED=my_integration,other_integration

# service 呼び出しだけ host fallback に固定
# （拡張 widget は描画される。完全に消したい時は次の例と組み合わせる）
flutter run --dart-define=COMERUNE_EXT_POLICY=hostOnly

# slot を hostOnly に強制（拡張 widget を全 slot で隠す）
flutter run --dart-define=COMERUNE_EXT_SLOT_ORDER=hostOnly

# 完全 baseline を再現（service + slot 両方を host のみに）
flutter run \
  --dart-define=COMERUNE_EXT_POLICY=hostOnly \
  --dart-define=COMERUNE_EXT_SLOT_ORDER=hostOnly
```

**注意**: `COMERUNE_EXT_POLICY` は **service 呼び出しのみ** に作用し、slot widgets には影響しません。slot widgets を抑制するには `COMERUNE_EXT_SLOT_ORDER` を使うか、`COMERUNE_EXT_DISABLED` で対象 extension の register 自体を skip してください。

### release ビルドでの挙動

- **release ビルドではこれらの dart-define は完全に無視されます**
- `kReleaseMode` 早期 return により、override の lookup table は AOT で tree-shake されます
- 不正値（例: `COMERUNE_EXT_POLICY=invalid_value`）は debug でも silently fallback、起動を阻害しません

---

## 6. セキュリティ運用

### 6-1. capability facade の原則

拡張に **生の `http.Client` / `flutter_secure_storage` / 認証トークン** を直接渡さないでください。

- 拡張に渡してよいのは「必要な操作だけを公開する狭い facade」のみ
- 認証情報は host 側でラップした session オブジェクト経由で渡す
- 拡張側で raw network call を実装する場合は、自前で `http` 等を depend し、ホストの認証情報は受け取らない設計にする

### 6-2. ログ・エラーメッセージの匿名化

- 拡張内で生成するログメッセージに **endpoint URL / 内部 API 名 / private 識別子** を含めない
- ホストの `logExtensionDiagnostic` ヘルパを使う場合、release では error / stackTrace は完全に dropped されます（debug ではのみ詳細表示）
- 自前のロガーを使う場合も release 時の sanitisation を必ず実装してください

### 6-3. submodule の commit SHA pin

- `git submodule add` した時点の commit SHA で固定される運用を遵守
- **`git submodule update --remote` は使わない**（意図しない最新版を取り込む危険性）
- 期待 SHA は内部メモまたは README で管理（公開 repo には submodule URL も SHA も載せない）
- `pubspec.lock` の sha256 content-hash は pub.dev 由来の依存にしか効かないため、submodule 自体の改ざん検知は **コミット SHA 確認** が唯一の手段

### 6-4. リリースノートの取り扱い

[`CLAUDE.md` のリリースノート作成ルール](../CLAUDE.md) に従い、拡張機能の存在を**汎用語のみ**で表現してください（具体的な API 名・サービス固有名・脆弱性詳細は記載しない）。

---

## 7. 不在時の挙動

`integrations/` ディレクトリが空（または `.gitkeep` のみ）の場合:

- `make ext-gen` は `pubspec_overrides.yaml` を削除し、`registry.g.dart` を空 list で生成します
- `flutter pub get` / `flutter analyze` / `flutter test` / `flutter run` がすべて通常通り成功します
- ホストの拡張呼び出しは `ExtensionResultUnsupported` を返し、関連する UI ボタン / メニュー項目は **そもそも生えません**（renderless）
- ロード時の起動オーバーヘッドはマイクロ秒オーダーで実質ゼロ

これは [`AGENTS.md` の Optional Reference Two-Stage Fallback ルール](../AGENTS.md) を満たすための必須挙動であり、フォークしたばかりの開発者がいきなり動かせる前提です。

---

## 8. トラブルシュート

### 8-1. `make ext-gen` 後に `pubspec.lock` の差分が大きい

新たに `integrations/<name>/` を path 依存として解決した結果です。`integrations/<name>/pubspec.yaml` の依存を pin したうえで、本体の `pubspec.lock` の差分を確認してから commit してください。lock 自体は通常 commit します。

### 8-2. `flutter pub get` がパッケージを解決できない

- `pubspec_overrides.yaml` が古い → `make ext-gen` で再生成
- `integrations/<name>/pubspec.yaml` の `name:` がディレクトリ名と一致していない → ディレクトリかパッケージ名のどちらかをそろえる
- スクリプトが該当 integration を skip している場合は `dart run scripts/gen_extension_overrides.dart` の stderr 出力を確認（理由は warning として出力されます）

### 8-3. 拡張の widget がメニューに出ない

| 原因 | 対処 |
|---|---|
| broadcaster ガードに引っかかっている | `SlotIds.broadcasterScreenActions` は放送者専用 slot。条件を満たしているか確認 |
| 型が `PopupMenuEntry<Object>` でない | `PopupMenuItem<int>` 等は invariant generics で silently drop。`PopupMenuItem<Object>` に修正 |
| dart-define で disable されている | `COMERUNE_EXT_DISABLED` または `COMERUNE_EXT_SLOT_ORDER_*=hostOnly` を確認 |
| `register()` 内で例外を投げている | debug ログで `optional integration unavailable` を確認 |

### 8-4. service 呼び出しが期待通り動かない

期待される結果ごとに切り分けてください。

#### 常に `ExtensionResultUnsupported` が返る

| 原因 | 対処 |
|---|---|
| 拡張が `register` で `registerService` を呼んでいない | 実装を確認 |
| dart-define で `COMERUNE_EXT_POLICY=hostOnly` などに固定 | 該当 dart-define を外す |
| 拡張内で `ExtensionResultUnsupported` を return している | 拡張側のロジックを確認 |
| registry が freeze 後に register を試みた | `loadAll` 後の register は silently ignored。register は `register()` メソッド内のみで行う |

#### 常に `ExtensionResultFailure` が返る（呼び出すと内部で例外）

| 原因 | 対処 |
|---|---|
| 拡張内で例外を throw している | debug ログで `optional integration call failed` を確認。invoker が拡張例外を `ExtensionResultFailure` に正規化してホストを保護しています |
| 拡張側 service が長時間 future を返す → タイムアウト | 自前で timeout / retry をかけるか、host 側の呼出箇所に timeout を仕込む |

### 8-5. テストが落ちる

- 既存の widget テストで `ExtensionScope` を mount していなくても、`resolveSlotChildren` は host children のみを返す防御的設計です。ただし service 呼び出しを test する場合は registry を明示的に inject する必要があります（[X2 のテストコード](../test/extension/extension_service_invoker_test.dart) を参照）

---

## 付録: 拡張機構の実装ファイル一覧

参照用にホスト側の実装ファイル一覧を載せておきます。詳細は各ファイルの dartdoc を参照してください。

| 種別 | ファイル | 役割 |
|---|---|---|
| Contract | `lib/extension/comerune_extension.dart` | `ComeruneExtension` 抽象クラス・`name` getter |
| Contract | `lib/extension/extension_registry.dart` | service / slot widget の registry |
| Contract | `lib/extension/extension_result.dart` | sealed `ExtensionResult<T>` |
| Contract | `lib/extension/slot_ids.dart` | スロット ID カタログ |
| Contract | `lib/extension/service_override_policy.dart` | 4 種 policy enum |
| Contract | `lib/extension/slot_insert_order.dart` | 4 種 order enum |
| Service | `lib/extension/services/broadcast_control_extension.dart` | `BroadcastControlExtension` |
| Loader | `lib/extension/extension_loader.dart` | 防御的ローダ・freeze |
| Invoker | `lib/extension/extension_service_invoker.dart` | policy 適用ヘルパ |
| Scope | `lib/extension/extension_scope.dart` | `InheritedWidget` |
| Slot | `lib/extension/extension_slot.dart` | `resolveSlotChildren` ヘルパ |
| Override | `lib/extension/extension_debug_overrides.dart` | dart-define 解決（debug 限定） |
| Logging | `lib/extension/_logging.dart` | 共通ロガー（release 匿名化） |
| Generator | `scripts/gen_extension_overrides.dart` | `pubspec_overrides.yaml` 生成 |
| Generator | `scripts/gen_extension_registry.dart` | `registry.g.dart` 生成 |
| Discovery | `scripts/_extension_discovery.dart` | 共通ディスカバリ + 検証 |
