## ADDED Requirements

### Requirement: explore loop gate
Phase 1 は少なくとも 1 回の `/twl:explore` 呼び出しを経た後、ユーザーに `[A] Phase 2 へ進む / [B] まだ探索したい / [C] explore-summary.md を手動編集したい` の 3 択を AskUserQuestion (loop-gate) で提示しなければならない（SHALL）。ゼロ探索で Phase 2 に進んではならない（MUST）。

#### Scenario: 1 ループで Phase 2 へ進む
- **WHEN** ユーザーが loop-gate で `[A] Phase 2 へ進む` を選択する
- **THEN** ループを終了し Step 1.5 へ遷移する

#### Scenario: 追加探索を選択する
- **WHEN** ユーザーが loop-gate で `[B] まだ探索したい` を選択し、懸念テキストを入力する
- **THEN** 入力テキストを `accumulated_concerns` に追加し、エスケープ処理後に `<additional_concerns>` タグで次の `/twl:explore` 呼び出しに注入して再ループする

### Requirement: accumulated_concerns 再注入
2 回目以降の `/twl:explore` 呼び出し時、`accumulated_concerns` を `${CLAUDE_PLUGIN_ROOT}/scripts/escape-issue-body.sh` でエスケープし `<additional_concerns>` XML タグに包んで引数として渡さなければならない（SHALL）。

#### Scenario: ユーザー懸念の再注入
- **WHEN** `[B]` 選択で 2 回目の `/twl:explore` を呼び出す
- **THEN** 前回のユーザー入力が `&`, `<`, `>` をエスケープした上で `<additional_concerns>` タグに包まれて探索エージェントに渡される

### Requirement: edit-complete-gate
`[C]` 選択時、ユーザーに `explore-summary.md` のパスを提示して編集を依頼した後、AskUserQuestion (edit-complete-gate) で `[A] 編集完了 / [B] 編集をキャンセル` を再提示しなければならない（SHALL）。

#### Scenario: 編集完了を確認する
- **WHEN** ユーザーが edit-complete-gate で `[A] 編集完了` を選択する
- **THEN** `explore-summary.md` を Read し直して loop-gate に戻る（ループを続行する）

#### Scenario: 編集をキャンセルする
- **WHEN** ユーザーが edit-complete-gate で `[B] 編集をキャンセル` を選択する
- **THEN** 直前の `explore-summary.md` の内容を維持して loop-gate に戻る

## MODIFIED Requirements

### Requirement: Step 1.5 をループ外に配置
`/twl:issue-glossary-check` の呼び出し（旧 Phase 1.5）をループ終了（`[A]` 選択）後に 1 度だけ発火させなければならない（SHALL）。SKILL.md 内の呼称は **`Step 1.5`** に統一しなければならない（MUST）（`Phase 1.5` ではない）。

#### Scenario: Step 1.5 の発火タイミング
- **WHEN** loop-gate で `[A] Phase 2 へ進む` が選択されてループを抜ける
- **THEN** `Step 1.5` として `/twl:issue-glossary-check` が 1 度だけ呼び出される

### Requirement: 既存セッション継続時の Phase 1 スキップ維持
既存セッション継続（`[A] 継続` 選択）時の Phase 1 スキップ動作は変更してはならない（MUST）。

#### Scenario: 既存セッション継続
- **WHEN** `explore-summary.md` が既に存在し、ユーザーが継続を選択している
- **THEN** Phase 1（explore loop）をスキップして Phase 2 に進む
