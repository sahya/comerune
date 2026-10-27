# OAuth ログイン / タイムシフトコメント取得 不動作の原因分析

作成日: 2026-10-27
基準コミット: `8b79b56`（行番号はこの時点のもの。作業前に必ず現行コードで再確認すること）

## このドキュメントについて

「OAuth ログイン」と「タイムシフト（過去放送）のコメント取得」が動かない原因を、コードと GitHub Issue を突き合わせて調べた結果をまとめたもの。調べたあと、別エージェントに反証してもらうクロスレビューを 1 回行い、その結果も反映した。

**AI エージェント向けの読み方**

- 各項目に **[確定] / [推測] / [不明]** のラベルを付けている。[確定] はファイル:行で裏付けたもの、[推測] はコード外の知識や状況証拠によるもので、確度（高・中・低）を併記している。[不明] は実機かサーバー側の確認なしには判断できないもの。
- [推測] / [不明] を前提に実装を始めないこと。先に「6. 検証手順」で事実を確定させる。
- スコープと受け入れ基準の一次情報は GitHub Issue（#639, #654, #655, #795, #581）。本ドキュメントは補助資料なので、Issue と食い違う場合は Issue を優先し、食い違いを報告すること。
- 実装時は `AGENTS.md` と `.ai/flutter_rules.md`、`CLAUDE.md` のルール（2 段フォールバック、依存ピン留め、テストファイル肥大化ルールなど）に従うこと。

**未確認の前提**: 利用者が見ている具体的な症状（ボタンが出ない、ブラウザから戻らない、接続失敗の表示など）は聞き取れていない。本ドキュメントの分析が実際の症状と一致するかは未確認。

---

## 1. 結論サマリ

| 機能 | 主因 | 区分 |
|---|---|---|
| OAuth | release ビルドではボタン非表示。加えて、取得した access_token をどの API も使っていないので、成功しても機能差が生まれない | [確定] 未完成・意図的な無効化 |
| OAuth（debug で試す場合） | App Links 検証（assetlinks.json の署名 SHA-256、applicationId）、dart-define 未指定、BFF の状態のどれかで途中停止しうる | [推測] / [不明] |
| タイムシフト | programinfo が終了放送では `rooms=[]` を返す。resolver が status を読む前に例外を投げるので、タイムシフト判定に到達しない。そのまま audience_token なしの WebSocket に落ちて HTTP 400 になる | [確定] コード経路（実機の応答形は Issue #654 の報告に依拠） |
| タイムシフト | 機能フラグ `kTimeshiftFetchEnabled = false` で取得処理自体も無効化されている。ただし上記の理由で、実際の症状にはこのフラグは関与していない | [確定] |

---

## 2. OAuth の分析

### 2.1 確定事実

- **O-1 [確定]**: release ではログインボタンが出ない。`lib/presentation/screens/login_screen.dart:365-366` が `oauthAvailable = kDebugMode && (_oauthController?.isFullyConfigured ?? false)`。直前のコメントに「access_token の配線は #795 で対応予定」とある。
- **O-2 [確定]**: debug でも設定がないとボタンが出ない。`lib/data/auth/oauth_bff/oauth_bff_config.dart` の `production()` は `NICONICO_OAUTH_CLIENT_ID` / `OAUTH_BFF_HOST` / `OAUTH_AUTHORIZE_ENDPOINT` を `String.fromEnvironment` で読む。`--dart-define-from-file=android/oauth_bff.env` を付けずに `flutter run` すると、どれも空になり `isFullyConfigured == false` になる。`Makefile:19-20` は、env ファイルがあるときだけこの引数を付ける。
- **O-3 [確定]**: OAuth トークンはどの API でも使われていない。`OAuthTokenStore` を参照しているのは、`lib/main.dart:285` の生成箇所だけ。`OAuthAuthController` にはトークンを読み出す API がなく、`OAuthBffAuthService.refresh()` を呼んでいる箇所もない。全 API は `Cookie: user_session`（WebView ログイン由来）で認証している。OAuth が成功しても、変化はスナックバーの「OAuth ログインに成功しました」（`login_screen.dart:294`）だけ。
- **O-4 [確定]**: App Links の受け口。`android/app/src/main/AndroidManifest.xml` の intent-filter は `autoVerify="true"`、host が `${bffHost}`、pathPrefix が `/auth/callback`。`android/app/build.gradle.kts:41-42` では、`android/oauth_bff.env` がないと host が `oauth-bff.example.invalid` になる。同じく `:17` では、`app_id.properties` がないと applicationId が `com.example.comerune` になる。
- **O-5 [確定]**: `AndroidManifest.xml` に `<meta-data android:name="flutter_deeplinking_enabled" android:value="false"/>` がない。app_links 7.2.1 の公式ドキュメント（`doc/README_android.md`）には「From Flutter 3.24, you must disable it explicitly」とある。CI の Flutter は 3.44.0。`MaterialApp`（`lib/main.dart:833`）は `home:` だけで、`onGenerateRoute` を持たない。
- **O-6 [確定]**: BFF（Cloudflare Pages Functions の `POST /api/token`）と `/.well-known/assetlinks.json` はこのリポジトリにない（`site/` に `.well-known/` も `functions/` もない）。Issue #795 は依存タスクとして「assetlinks.json への Play App Signing key SHA-256 追加（運用タスク）」を挙げている。
- **O-7 [確定]**: PKCE は使っていない。Issue #537 のコメントで、上流が PKCE 非対応と判断して BFF 方式に変更した経緯がある。scope は `oauth_bff_config.dart:58` で `'openid user'` に固定されている。
- **O-8 [確定]**: OAuth 関連 Issue の状態。Issue #889（OAuth でコメント投稿を動かす Epic）は not_planned でクローズ済み（「OAuth ではないが PR #971 の WebSocket 投稿で解決」）。#795 / #581 は on-hold のままオープン。

### 2.2 debug で OAuth を試したときに止まりうる箇所

| ID | 候補 | 確度 | 根拠 / 補足 |
|---|---|---|---|
| OC-1 | debug ビルドの署名 SHA-256 が assetlinks.json に登録されていない。Android 12 以降は、検証されていない App Link がブラウザで開くため、コールバックがアプリに戻らない | 中（クロスレビューでは最有力） | debug keystore は開発機ごとに異なる。assetlinks の中身はリポジトリ外なので [不明] |
| OC-2 | applicationId が assetlinks.json の `package_name` と一致しない（`app_id.properties` がないときのフォールバック値など） | 中 | O-4 |
| OC-3 | dart-define 未指定でボタン自体が出ない | 高（IDE から素の `flutter run` の場合） | O-2 |
| OC-4 | BFF が未デプロイ、BFF の設定ミス、または上流の redirect_uri 登録との不一致 | 不明 | O-6 |
| OC-5 | `flutter_deeplinking_enabled` を無効化していない影響 | 欠落は [確定]、影響は [推測] で中 | 下の注記を参照 |
| OC-6 | scope に `offline_access` などがなく、refresh_token が返らない。将来 Bearer で生放送 API を叩くなら、追加の scope も必要になる可能性がある | 中 | 上流の仕様を確認する必要がある |
| OC-7 | `android:taskAffinity=""` と `launchMode="singleTop"` の組み合わせで、ブラウザから戻ったときに別タスクで 2 つ目の MainActivity が起動し、元の画面に結果が届かない | 低〜中 | 実機で確認する必要がある |

**OC-5 の注記**: クロスレビューでは、評価が次の 2 つに分かれた。

- (a) Flutter が URL を Navigator に `pushRoute` しようとし、ルート生成器がないので debug ではエラーログが出る。ただし intent 自体は消費されないため、app_links のストリームには URL が届き、実害はない。こちらがより有力。
- (b) バージョンによってはフローを阻害する。

どちらであるかは実機確認が必要。いずれにしても、公式手順どおり無効化するのが妥当。

### 2.3 OAuth の位置づけ

OAuth を「直す」には、ログインフローを通すだけでなく、取得したトークンを API 呼び出しに使う配線（#795 の `AuthHeaderResolver` 構想）が要る。現状はその前段階で止まっている。コメント投稿は PR #971 の WebSocket 経由で解決済みなので、OAuth が必要になる具体的なユースケースが現時点にあるかも [不明]。タイムシフトに OAuth が必要かも [不明] だが、参考実装の Hakumai は Bearer 認証を使っている（[推測] 中）。

---

## 3. タイムシフトの分析

### 3.1 実際に通るコード経路（[確定]）

```
ConnectionSupervisor → _SessionWsClientAdapter.connectAndResolveEndpoints() (lib/main.dart)
  └─ ProgramInfoResolver.resolve()  GET https://live2.nicovideo.jp/watch/{lv}/programinfo
       ├─ data.rooms が空 → ProgramInfoResolveException('Program info response has no rooms')
       │     (lib/data/connection/program_info_resolver.dart:115)
       │     ※ status の解析 parseProgramStatus は :178 にあり、ここには到達しない
       │     → isTimeshift 判定なし / onTimeshiftDetected 不発 / 「未対応」ダイアログも出ない
       └─ main.dart:1021 の catch で title だけ拾い、WebSocket フォールバックへ
            └─ SessionWsClient(lv: lv)  (main.dart:1037)  ← Cookie なし
                 URL は固定値 wss://a.live2.nicovideo.jp/wsapi/v2/watch/{lv}
                 (lib/domain/connection/session_ws_client.dart:212)  ← audience_token なし
                 → HTTP 400 → connectFailed → sessionWsConnectFailed（「接続失敗」表示）
```

Issue #654 の実機報告（プレミアム会員、`lv350354888`）は「title は返るが `rooms=[]`」で、上の経路と一致する。報告されたエラー文は `Connection to 'https://a.live2.nicovideo.jp:0/wsapi/v2/watch/lv350354888#' was not upgraded to websocket, HTTP status code: 400`。

### 3.2 確定事実

- **T-1 [確定]**: `lib/main.dart:87` の `kTimeshiftFetchEnabled = false`。有効なら `_tryStartTimeshiftInitial`（`:682`）が `fetchInitial` を呼ぶが、無効なので「未対応」ダイアログを出して return するだけ。ただし 3.1 のとおり、今の実機応答ではこの関数まで到達しない。
- **T-2 [確定]**: テストに穴がある。`test/data/connection/program_info_resolver_test.dart:60-85` が検証しているのは「`status=ended` かつ `rooms` が空でない」形だけで、#654 で報告された実際の形（ended かつ `rooms=[]`）を成功系として扱うテストはない。
- **T-3 [確定]**: フォールバック用 WebSocket が `_buildConnectHeaders`（`session_ws_client.dart:654`）で付けるのは User-Agent と `Origin: https://live.nicovideo.jp` だけ。Cookie と audience_token は付かない。
- **T-4 [確定]**: audience_token 付きの WebSocket URL を取る処理はすでにある。PR #971 で、視聴ページの `<script id="embedded-data" data-props>` から `site.relive.webSocketUrl` を取り出す `_resolveWebSocketUrl` / `_fetchWatchPageWsUrl` / `_extractWsUrlFromHtml`（`lib/main.dart:1206-1300` 付近）が実装済み。ただし呼び出し元はコメント投稿用の `_ensureCommentPostWs` だけで、視聴やタイムシフトの経路では使われていない。
- **T-5 [確定]**: WebSocket メッセージの解析は汎用的。`SessionWsMessageParser.extractEndpoints`（`session_ws_client.dart:869`）は、メッセージ中の view API の URL を広く拾う。そのため `messageServer.data.viewUri` を視聴経路で使う場合も、パーサーを改修せずに済む見込み。
- **T-6 [確定]**: `NdgrTimeshiftClient._fetch`（`lib/domain/connection/ndgr_timeshift_client.dart`）は認証ヘッダも Accept ヘッダも付けない素の GET。ただしライブ用の `NdgrClient._fetch`（`ndgr_client.dart:427`）も同じで、ライブは動いている。
- **T-7 [確定]**: 放送終了を検出したときの扱い（`ConnectionSupervisor.endBroadcast()`）は、タイムシフト取得を止めない。取得処理は `TimeshiftFetchController` として supervisor の外で独立して動く設計になっている。

### 3.3 推測・不明点

| ID | 内容 | 区分 |
|---|---|---|
| TU-1 | HTTP 400 の原因は audience_token がないこと | [推測] 中〜高。コミュニティ実装での通説で、トークン付き URL を使う PR #971 の投稿経路が通っていることとも整合する |
| TU-2 | エラー文の `:0` と末尾の `#` は、dart:io が `wss://` を `https://` に組み直すときの表示上の産物で、実際には 443 番ポートに接続している | [推測] 高 |
| TU-3 | トークン付きの WebSocket にタイムシフト番組でつないだとき、`messageServer` で viewUri が返るか | [不明]。Hakumai はそうしていると #654 のコメントにある |
| TU-4 | タイムシフト視聴権（予約やチケット）やプレミアム会員であることが必要か。権利がないと embedded-data の `webSocketUrl` が空になる、など | [不明]。空のとき、現行の `_extractWsUrlFromHtml` は黙って null を返す |
| TU-5 | embedded-data に放送状態（ENDED など）が含まれていて、programinfo の代わりにタイムシフト判定に使えるか | [推測] 中 |
| TU-6 | 終了放送に対して、NDGR の `view?at=now` → `next.at` → previous / backward という流れが成立するか。ライブ側では同じ流れが実証されている | [不明]。`at=<終了時刻>` を使う実装もあり得る |
| TU-7 | NDGR がタイムシフトで認証ヘッダを要求するか（#655） | [推測] 低。認可は viewUri のクエリに埋まっていると考えられ、ライブはヘッダなしで動いている |
| TU-8 | 署名付き viewUri の有効期限が、長時間の backward 走査より短い可能性 | [不明] |

---

## 4. 関連するが本件の原因ではないもの

- コメント投稿で匿名トークンを検出したとき、`resolvedWsUri = null` にしてトークンなしの固定 URL と Cookie で接続する（`lib/main.dart:1145`, `:1182`）。TU-1 が正しければ、この経路も 400 になるおそれがある。投稿側の潜在バグ候補。[推測] 中。
- `TimeshiftFetchPanel` は、コントローラが null でない限り常に描画される（`lib/presentation/screens/comment_screen.dart:3537`）。UI の表示条件の問題で、取得が失敗する原因ではない。

---

## 5. 推奨する作業順序（Issue 化の候補）

各タスクは小さく分けて、1 PR に 1 つの責務とする。新しい Issue を作る前に、既存の Issue（#654 / #655 / #795）と重複していないか確認すること。

### タイムシフト

1. **[調査] 実機の応答を記録する**（実装の前提）
   - 終了放送の programinfo の応答全体、embedded-data の `site.relive.webSocketUrl` の有無、トークン付き WebSocket での `messageServer` の内容、その viewUri に対する `at=now` の応答を記録する。プレミアム会員と一般会員の両方で取る。
   - 受け入れ基準: TU-3〜TU-6 の [不明] が事実として記録され、#654 に反映されている。
2. **[修正] `ProgramInfoResolver` が `rooms=[]` でも status と title を返せるようにする**
   - たとえば viewUri を nullable にする、または ended のときだけ別の結果型を返す。呼び出し側も含めて設計を決める。
   - 受け入れ基準: ended かつ `rooms=[]` の fixture テストを、既存の `program_info_resolver_test.dart` の該当 group に追加する。ended の放送は WebSocket フォールバックで 400 にならず、タイムシフトとして扱われる。
   - 注意: この修正だけを入れて `kTimeshiftFetchEnabled=false` のままなら、「未対応」ダイアログが正しく出るようになる（誤った「接続失敗」表示の解消）。これだけでも価値がある。
3. **[実装] viewUri の取得経路を作る**（1 の結果次第）
   - `_fetchWatchPageWsUrl` を視聴とタイムシフトの経路にも配線し、WebSocket から `messageServer.viewUri` を得てから `NdgrTimeshiftClient` に渡す（Hakumai 方式）。
   - 視聴権がなく `webSocketUrl` が空の場合は、「再試行」を案内しないエラーとして UI に出す（#639 の方針）。
4. **[有効化] `kTimeshiftFetchEnabled = true` に戻し、「未対応」ダイアログと関連テストを外す**
   - 受け入れ基準: 実機でコメントが段階的に取得できることを確認し、スクリーンショットを PR に添付する。

### OAuth

1. **[調査] どこで止まっているかを特定する**（「6. 検証手順」の OAuth 項目）。症状の聞き取りも含む。
2. **[修正・小] `flutter_deeplinking_enabled=false` を追加する**（app_links の公式手順に合わせる）。影響範囲は App Links の受信経路だけ。
3. **[設計] #795 の再評価**: コメント投稿は WebSocket で解決済みなので、OAuth のトークンが必要な具体的な API（タイムシフトに必要か、など）が見つかるまで on-hold を続けるか判断する。判断は人間オーナーに委ねる。

---

## 6. 検証手順

| 対象 | 手順 | 判定 |
|---|---|---|
| タイムシフトの経路（3.1） | 終了放送の lv を開き、logcat を見る | `programinfo resolution failed, falling back to WebSocket: ... Program info response has no rooms` が出れば 3.1 の経路で確定 |
| TU-1（400 の原因） | WebSocket の upgrade ヘッダ付きで、固定 URL と embedded-data 由来の URL にそれぞれ `curl -i` する | 前者が 400、後者が 101 なら TU-1 は確定 |
| TU-6（at=now） | 実際の viewUri に `&at=now` を付けて取得し、`protoc --decode_raw` などで `next` / `backward` / `previous` の有無を見る | — |
| OC-1 / OC-2（App Links） | `adb shell pm get-app-links <applicationId>` | 対象ホストが `verified` でなければ App Links 未検証 |
| App Links の受信配線 | `adb shell am start -a android.intent.action.VIEW -d 'https://<bffHost>/auth/callback?code=x&state=y' <applicationId>` | 状態不一致（stateMismatch）系のスナックバーが出れば、受信からサービスまでの配線は生きている |
| OC-5 | 上と同じ操作のときの logcat | ルート生成エラーが出るか。app_links のストリームに届いているか |
| OC-7 | コールバック後に `adb shell dumpsys activity activities` を実行する | MainActivity が重複していないか |

注意: 公開リポジトリなので、BFF のホスト名、client_id、トークン、`user_session` の値を Issue や PR、ログ貼り付けに含めないこと。

---

## 7. 参照

- Issue: #537（App Links + BFF 方針。PKCE 非対応の判断）、#580 / #581 / #889（コメント投稿と OAuth）、#639（タイムシフトの複合原因）、#654（viewUri 取得経路と Hakumai との比較）、#655（NDGR の認証ヘッダ）、#795（OAuth を release で有効化し、Bearer と Cookie を併用する構想）
- PR: #791 / #794（OAuth のデータ層と UI）、#971（WebSocket 投稿、embedded-data から webSocketUrl を取得）
- 外部: app_links の Android セットアップ（`flutter_deeplinking_enabled` の無効化手順）、Hakumai `NicoManager.swift`（#654 のコメントに記載のリンク）
