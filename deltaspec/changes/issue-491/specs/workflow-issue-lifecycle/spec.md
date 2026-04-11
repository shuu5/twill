## ADDED Requirements

### Requirement: workflow-issue-lifecycle SKILL.md 新規作成

`plugins/twl/skills/workflow-issue-lifecycle/SKILL.md` が新規作成され、frontmatter に `type: workflow`, `user-invocable: true`, `spawnable_by: [controller, user]`, `can_spawn: [composite, atomic, specialist]` を含まなければならない（SHALL）。

#### Scenario: フロントマター検証
- **WHEN** `plugins/twl/skills/workflow-issue-lifecycle/SKILL.md` を読む
- **THEN** `type: workflow`, `user-invocable: true`, `spawnable_by: [controller, user]`, `can_spawn: [composite, atomic, specialist]` が全て存在する

### Requirement: workflow-issue-lifecycle N=1 不変量

workflow-issue-lifecycle の冒頭で `bash "${CLAUDE_PLUGIN_ROOT}/scripts/spec-review-session-init.sh" 1` を必ず呼び出さなければならない（MUST）。

#### Scenario: N=1 guard 呼び出し
- **WHEN** workflow-issue-lifecycle が起動される
- **THEN** spec-review-session-init.sh に引数 1 を渡して呼び出す

### Requirement: workflow-issue-lifecycle 入力インターフェース

per-issue dir の絶対パスを位置引数 `$1` として受け取り、`IN/draft.md`, `IN/arch-context.md`, `IN/policies.json`, `IN/deps.json` を読み込まなければならない（SHALL）。

#### Scenario: per-issue dir 読み込み
- **WHEN** `/twl:workflow-issue-lifecycle /abs/path/to/per-issue/0` が呼ばれる
- **THEN** `/abs/path/to/per-issue/0/IN/draft.md` を issue body として読み込む

### Requirement: workflow-issue-lifecycle round loop 全分岐実装

以下の全分岐を実装しなければならない（SHALL）:
1. CRITICAL findings (conf>=80) → body 修正 → 再レビューループ
2. WARNING only → body 修正 → ループ終了
3. clean (findings なし) → 即ループ終了
4. max_rounds 到達 → circuit_broken
5. codex gate 失敗 (2回) → codex_unreliable で OUT/report.json 書き込み + exit 0

#### Scenario: CRITICAL findings による再レビューループ
- **WHEN** spec-review aggregate に conf>=80 の CRITICAL findings が存在する
- **THEN** STATE を fixing にして body を修正し、同じ round 内で再レビューを実行する

#### Scenario: circuit_broken
- **WHEN** round が policies.max_rounds に達し CRITICAL findings がまだ残る
- **THEN** STATE を circuit_broken にして OUT/report.json に `status: circuit_broken` を書き込む

### Requirement: workflow-issue-lifecycle ファイル経由 handoff

workflow 内部で `IN/` 以外のパス・env var 参照をしてはならない（MUST NOT）。出力は `OUT/report.json` に `{status, issue_url, rounds, findings_final, warnings_acknowledged}` を書き込まなければならない（SHALL）。

#### Scenario: ファイル経由 I/O
- **WHEN** workflow が正常完了する
- **THEN** `OUT/report.json` が `status: done`, `issue_url`, `rounds` を含んで存在する
