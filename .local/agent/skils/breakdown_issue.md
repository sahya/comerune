以下の仕様書を読み、Flutterアプリ開発用に実装可能な Issue に分解してください。

目的は、モバイルアプリに詳しくないオーナーでも承認しやすい形にすることです。
そのため、各 Issue は小さく、責務が明確で、受け入れ条件が具体的である必要があります。

要件:
- まず仕様の要約を作成する
- 不明点、未確定事項、仕様上の曖昧さを抽出する
- その後、Epic と複数の Issue に分解する
- Issue は依存順に並べる
- 1 Issue = 1責務を守る
- 各 Issue に scope / non-scope / acceptance criteria / test expectations を必ず付ける
- UI、状態管理、データアクセス、テストを一気に詰め込みすぎない
- オーナーが実装詳細を理解していなくても判断できる文章にする
- 仕様に書かれていない大きな挙動は勝手に補完しない
- 補完が必要な場合は assumption として明記する
- 各 Issue について「AI実装に向いているか」「人間承認が必要な論点があるか」を示す
- 最後に、並列実装できる Issue と、順序依存が強い Issue を分けて示す

出力フォーマット:

# 1. 仕様要約
- feature summary
- user-visible behavior
- main flows
- data/state impact
- validation/error points

# 2. 不明点 / 曖昧点 / 要確認事項
- itemized list

# 3. Epic
- title
- goal
- overall acceptance criteria

# 4. Issue Breakdown
Issue ごとに以下の形式で出力:

## Issue [番号]
### Title
### Goal
### Scope
### Non-scope
### Dependencies
### Acceptance Criteria
- [ ]
- [ ]
- [ ]

### Validation / Error Handling
### Test Expectations
- unit
- widget
- integration

### Assumptions
### AI実装適性
- High / Medium / Low

### Human Approval Needed
- Yes / No
- If yes, why

# 5. 実装順序の提案
- sequential issues
- parallelizable issues

# 6. リスク
- architecture risk
- requirement risk
- testing risk

以下が仕様書です:

[ここに仕様書を貼る]