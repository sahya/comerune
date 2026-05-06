# 拡張機能ガイド (`integrations/`)

ホスト本体には含めにくい実装を、別パッケージとして取り込むための仕組みです。本ガイドはフォーク開発者が `integrations/<name>/` を追加して動かすまでの手順をまとめたものです。

## 0. 設計概要

- ホスト本体は **contract（abstract class / SlotId）のみ** を持つ
- 実装は `integrations/<name>/` に置いた別 Dart パッケージ（`path` 依存）
- `integrations/` が空でも build / analyze / test / 起動が成功する（[`AGENTS.md` の Optional Reference Two-Stage Fallback](../AGENTS.md) 規約準拠）
- 信頼境界は **自分または信頼するフォーク開発者**。第三者拡張は前提外（拡張＝依存追加と同等の信頼判断が必要）

## 1. 追加手順

```bash
git submodule add <your-private-repo-url> integrations/<name>
make ext-gen           # pubspec_overrides.yaml と registry.g.dart を再生成
flutter pub get
flutter run
```

運用ルール:

- `.gitmodules` に URL を **書かない**（公開 repo に submodule の存在を残さない）。`integrations/*` は `.gitignore` 対象、`.gitkeep` のみ追跡
- `<name>` は **`pubspec.yaml` の `name:` と完全一致** + **snake_case のみ**（`^[a-z_][a-z0-9_]*$`）
- Dart 予約語（`class`, `void`, `null` 等）と Dart/Flutter ビルトインパッケージ名（`dart`, `flutter`, `flutter_test`, `meta`）は使えない
- `git submodule update --remote` は禁止。SHA はコミット pin で固定する

## 2. submodule の最小構造

```
integrations/<name>/
├── pubspec.yaml
└── lib/<name>.dart
```

```yaml
# pubspec.yaml
name: <name>            # ディレクトリ名と完全一致
publish_to: "none"
environment:
  sdk: ">=3.11.0 <4.0.0"
dependencies:
  flutter:
    sdk: flutter
```

```dart
// lib/<name>.dart
import 'package:flutter/widgets.dart';
import 'package:comerune/extension/comerune_extension.dart';
import 'package:comerune/extension/extension_registry.dart';
import 'package:comerune/extension/extension_result.dart';
import 'package:comerune/extension/services/broadcast_control_extension.dart';
import 'package:comerune/extension/slot_ids.dart';

ComeruneExtension createExtension() => _MyIntegration();

class _MyIntegration extends ComeruneExtension {
  const _MyIntegration();

  @override
  String get name => 'my_integration'; // override 推奨。release `--obfuscate` で runtimeType は mangled

  @override
  void register(ExtensionRegistry registry) {
    final _MyBroadcastControl control = _MyBroadcastControl();
    registry.registerService<BroadcastControlExtension>(control);
    registry.registerSlotWidgets(
      SlotIds.broadcasterScreenActions,
      <Widget>[
        PopupMenuItem<Object>(
          value: const Object(),
          onTap: () => control.extendBroadcast(by: const Duration(minutes: 30)),
          child: const Text('放送を延長'),
        ),
      ],
    );
  }
}

class _MyBroadcastControl extends BroadcastControlExtension {
  @override
  Future<ExtensionResult<void>> extendBroadcast({required Duration by}) async {
    return const ExtensionResultOk<void>(null);
  }
}
```

命名は内部 API 名・特定サービス固有名を含めない（`integration_*` 等の汎用名推奨）。

## 3. Slot カタログ

| ID | 表示位置 | 表示条件 | 要求型 | デフォルト order |
|---|---|---|---|---|
| `SlotIds.broadcasterScreenActions` | コメント画面 AppBar の overflow メニュー、「配信を終了」直後 | 放送者として接続中 | `PopupMenuEntry<Object>` | `hostFirst` |

**型に注意**: Dart の generics は invariant のため、`PopupMenuItem<int>` や `PopupMenuItem<void>` は登録しても **silently drop** されます。必ず `PopupMenuItem<Object>` を使ってください。`onTap` は extension 側で完結させ、ホストは非ホスト値を no-op として無視します。

## 4. Service カタログ

| Contract | host built-in 実装 | 用途 |
|---|---|---|
| `BroadcastControlExtension` (`extendBroadcast`) | なし | 放送制御系の拡張ポイント。拡張未登録時は `ExtensionResultUnsupported`、関連 UI は描画されない |

`ExtensionResult<T>` は sealed の 3 ケース:

- `ExtensionResultOk<T>(value)` — 正常終了
- `ExtensionResultUnsupported<T>()` — 拡張未登録、または「未対応」を明示
- `ExtensionResultFailure<T>(cause)` — 拡張内例外（host 側で正規化）

⚠️ `cause` を caller 側で直接ログ出力しないでください。host の `logExtensionDiagnostic` ヘルパは release で内容を匿名化しますが、`print(result.cause)` すると release でも漏れます。

呼び出しは `ExtensionServiceInvoker.invoke` 経由（policy デフォルトは `extensionFirstFallback`、`hostFallback` を渡せば代替実装にフォールバック可能）。

## 5. dart-define 上書き（debug 限定 / release では無視）

| キー | 効果 |
|---|---|
| `COMERUNE_EXT_DISABLED=name1,name2` | 該当 extension の `register` を skip |
| `COMERUNE_EXT_POLICY=hostOnly\|...` | グローバル service policy 上書き |
| `COMERUNE_EXT_POLICY_<CONTRACT>=...` | contract 単位の policy 上書き |
| `COMERUNE_EXT_SLOT_ORDER=hostFirst\|...` | グローバル slot order 上書き |
| `COMERUNE_EXT_SLOT_ORDER_<SLOT_ID>=...` | slot 単位の order 上書き |

**作用 surface の対応**:

- `COMERUNE_EXT_POLICY*` → service 呼び出しのみ
- `COMERUNE_EXT_SLOT_ORDER*` → slot widgets のみ
- `COMERUNE_EXT_DISABLED` → register 全体を skip（最も強い）

```bash
# 拡張をまとめて無効化（baseline 検証）
flutter run --dart-define=COMERUNE_EXT_DISABLED=my_integration

# service + slot 両方を host のみに固定
flutter run \
  --dart-define=COMERUNE_EXT_POLICY=hostOnly \
  --dart-define=COMERUNE_EXT_SLOT_ORDER=hostOnly
```

不正値（例: `COMERUNE_EXT_POLICY=invalid`）は silently fallback。release では `kReleaseMode` 早期 return + tree-shake で完全に無視されます。

## 6. セキュリティ運用

- **capability facade**: 拡張に raw `http.Client` / `flutter_secure_storage` / 認証トークンを直接渡さない。狭い facade 経由 or 拡張側で完結させる
- **ログ匿名化**: 拡張内ログに endpoint URL / 内部 API 名 / private 識別子を含めない。host の `logExtensionDiagnostic` 経由なら release で error/stackTrace は完全 drop
- **submodule SHA pin**: 取り込み時に commit を固定。期待 SHA は内部メモで管理（公開 repo には URL も SHA も載せない）。`pubspec.lock` の sha256 は pub.dev 由来にしか効かないため、submodule 改ざん検知は SHA 確認が唯一の手段
- **リリースノート**: 拡張機能の存在は汎用語のみで表現（[CLAUDE.md のリリースノート規約](../CLAUDE.md) 参照）

## 7. トラブルシュート

### 拡張 widget が menu に出ない

| 主な原因 | 対処 |
|---|---|
| 型が `PopupMenuEntry<Object>` でない | `PopupMenuItem<Object>` に修正（invariant generics で他は silently drop） |
| 非 broadcaster | 該当 slot は broadcaster gate 必須 |
| dart-define で disable | `COMERUNE_EXT_DISABLED` / `COMERUNE_EXT_SLOT_ORDER_*=hostOnly` を確認 |
| `register()` 内で例外 | debug ログ `optional integration unavailable` を確認 |

### service 呼び出しが常に `ExtensionResultUnsupported` を返す

| 主な原因 | 対処 |
|---|---|
| `registerService` 未呼び出し / 拡張内で Unsupported を明示 return | 拡張側ロジック確認 |
| `COMERUNE_EXT_POLICY=hostOnly` 等で固定 | 該当 dart-define を外す |
| `loadAll` 後の register（freeze 後） | register は `register()` メソッド内のみで行う |

### service 呼び出しが常に `ExtensionResultFailure` を返す

| 主な原因 | 対処 |
|---|---|
| 拡張内で例外を throw | debug ログ `optional integration call failed` を確認。invoker が `ExtensionResultFailure` に正規化、host は保護される |

### ビルド / 依存解決が失敗する

| 主な原因 | 対処 |
|---|---|
| `flutter pub get` がパッケージ解決失敗 | dir 名と pubspec name 不一致 → どちらかをそろえる + `make ext-gen` 再実行 |
| `make ext-gen` 後 `pubspec.lock` の差分が大きい | 新 path 依存追加で解決結果が変わった。差分確認後に commit、lock は通常 commit する |

## 付録

実装ファイルは `lib/extension/` 配下、生成スクリプトは `scripts/gen_extension_*.dart`。各ファイルの dartdoc が一次情報源です。
