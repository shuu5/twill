## MODIFIED Requirements

### Requirement: su-observer SKILL.md モード分離廃止

su-observer SKILL.md はモード判定テーブルを持ってはならない（SHALL）。ユーザー入力に対する行動選択は LLM が文脈から判断しなければならない（SHALL）。AskUserQuestion によるモード強制選択を行ってはならない（SHALL NOT）。

#### Scenario: ユーザーが「Issue 実装して」と指示した場合
- **WHEN** ユーザーが特定の Issue 番号とともに実装指示を出す
- **THEN** su-observer は AskUserQuestion でモードを確認せず、直接 co-autopilot を `cld-spawn` 経由で spawn し、`cld-observe-loop` で能動 observe を開始しなければならない（SHALL）

#### Scenario: ユーザーが「状況は？」と問い合わせた場合
- **WHEN** ユーザーが現在の進捗や状況確認を求める
- **THEN** su-observer は `cld-observe`（単発）で観察し、状況レポートをユーザーに返さなければならない（SHALL）

### Requirement: su-observer SKILL.md 常駐ループ構造

su-observer SKILL.md は Step 0（初期化）→ Step 1（常駐ループ）→ Step 2（終了）の 3 ステップ構造でなければならない（SHALL）。

#### Scenario: セッション初期化
- **WHEN** su-observer が起動される
- **THEN** Step 0 で bare repo 検証、SupervisorSession 復帰 / 新規作成、Project Board 状態取得、doobidoo 記憶復元を実行しなければならない（SHALL）

#### Scenario: 常駐ループでの controller spawn
- **WHEN** Step 1 の常駐ループ中にユーザーが controller 起動を必要とする指示を出す
- **THEN** 対象 controller を `cld-spawn` 経由で起動しなければならない（SHALL）。co-autopilot の場合は追加で `cld-observe-loop` を実行しなければならない（SHALL）

### Requirement: 全 controller の session:spawn 経由起動

su-observer から起動される全 controller（co-autopilot, co-issue, co-architect, co-project, co-utility, co-self-improve）は `session:spawn`（`cld-spawn`）経由で起動されなければならない（SHALL）。`Skill()` による直接呼出しを使ってはならない（SHALL NOT）。

#### Scenario: co-self-improve の起動
- **WHEN** su-observer がテスト実行を co-self-improve に委譲する
- **THEN** `cld-spawn` で co-self-improve セッションを起動しなければならない（SHALL）。`Skill(twl:co-self-improve)` 直接呼出しを使ってはならない（SHALL NOT）

### Requirement: session plugin スクリプト群の明示的参照

su-observer SKILL.md の Step 1 は session plugin スクリプト群を具体的に参照しなければならない（SHALL）: `cld-spawn`（spawn）、`cld-observe` / `cld-observe-loop`（observe）、`session-state.sh`（状態確認）、`session-comm.sh`（inject / 介入）。

#### Scenario: observe ループの実行
- **WHEN** co-autopilot が spawn された後
- **THEN** `cld-observe-loop` で能動 observe ループを実行しなければならない（SHALL）

#### Scenario: 介入が必要な問題の検出
- **WHEN** observe 中に問題パターンを検出した場合
- **THEN** `session-comm.sh` を使用して介入プロトコル（SU-1〜SU-7）に従い対応しなければならない（SHALL）

### Requirement: SU-1〜SU-7 制約の維持

モード分離廃止後も SU-1〜SU-7 制約は全て維持されなければならない（SHALL）。

#### Scenario: 介入実行時の 3 層プロトコル遵守
- **WHEN** su-observer が問題を検出して介入する
- **THEN** SU-1 に従い Auto / Confirm / Escalate の 3 層プロトコルに従わなければならない（SHALL）。SU-2 に従い Layer 2（Escalate）はユーザー確認が必要である（SHALL）

#### Scenario: 直接実装の禁止
- **WHEN** su-observer が Issue の実装を求められた場合
- **THEN** SU-3 に従い自ら実装を行ってはならない（SHALL NOT）。適切な controller に委譲しなければならない（SHALL）
