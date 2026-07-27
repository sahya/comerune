# リリースダウンロード統計の仕組み

GitHub Releases のダウンロード数の推移を記録・可視化する仕組みの説明。

## 背景

GitHub の Releases API（`/repos/{owner}/{repo}/releases`）が返す
`download_count` は **その時点の累計値** であり、過去の推移を遡って取得する
公式 API は存在しない。そのため推移を見るには、定期的にスナップショットを
取って自前で時系列化する必要がある。記録開始より前のデータは復元できない。

## 構成

```
┌─ GitHub Actions (release-metrics.yml, 毎日 04:23 JST) ─┐
│  Releases API から全リリースの download_count を取得    │
│  → 1 行の JSON にして metrics-data ブランチに追記       │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
      metrics-data ブランチ  data/release-downloads.jsonl
      （orphan ブランチ。コード履歴とは独立。手動編集しない）
                          │ raw.githubusercontent.com 経由で fetch
                          ▼
      site/metrics/ （https://comerune.pages.dev/metrics/）
      素の SVG で折れ線グラフ描画（外部ライブラリなし）
```

- **収集**: `.github/workflows/release-metrics.yml`
  - 日次 cron + `workflow_dispatch`（手動実行可）
  - draft リリースは除外。prerelease はフラグ付きで記録
- **保存**: `metrics-data` ブランチの `data/release-downloads.jsonl`
  - 1 行 = 1 スナップショット（JSON Lines）
  - 例: `{"ts":"2026-07-27T19:23:00Z","releases":[{"tag":"v1.2.0","prerelease":false,"published_at":"...","assets":[{"name":"comerune.apk","count":123}]}]}`
  - main に日次コミットを積まないため・CI を毎日走らせないための分離
- **閲覧**: `site/metrics/index.html` + `app.js`
  - Cloudflare Pages で `site/` と一緒に配信される
  - データ取得のため `site/_headers` で `/metrics/*` のみ
    `connect-src` に `https://raw.githubusercontent.com` を追加している

## 運用メモ

- 初回はワークフローを `workflow_dispatch` で一度手動実行すると、
  `metrics-data` ブランチが作成されデータ蓄積が始まる
- データがまだ無い間、統計ページは「まだデータがありません」を表示する
  （ページ自体は壊れない）
- スナップショットは追記のみ。壊れた行があっても閲覧ページは該当行を
  読み飛ばして継続する
- 記録先を将来 Cloudflare Workers + D1 等に移す場合も、この JSONL を
  そのままインポートすれば履歴は引き継げる（データはリポジトリに残るため
  移行先の選択に依存しない）

## 制約・注意

- 過去（収集開始前）のダウンロード数の推移は取得不能（API 仕様上の制約）
- `download_count` はアセット（APK 等）のダウンロードのみが対象。
  ソースコード zip/tar.gz（自動生成物）のダウンロードはカウントされない
- 1 日 1 点の粒度。日内の変動は追わない
