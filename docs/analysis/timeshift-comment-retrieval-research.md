# タイムシフト（終了放送）のコメント取得: 調査メモ

調査日: 2026-11-21
基準コミット: `20b7e24`（5 章は、実装 PR #1050 の `3cb5757` 時点のコードを説明しています）

## このドキュメントについて

終了した放送（タイムシフト）のコメントを、ニコニコ生放送の新しいコメントサーバー（NDGR）からどう取得するかを調べた結果をまとめたものです。調べたのは、公開されている他のクライアントの実装と、公式の protobuf 定義です。実装の PR では、この結果をもとに取得経路を決めました。

**根拠のラベル**

- **確認済み**: 公開リポジトリのソースコードで確かめたもの。実際のサーバーの挙動ではなく、「その実装がそう動くように書かれている」という意味です。
- **推測**: 状況証拠によるもの。
- **不明**: 実機とログイン済みのアカウントがないと判断できないもの。

**注意**: 調査環境からはニコニコに接続できません。そのため、ここに書いたことは実機ではまだ確認していません。確認の手順は「6. 実機での確認手順」にまとめました。

---

## 1. 結論

| 項目 | 結論 | 根拠 |
|---|---|---|
| 終了放送の viewUri の取り方 | 視聴ページの埋め込みデータ `site.relive.webSocketUrl` から WebSocket の URL を取り、その WebSocket に `startWatching` を送ります。返ってくる `messageServer` メッセージの `data.viewUri` が viewUri です | 確認済み（4 実装で一致） |
| programinfo の `rooms` | 終了放送では空になります。viewUri の取得には使えません | 実機報告（#654） |
| 過去コメントの読み方 | `view?at=now` の応答（なければ `next.at` を辿った先）に出てくる `backward` から、PackedSegment を `next.uri` で辿ります（4.2 で実装ごとの違いを説明） | 確認済み（3 実装。このアプリの `NdgrTimeshiftClient` は NdgrClientSharp と同じ 2 段階の方式） |
| NDGR への認証ヘッダ | `Authorization` などの認証ヘッダを付けている実装はありません。Hakumai は User-Agent だけ、n-air はヘッダを指定していません。ただし tsukumijima/NDGRClient は、ブラウザに似せたヘッダ一式（origin、referer など）を付け、`user_session` の Cookie を持つ HTTP セッションで取得しています。Cookie なしでも取得できるかは U-8 | 確認済み（ヘッダの内容）／不明（Cookie の要否） |
| 視聴権がないとき | 視聴ページの `webSocketUrl` が空になります | 確認済み（2 実装） |
| 予約・視聴権の有効化 | 予約（POST）と視聴開始（PATCH）の API があります。ただし視聴権を使ってしまうので、このアプリは勝手に実行しません | 確認済み（2 実装。`nico.py` は実行前に利用者に確認を求める） |

---

## 2. 調べた実装

| 実装 | 言語 | 参照したコミット | 終了放送への対応 |
|---|---|---|---|
| [tsukumijima/NDGRClient](https://github.com/tsukumijima/NDGRClient) | Python | `b450b9d78cb3` | あり（予約処理も含む） |
| [TORISOUP/NdgrClientSharp](https://github.com/TORISOUP/NdgrClientSharp) | C# | `f94655beb125` | README に、放送中の番組の過去コメントとタイムシフトからコメントを取得できる、という趣旨の記載がある（要約）。viewUri の取得は範囲外 |
| [honishi/Hakumai](https://github.com/honishi/Hakumai) | Swift | `20cfa667d188` | あり（番組開始時刻から順方向に読む） |
| [n-air-app/n-air-app](https://github.com/n-air-app/n-air-app) | TypeScript | `8a7522cba024` | ライブ向け（backward を辿る処理はある） |
| [fireattack/python-scripts](https://github.com/fireattack/python-scripts)（`nico.py`） | Python | `0433927` | あり（タイムシフトのダウンロード用） |
| [n-air-app/nicolive-comment-protobuf](https://github.com/n-air-app/nicolive-comment-protobuf) | proto | `a577cae` | 公式の protobuf 定義 |

行番号は、上の各コミットの時点のものです。

---

## 3. viewUri の取り方

### 3.1 視聴ページ → WebSocket → `messageServer`（確認済み）

1. Cookie の `user_session` を付けて、`https://live.nicovideo.jp/watch/<lv>` を取得します。
   - tsukumijima/NDGRClient `ndgr_client/ndgr_client.py` L1043-1072
   - モバイルの User-Agent を送ると `sp.live.nicovideo.jp` にリダイレクトされ、埋め込みデータのないページが返ります。デスクトップの User-Agent を使う必要があります（**推測**。このアプリの既存実装のコメントにある知見で、上の実装のソースには記載がありません）。
2. `<script id="embedded-data" data-props="...">` の JSON から `site.relive.webSocketUrl` を読みます。
3. その URL の WebSocket に接続し、`startWatching` を送ります。
   - tsukumijima: `{"type":"startWatching","data":{"reconnect":false}}`（L1196-1270）
   - Hakumai: `{"type":"startWatching","data":{}}`（`NicoManager.swift` L44-46）
   - 動画のストリームを要求するフィールド（`stream`）は要りません。
4. サーバーから `ping` が来たら `pong` を返します。`messageServer` メッセージの `data.viewUri` を受け取ったら、WebSocket を閉じます。

Hakumai は Cookie ではなく OAuth の API（`api.live2.nicovideo.jp/api/v1/wsendpoint`）で WebSocket の URL を取ります。その後の `startWatching` → `messageServer` の流れは同じです（`NicoManager.swift` の `requestLiveInfo` L487 〜 `requestWebSocketEndpoint` L558-592、L622）。

### 3.2 視聴権

- **視聴権がないとき**（確認済み）: `webSocketUrl` が空文字になります。`nico.py` は、このとき `userProgramWatch.canWatch` が `false` であることも見ています。
- **予約と視聴開始**（確認済み、2 実装）: `webSocketUrl` が空のとき、次の 2 つを順に行ってから視聴ページを取り直します。
  - `POST https://live2.nicovideo.jp/api/v2/programs/<lv>/timeshift/reservation`（予約）
  - 同じ URL への `PATCH`（視聴期限の開始）
  - tsukumijima/NDGRClient（L1145-1190）はログイン済みなら自動で実行し、予約に失敗すると「Are you premium member?」という例外を投げます。
  - `nico.py`（L208-229）は、実行する前に利用者に確認を求めます（自動で実行するオプションもある）。
- **アプリでの扱い**: 視聴開始（PATCH）は視聴期限のカウントを始めてしまいます。そのため、このアプリは予約も視聴開始も自動では行わず、「視聴できない」と伝えるだけにしました。

### 3.3 プレミアム会員かどうか

コメントを取れるかどうかは、プレミアム会員かどうかだけでは決まりません。予約の有無、視聴期限、チケットの要否によって決まります。

- 予約していないプレミアム会員は取得できません。
- 番組によっては、予約済みの一般会員でも取得できます。

参考にした実装は、どれも `webSocketUrl` が空かどうかで取得の可否を判断しています。会員種別を先に判定している実装は見つかりませんでした。

ただし `nico.py`（L209-239）は、取得できない理由を埋め込みデータから見分けています（確認済み）。

- `userProgramWatch.canWatch`: 視聴できるか
- `userProgramWatch.isCountryRestrictionTarget`: 地域制限の対象か
- `programWatch.condition.payment == 'Ticket'` と `userProgramWatch.payment.hasTicket`: チケットが必要か、持っているか

会員種別を先に判定して案内する機能（#642）では、これらが判定の候補になります。実際の値が番組や会員種別によってどう変わるかは、実機で確かめる必要があります（U-5）。

---

## 4. 過去コメントの読み方

### 4.1 protobuf の定義（確認済み）

出典: n-air-app/nicolive-comment-protobuf `proto/dwango/nicolive/chat/service/edge/payload.proto`

- `ChunkedEntry`: `oneof entry { MessageSegment segment = 1; BackwardSegment backward = 2; MessageSegment previous = 3; ReadyForNext next = 4; }`
  - `ReadyForNext`: `int64 at = 1`
- `MessageSegment`: `from = 1`、`until = 2`、`uri = 3`
- `BackwardSegment`: `until = 1`、`PackedSegment.Next segment = 2`、`snapshot = 3`
- `PackedSegment`: `repeated ChunkedMessage messages = 1`、`Next next = 2`、`snapshot = 3`

### 4.2 逆方向に読む方式（多数派。確認済み）

tsukumijima/NDGRClient（`downloadBackwardComments` L866-1028）、NdgrClientSharp（`NdgrPastCommentFetcher.cs` L40-130）、n-air-app（`NdgrClient.ts` L70-170）の 3 つが使う方式です。

**共通する点**

1. `viewUri?at=now` から始めます。
2. どこかの応答で `backward.segment.uri` を見つけたら、その URI から PackedSegment を取得し、`next.uri` を辿って、より古い方へ読みます。

**違う点**

| 項目 | 実装ごとの扱い |
|---|---|
| `backward` を探す手順 | NdgrClientSharp: `at=now` で `next.at` を得てから、`at=<next.at>` の応答で探す（2 段階）。NDGRClient と n-air: `at=now` の応答も含めて最初に出てきた `backward` を使い、なければ `next.at` を辿る |
| どこまで辿るか | NDGRClient と NdgrClientSharp: `next.uri` がなくなるまで（NdgrClientSharp は件数の上限あり）。n-air: 指定の件数（`numBackward`）に達したら止める |
| `previous` を読むか | 読む: NdgrClientSharp、n-air。読まない: NDGRClient |
| リクエストの間隔 | NDGRClient は 10ms、n-air は 7ms、NdgrClientSharp は間隔なし |
| 重複の除外 | NDGRClient はしない |

**このアプリの `NdgrTimeshiftClient`** は NdgrClientSharp と同じ 2 段階の方式です。`previous` も読み、backward のリクエスト間隔は 7ms で、メッセージ ID で重複を除外します。

### 4.3 順方向に読む方式（Hakumai。確認済み）

- `viewUri?at=<番組開始時刻の UNIX 秒>` から始めます（`NdgrClient.swift` L46-64）。
- `next.at` を辿りながら `segment` を順に読み、`next` がなくなったら終了します。
- `backward` と `previous` は読みません（L117-186）。
- HTTP 429 が返ったら 10 秒、20 秒、40 秒、80 秒と待ってから再試行します（`NdgrRequestThrottle.swift`）。

逆方向の方式が終了放送でうまく動かなかった場合の、代わりの方式になります。

---

## 5. このアプリでの実装との対応

| 手順 | 実装 |
|---|---|
| 終了放送の検出 | `ProgramInfoResolver`（`status=ended` なら、`rooms=[]` でもタイムシフトとして扱う。#1015） |
| 視聴ページから WebSocket の URL を取る | `WatchPageWebSocketUrlResolver`（コメント投稿の経路と共用） |
| WebSocket から viewUri を取る | `TimeshiftViewUriResolver`（`startWatching` の data は空。取得後すぐに閉じる。タイムアウトは 15 秒） |
| 過去コメントの取得 | `NdgrTimeshiftClient` と `TimeshiftFetchController`（既存） |
| 取得を始める判断 | `TimeshiftFetchStarter`（番組ごとに 1 回だけ解決する。番組を切り替えたら状態を戻す。ライブで見ていた放送が終わっただけのときは何もしない〔#1017、#1018 の `hasStreamedSinceConnectionStart`〕） |
| 失敗したとき | 理由ごとのダイアログを lv ごとに 1 回だけ出す（未ログイン／視聴できない／取得できない） |
| Cookie の送り先 | 視聴ページと同じホストへのリダイレクトと、`wss://*.nicovideo.jp` の WebSocket だけ |

---

## 6. 実機での確認手順

ログを貼るときは、Cookie、トークン、署名付きの URL（`audience_token` や viewUri のクエリ）を伏せてください。

1. 予約済みで、視聴期限内のタイムシフトを開きます。コメントが段階的に取得されることを確認します。
2. 予約していないタイムシフトを開きます。「このタイムシフトは現在視聴できません」のダイアログが出ることを確認します。
3. ログアウトした状態で開きます。ログインを促すダイアログが出ることを確認します。
4. 500 件、1000 件、全件のボタンで続きを取得できることを確認します。時間を置いてから押した場合（署名付き URL の有効期限）も確認します。
5. logcat に `Timeshift view URI unavailable: <理由>` が出た場合は、その理由を記録します。

---

## 7. 実機でないと判断できないこと

| ID | 内容 | 追跡先 |
|---|---|---|
| U-1 | 終了放送で `at=now` が `next` を返し、`at=<next.at>` が `backward` を返すか。backward を辿って番組の冒頭まで届くか | #654（Phase 1）、#1050 の確認手順 |
| U-2 | `previous` の使い方の違いで、取得できる範囲が変わるか | #654（Phase 1） |
| U-3 | 署名付き viewUri、backward、segment の URL の有効期限。「全件取得」の途中で切れないか | #1050 の確認手順 2 |
| U-4 | 視聴権がないときに、WebSocket がどのエラーを返すか。NDGRClient は WebSocket の `error` と `disconnect` を扱い、`data.code` または `data.reason` を読んでいる（L1244、確認済み）。実際に返る値は不明 | #654（Phase 1） |
| U-5 | プレミアム限定の番組やチケットが必要な番組で、3.3 のフィールドが実際にどんな値になるか | #642 |
| U-6 | レート制限（HTTP 429 や 503）の条件 | #654（Phase 1） |
| U-7 | タイムシフトの視聴期限の現在の仕様 | #642 |
| U-8 | NDGR への取得に `user_session` の Cookie が必要か（このアプリは付けずに取得している） | #655 |

## 8. 次の作業の候補

- U-1〜U-3 の結果によっては、順方向に読む方式（4.3）を代わりとして加える。
- 予約や視聴開始をユーザーが自分で選べる導線を作る（視聴権を使うので、明示的な操作にする）。作る前に、ニコニコの利用規約を確認し、リクエストの回数や間隔にも配慮する。
- プレミアム判定による早めの案内（#642。U-5 の結果が前提）。
- 停止ボタンと取得処理の連動（#645）。
