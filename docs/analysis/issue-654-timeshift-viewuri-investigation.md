# Issue #654 調査メモ: タイムシフト viewUri の正しい取得経路

- 対象 Issue: [#654 fix(timeshift): タイムシフト viewUri の正しい取得経路を調査・実装する](https://github.com/sahya/comerune/issues/654)
- 調査日: 2026-07-10
- 対象コード: `main` ブランチ時点（`f06a5de`）
- 本メモの位置づけ: コード読解 + 公開 OSS（Hakumai / N Air / viewer 系実装）との比較による原因分析と、
  後続の実装者（別セッションの Claude）向け実装指示。**本メモ自体はコード変更を含まない。**

---

## 1. 結論サマリ

### OAuth 認証は原因ではない

現在タイムシフトで失敗している経路（`programinfo` → WS フォールバック）には **OAuth が一切登場しない**。
両方とも `user_session` cookie 認証であり、`user_session` 自体は同じ放送で title の取得に成功している
（Issue 本文のユーザ報告: `lv350354888` で title 取得成功 / `rooms=[]`）。
したがって「OAuth 認証の不具合調査」は本 Issue の解決には不要。
OAuth が関係するのは Hakumai 方式（`wsendpoint` API）を採用する場合のみで、後述の通り **採用しないことを推奨**する。

### 真因は 2 つ（いずれも実装上の問題）

| # | 真因 | 場所 |
|---|------|------|
| 1 | `programinfo` の `rooms[]` は **live 配信専用**の構造で、ended（タイムシフト）では空。しかも `ProgramInfoResolver.resolve()` は `rooms` チェック（先）→ `status` パース（後）の順なので、**タイムシフトでは `status=ended` の判定に到達する前に例外で離脱**し、`onTimeshiftDetected` が実放送で一度も発火しない（事実上の dead path） | `lib/data/connection/program_info_resolver.dart:112-118`（rooms チェック）と `:178`（status パース） |
| 2 | WS フォールバックが `wss://a.live2.nicovideo.jp/wsapi/v2/watch/{lv}` を **audience_token なしでハードコード**しており、HTTP 400 で handshake 拒否される（ユーザ報告のエラーと一致）。正しい WS URL は watch ページ HTML の `<script id="embedded-data">` 内 `site.relive.webSocketUrl`（audience_token 付き）からしか得られない | `lib/domain/connection/session_ws_client.dart:210-212` |

### 決定的な事実: 正しい取得コードは既にリポジトリ内に存在する

`_SessionWsClientAdapter`（`lib/main.dart`）には watch ページを取得して embedded-data から
`site.relive.webSocketUrl` を抽出するコードが**既に実装済み**である:

- `_resolveWebSocketUrl` / `_fetchWatchPageWsUrl`（`lib/main.dart:1206-1266`）
  - desktop UA で `https://live.nicovideo.jp/watch/{lv}` を取得（mobile UA は `sp.` へ redirect され embedded-data が無いことも既にコメントで解明済み）
  - `<script id="embedded-data" data-props="...">` を正規表現抽出 → HTML unescape → JSON parse
  - `site.relive.webSocketUrl` を取り出し `frontend_id=9` を補完（`lib/main.dart:1268-1305`）
  - `audience_token` が `anonymous` の場合の検出も実装済み（`_isAnonymousWsUri`, `lib/main.dart:1182-1185`）

ただしこのコードは **コメント投稿経路（`_ensureCommentPostWs`）専用**に配線されており、
視聴・タイムシフトの endpoint 解決経路（`connectAndResolveEndpoints`）からは使われていない。
**この既存コードをタイムシフト経路に転用するのが最小修正**であり、OAuth もスコープ追加も不要。

### 正しいタイムシフト viewUri 取得経路（ブラウザ / Hakumai / viewer 系 OSS 共通）

```
watch ページ HTML (user_session cookie)
  → embedded-data の site.relive.webSocketUrl  (audience_token 付き。タイムシフト視聴権が無いと空文字)
  → WS 接続 + startWatching 送信
  → サーバから messageServer メッセージ受信: data.viewUri が NDGR view API URL
     (live / timeshift 共通。https://mpn.live.nicovideo.jp/api/view/v4/... 形式)
  → [timeshift の場合] viewUri を得たら WS は disconnect してよい (Hakumai と同じ)
  → viewUri を NdgrTimeshiftClient.fetchPastComments に渡す
```

`SessionWsClient` のメッセージパーサは `/api/view/v4/` を含む https URL を
`ndgrEndpointResolved` イベントとして抽出する実装が既にあるため
（`lib/domain/connection/session_ws_client.dart:869-904`）、
**messageServer の viewUri 抽出も追加実装なしで動く見込み**。

---

## 2. 現状コードの失敗フロー（実測報告と整合）

タイムシフト（ended 放送）を開いたときの実際の流れ:

1. `_SessionWsClientAdapter.connectAndResolveEndpoints`（`lib/main.dart:935`）が
   `ProgramInfoResolver.resolve()` を呼ぶ
2. `programinfo` API は title 等を返すが `rooms=[]`
   → `resolve()` は `'Program info response has no rooms'` の
   `ProgramInfoResolveException`（title のみ保持）を throw（`program_info_resolver.dart:112-118`）
   - **この時点で `data.status` は未パース**。例外には `programStatus` が載っていないため、
     呼び出し側は「ended だから rooms が無い（正常）」と「live なのに rooms が無い（異常）」を区別できない
3. `lib/main.dart:1021` の catch で title だけ通知し、**WS フォールバックへ落ちる**
4. フォールバックの `SessionWsClient` は `webSocketUri` override なしで生成される（`lib/main.dart:1037-1039`）
   → ハードコードの `wss://a.live2.nicovideo.jp/wsapi/v2/watch/{lv}`（token なし）へ接続
   → **HTTP 400**（ユーザ報告のスクリーンショットと一致）
5. `connectFailed` → `ConnectionSupervisor` が `SESSION_WS_CONNECT_FAILED` で失敗
6. `onTimeshiftDetected` は一度も呼ばれないため `TimeshiftFetchController.fetchInitial` は未実行
   → パネルのボタン類も `StateError`（Issue 記載のとおり）

補足: `lib/main.dart:989-991` の `onTimeshiftDetected?.call(programInfo.viewUri)` は
「`rooms[0].viewUri` が存在し **かつ** `status=ended`」のときだけ発火する設計だが、
ended では rooms が空なのでこの組み合わせは実放送では成立しない。
さらに仮に発火しても、渡している URI は **live 用 rooms の viewUri** であり、
タイムシフト用として正しい保証がない。

また `kTimeshiftFetchEnabled = false`（`lib/main.dart:87`）の暫定ガードにより、
現在は検出できたとしても「未対応ダイアログ」を出すだけになっている。

---

## 3. 参照 OSS の比較（裏取り）

### Hakumai（macOS 用ニコ生コメビュ, Swift）

`Hakumai/Managers/NicoManager/NicoManager.swift` を確認:

- WS URL は `https://api.live2.nicovideo.jp/api/v1/wsendpoint`（**OAuth Bearer 必須**）で動的取得
- WS 上の `WebSocketMessageServerData`（`messageServer` メッセージ）の `data.viewUri` を
  NDGR 接続先として `ndgrClient.connect(viewUri:beginTime:)` に渡す — **live / timeshift 共通**
- タイムシフトでは履歴取得後に `if isTimeShift { disconnect() }` で watch WS を切断

→ 「viewUri は WS の messageServer から得る」「timeshift では取得後 disconnect」という
   フロー自体はそのまま参考になる。ただし wsendpoint API は OAuth 前提。

### comerune で wsendpoint 方式を採らない理由（= OAuth に触れる必要がない理由）

comerune の OAuth BFF スコープは `openid user` のみ（`lib/data/auth/oauth_bff/oauth_bff_config.dart:58`）。
wsendpoint API の利用には生放送視聴系の OAuth スコープが別途必要になる
（Hakumai は専用の OAuth クライアント登録を持つ）。つまり wsendpoint 方式は
「スコープ追加申請 + BFF 改修 + トークン管理」がセットになり、本 Issue のスコープを大きく超える。
一方 embedded-data 方式は `user_session` cookie だけで完結し、しかも取得コードが実装済み。

**→ 本 Issue では embedded-data 方式を採用し、wsendpoint / OAuth 移行は将来の別 Issue とする。**
（将来 wsendpoint 方式へ移行する場合に限り、必要スコープの特定と BFF 側の対応可否を
別 Issue で調査すること。）

### viewer 系 OSS / 公開資料（embedded-data 方式の裏取り）

タイムシフトを含むコメント取得で「watch ページ embedded-data → `site.relive.webSocketUrl`
→ startWatching → `messageServer` の viewUri」という経路を使う実装・解説が複数公開されている:

- [rinsuki: ニコニコ生放送のコメントを取る](https://scrapbox.io/rinsuki/%E3%83%8B%E3%82%B3%E3%83%8B%E3%82%B3%E7%94%9F%E6%94%BE%E9%80%81%E3%81%AE%E3%82%B3%E3%83%A1%E3%83%B3%E3%83%88%E3%82%92%E5%8F%96%E3%82%8B)
- [kairi003: ニコ生(タイムシフト)ダウンローダーを書く](https://qiita.com/kairi003/items/62a487a2ab786cb0f502) /
  [kairi003/nicolive-dl](https://github.com/kairi003/nicolive-dl/blob/master/nicolive_dl/nicolive_dl.py)
  — **タイムシフトを対象にした**ダウンローダーが embedded-data の webSocketUrl を使用
- [pasta04: ニコ生チャット取得](https://qiita.com/pasta04/items/33da06cf3c21e34fc4d1)
- [DaisukeDaisuke: ニコ生コメントサーバーからのコメント取得備忘録 (NDGR/protobuf)](https://qiita.com/DaisukeDaisuke/items/3938f245caec1e99d51e)
  — 2024 年 6 月のインフラ刷新後、`messageServer` イベントの `data.viewUri` が
  NDGR (HTTP stream) の接続先になったことを記載
- [tor4kichi: ニコ生 配信情報 WebSocket の雑なまとめ](https://gist.github.com/tor4kichi/c5475c8362ee897911e43c46f0918023)

### nicoNewStreamRecorderKakkoKari（ニコ生新配信録画ツール(仮), C#）

タイムシフト録画・コメント取得に実績のある録画ツール
[guest-nico/nicoNewStreamRecorderKakkoKari](https://github.com/guest-nico/nicoNewStreamRecorderKakkoKari)
のソースを確認した結果、**本メモの推奨経路と同一のアーキテクチャ**だった:

- `src/rec/Html5Recorder.cs` — watch ページ HTML から
  `<script id="embedded-data" data-props="...">` を正規表現で抽出し、
  そこから WS 接続情報を得る（timeshift も `si.isTimeShift` で同経路を通る）
- `src/rec/MpnCommentGetter.cs`（NDGR 世代のコメント取得）:
  - viewUri は **watch WS のメッセージから抽出**:
    `mpnViewUri = util.getRegGroup(message, "\"viewUri\":\"(.+?)\"")`
    — つまり `messageServer` メッセージ経由（Hakumai と同じ）
  - `mpnViewUri + "?at=" + at`（live は `at=now`）で NDGR を fetch し、
    過去コメントは `ChunkedEntry.Backward.Segment.Uri` → `PackedSegment` を遡って取得
    — comerune の `NdgrTimeshiftClient`（`_nextBackwardUri` / backward segment 方式）と同型
  - NDGR fetch に **追加の認証ヘッダは付けていない**（§4 Non-scope の #655 の
    「viewUri は署名付き URL でありヘッダ不要の可能性が高い」という見立てと整合）
- `src/rec/TimeShiftCommentGetter.cs` は `thread` / `res_from` / `waybackkey` を使う
  **2024 年以前の旧コメントサーバ方式**であり、現行 NDGR 環境ではそのまま流用できない。
  同リポジトリを参考にする場合は Mpn 系（NDGR）クラスの方を見ること

Multi Comment Viewer / MCV 派生（NiconamaCommentViewer 等）も watch ページの
embedded-data から WS URL を取得する同型の方式（ブラウザと同じ経路）であり、
**視聴者クライアントで rooms[].viewUri をタイムシフトに使う実装は確認できなかった**。
N Air は配信者ツールであり、`programinfo.rooms` は「自分が配信中の番組」の投稿先解決用。
視聴者のタイムシフト読み出しに流用できる前提がそもそも誤りだった（Issue 本文の分析どおり）。

---

## 4. 実装指示（後続実装者向け）

方針: **embedded-data 方式でタイムシフト viewUri を解決する。** OAuth には触れない。
既存の `onTimeshiftDetected(Uri viewApiUri)` コールバック契約・
`TimeshiftFetchController.fetchInitial(Uri)`（`timeshift_fetch_controller.dart:129`）は変更しない。

### Step 1: `ProgramInfoResolver` — status を rooms より先にパースし例外に載せる

`lib/data/connection/program_info_resolver.dart`:

- `data['title']` の直後（rooms チェックの**前**）で `parseProgramStatus(data['status'])` を実行する
- `ProgramInfoResolveException` に `programStatus` フィールドを追加し、
  rooms 系の throw（`:113-118`, `:121-126`, `:132-137`）に title と同様に載せる
- 既存の戻り値 `ProgramInfo.programStatus` の挙動は不変（後方互換）

これで呼び出し側が「ended なので rooms が無い（正常系）」を識別できる。

### Step 2: watch ページ WS URL 解決を data 層クラスへ抽出

新規: `lib/data/connection/watch_page_ws_url_resolver.dart`

- `_SessionWsClientAdapter` の以下を移設（ロジックは実績があるのでそのまま流用）:
  - `_watchPageBaseUrl` / `_desktopUserAgent` / `_embeddedDataPattern` / `_maxWatchPageRedirects`
  - `_resolveWebSocketUrl` / `_fetchWatchPageWsUrl` / `_extractWsUrlFromHtml` / `_unescapeHtmlAttribute`
  - `_isAnonymousWsUri`
- 戻り値は「失敗理由を区別できる」形にする（例）:

```dart
enum WatchPageWsUrlFailure {
  fetchFailed,        // HTTP エラー / タイムアウト / embedded-data 不在
  emptyWebSocketUrl,  // 200 かつ embedded-data はあるが webSocketUrl が空
                      //   → タイムシフト視聴権なし・TS 期限切れの主シグナル
  anonymousToken,     // audience_token=...anonymous... → 未ログイン扱い
}

class WatchPageWsUrlResult {
  final Uri? wsUri;                      // 成功時のみ非 null
  final WatchPageWsUrlFailure? failure;  // 失敗時のみ非 null
}
```

- `emptyWebSocketUrl` の区別が重要: 現行コードは `webSocketUrl` が空だと単に `null` を返すが、
  タイムシフトではこれが「視聴権なし」の判定材料になる（#642 の UX ガードに渡す）
- `_ensureCommentPostWs` 側も新クラスを使うよう差し替え（重複実装を残さない）
- HTML スクレイピングなので、embedded-data の実 HTML 断片を fixture 化した
  lock-step テストを付ける（フォーマット依存を明示するという Issue 記載のリスク対策）

### Step 3: `_SessionWsClientAdapter.connectAndResolveEndpoints` にタイムシフト分岐を追加

`lib/main.dart` の `connectAndResolveEndpoints`:

```
programinfo 呼び出し
├─ 成功 & isTimeshift            → (A) タイムシフト WS 経路へ
├─ ProgramInfoResolveException
│   ├─ programStatus == ended    → title 通知後 (A) へ  ★現在 dead path になっている主経路
│   └─ それ以外                  → 従来どおり WS フォールバック（live 向け）
└─ 成功 & live                   → 従来どおり rooms viewUri を返す（変更なし）

(A) タイムシフト WS 経路:
 1. WatchPageWsUrlResolver.resolve(lv, userSession)
 2. 失敗 (emptyWebSocketUrl / anonymousToken / fetchFailed):
      onTimeshiftDetected は呼ばず、従来どおり
      SessionWsConnectException(broadcastEnded) を throw
      （ConnectionSupervisor は ended 表示、#642 ガードが視聴不可を案内）
      ※ 例外は投げても良いが必ず broadcastEnded 種別に畳む。
        参照先不在で他機能を壊さない（AGENTS.md の 2 段フォールバック規約）
 3. 成功: session_impl.SessionWsClient(
        lv: lv,
        webSocketUri: 取得した wsUri,           // ハードコード URL を使わない
        startWatchingMode: full,                 // messageServer を得るため full を第一候補
        connectHeaders: {'Cookie': 'user_session=...', 'X-Niconico-Session': ...},
      ) で接続
 4. ndgrEndpointResolved イベント（= messageServer.data.viewUri。
    既存パーサ session_ws_client.dart:887-891 が /api/view/v4/ を抽出）を待つ。
    タイムアウトは既存の endpointResolveTimeout (5s) をそのまま利用
 5. viewUri 取得後: WS を dispose（Hakumai と同じ「取得したら切る」方式。
    keepSeat 等の live 用タイマーを残さない）
 6. onTimeshiftDetected(viewUri) を発火
 7. SessionWsConnectException(broadcastEnded) を throw
    （ConnectionSupervisor を ended へ導く現行契約 lib/main.dart:1010-1014 を維持）
```

- live 経路（status=onAir）は**一切変更しない**こと（回帰リスク回避）
- 手順 4 で messageServer が来ない場合に備え、実機で startWatching の
  `full` / `minimal`（`data: {}`）両モードを確認する。ブラウザは stream 指定込みで送るため
  full が本命だが、TS では `chasePlay` 周りの応答が異なる可能性がある

### Step 4: 暫定ガードの解除

`lib/main.dart:77-87` のコメントに記載された手順どおり:

- `kTimeshiftFetchEnabled` を `true` に戻す（最終的には定数ごと削除）
- `_lastTimeshiftUnsupportedDialogLv`（`:398`）と `_showTimeshiftUnsupportedDialogIfNeeded`、
  未使用になる `AppStrings.timeshift.unsupported*` を削除
- `_tryStartTimeshiftInitial` の no-op 分岐を削除して `fetchInitial(viewApiUri)` を再配線

### Step 5: テスト（AGENTS.md のテスト肥大化ルールに従う）

- `test/data/connection/program_info_resolver_test.dart`（既存ファイルの既存 group に追加）:
  - `status=ended` + `rooms=[]` → 例外の `programStatus == ended` かつ title 保持
  - `status` パースが rooms チェックより先に行われること
- `test/data/connection/watch_page_ws_url_resolver_test.dart`（新規対象なので新規ファイル可）:
  - embedded-data あり（fixture HTML）→ wsUri 抽出 + `frontend_id=9` 補完
  - `webSocketUrl: ""` → `emptyWebSocketUrl`
  - `audience_token=...anonymous...` → `anonymousToken`
  - embedded-data 不在 / `sp.` redirect → `fetchFailed`
- adapter のタイムシフト分岐（既存の adapter/supervisor テストの group に追加）:
  - fake channel に `{"type":"messageServer","data":{"viewUri":"https://mpn.live.nicovideo.jp/api/view/v4/..."}}`
    を流し、`onTimeshiftDetected` がその viewUri で 1 回呼ばれ、WS が閉じられ、
    `broadcastEnded` が throw されること
  - watch ページ解決失敗時に `onTimeshiftDetected` が呼ばれないこと

### Step 6: 実機検証（受け入れ基準の実測）

1. プレミアムアカウント + 視聴権のあるタイムシフト（Issue の `lv350354888` 等）で
   初回 5,000 件の自動取得と `[500件取得]` 等のボタン動作を確認（#571 受け入れ基準）
2. 非プレミアム / 視聴権なし TS で #642 のガード表示になること
3. live 放送の視聴・コメント投稿に回帰がないこと
4. ブラウザ DevTools で同じ放送の `messageServer` メッセージを記録し、
   アプリが得た viewUri と同一形式であることを突き合わせ（スクリーンショットを PR に添付）

### 注意事項

- `user_session` を平文ログに出さない（既存の `SessionWsLogSanitizer` / 既存のヘッダマスキングを踏襲）
- embedded-data 取得はスクレイピングであり仕様変更に弱い。失敗時は
  例外を外へ漏らさず `broadcastEnded` に畳み、エラーログのみ残して継続する
  （公開リポジトリの 2 段フォールバック規約）
- 設定項目の追加はないため Export/Import 整合性チェックは対象外

### Non-scope（本 Issue に混ぜない）

- `NdgrTimeshiftClient._fetch` への auth header 追加 → #655 で扱う
  （NDGR viewUri は署名付き URL の可能性が高く、まず現状のまま実機確認してから判断）
- wsendpoint API / OAuth スコープ拡張への移行 → 将来の別 Issue（上記 §3 参照）
- live 経路の WS フォールバック URL 刷新（ハードコード除去を live にも波及させる件）
  → 動作している live 経路に触れるため別 Issue 推奨
- `ConnectionSupervisor` の timeshift 状態モデル化（#646）

---

## 5. Issue #654 チェックリストとの対応

| Issue のタスク | 本調査の結果 |
|---|---|
| 実際の API endpoint と request 形式の特定 | watch ページ embedded-data → `site.relive.webSocketUrl` → WS `startWatching` → `messageServer.data.viewUri`（§1, §3） |
| 仮説「埋め込み JS (`__INITIAL_STATE__` 等) 経由」 | ほぼ的中。正しくは `<script id="embedded-data" data-props>`。取得コードは既存（`lib/main.dart:1206`） |
| 仮説「`api.live.nicovideo.jp` の別 endpoint」 | `wsendpoint` が該当するが OAuth 必須のため不採用（§3） |
| 仮説「認証 cookie 追加 / X-Frontend-Id」 | 不要。`user_session` のみで watch ページ・WS とも到達可能。`frontend_id=9` はクエリで付与済み |
| 仮説「ticket 予約 API の必要性」 | viewUri 取得自体には不要。視聴権が無い場合は `webSocketUrl` が空になるため予約 API を呼ぶ必要はない（副作用リスクも回避できる） |
| OAuth 認証の失敗が原因か | **否**。現行の失敗経路に OAuth は関与しない（§1） |
