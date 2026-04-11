## ADDED Requirements

### Requirement: セッション初期化スクリプト（spec-review-session-init.sh）

`spec-review-session-init.sh <N>` は `/tmp/.spec-review-session-{hash}.json` を `{"total": N, "completed": 0, "issues": {}}` で作成しなければならない（SHALL）。hash は `printf '%s' "${CLAUDE_PROJECT_ROOT:-$PWD}" | cksum | awk '{print $1}'` で算出する。既存 state ファイルが存在する場合は上書き初期化する。

#### Scenario: 正常初期化
- **WHEN** `spec-review-session-init.sh 3` を実行する
- **THEN** `/tmp/.spec-review-session-{hash}.json` が `{"total":3,"completed":0,"issues":{}}` で作成される

#### Scenario: 既存 state 上書き
- **WHEN** 既存の state ファイルが存在する状態で `spec-review-session-init.sh 5` を実行する
- **THEN** state ファイルが `{"total":5,"completed":0,"issues":{}}` に上書きされる

---

### Requirement: PreToolUse gate スクリプト（pre-tool-use-spec-review-gate.sh）

`pre-tool-use-spec-review-gate.sh` は `Skill` ツールの `tool_input.skill` が `issue-review-aggregate` のとき、セッション state の `completed < total` であれば `permissionDecision: "deny"` を返さなければならない（SHALL）。deny メッセージには残り Issue 数と `/twl:issue-spec-review` 呼び出し指示を含める。

#### Scenario: completed < total でブロック
- **WHEN** セッション state が `{"total":3,"completed":1,"issues":{}}` の状態で `Skill(issue-review-aggregate)` が呼ばれる
- **THEN** PreToolUse hook が `{"permissionDecision":"deny","message":"spec-review 残り 2 Issue が未完了です。先に /twl:issue-spec-review を実行してください。"}` を返す

#### Scenario: completed == total でゲート通過
- **WHEN** セッション state が `{"total":3,"completed":3,"issues":{}}` の状態で `Skill(issue-review-aggregate)` が呼ばれる
- **THEN** PreToolUse hook がブロックせず、state file と lock file がクリーンアップされる

#### Scenario: state ファイル不在（フォールバック）
- **WHEN** セッション state ファイルが存在しない状態で `Skill(issue-review-aggregate)` が呼ばれる
- **THEN** PreToolUse hook はブロックしない（安全側フォールバック）

---

### Requirement: hooks.json への PreToolUse 登録

`hooks/hooks.json` の PreToolUse エントリに `"matcher": "Skill"` + `pre-tool-use-spec-review-gate.sh` を登録しなければならない（SHALL）。

#### Scenario: hooks.json 登録確認
- **WHEN** `hooks.json` の PreToolUse セクションを参照する
- **THEN** `{"matcher": "Skill", "hooks": [{"type": "command", "command": "...pre-tool-use-spec-review-gate.sh"}]}` エントリが存在する

## MODIFIED Requirements

### Requirement: check-specialist-completeness.sh の spec-review context フィルタ

`check-specialist-completeness.sh` は 3/3 specialist 完了時にマニフェストの context が `spec-review-` prefix を持つ場合のみ、セッション state の completed を flock 付きでインクリメントしなければならない（SHALL）。他 context には一切影響してはならない（MUST NOT）。

#### Scenario: spec-review context でインクリメント
- **WHEN** マニフェストの context が `spec-review-issue-123` で 3/3 specialist が完了する
- **THEN** `/tmp/.spec-review-session-{hash}.json` の completed が 1 増加する

#### Scenario: 他 context への非影響
- **WHEN** マニフェストの context が `phase-review-xxx` で 3/3 specialist が完了する
- **THEN** セッション state は変更されない

---

### Requirement: workflow-issue-refine Step 3b へのセッション初期化追加

`workflow-issue-refine/SKILL.md` の Step 3b 冒頭は `spec-review-session-init.sh <N>` 呼び出しを含まなければならない（SHALL）。N は処理する Issue 数である。

#### Scenario: セッション初期化ステップの存在確認
- **WHEN** `workflow-issue-refine/SKILL.md` の Step 3b を参照する
- **THEN** `spec-review-session-init.sh` の呼び出し手順が記載されている

---

### Requirement: architecture/domain/contexts/issue-mgmt.md への制約 IM-7 追記

`issue-mgmt.md` の Constraints セクションに制約 IM-7（「specialist spawn は機械的に保証しなければならない（SHALL）」）を追記しなければならない（SHALL）。

#### Scenario: IM-7 制約の存在確認
- **WHEN** `architecture/domain/contexts/issue-mgmt.md` の Constraints セクションを参照する
- **THEN** IM-7 として specialist spawn の機械的保証を規定するエントリが存在する

---

### Requirement: deps.yaml への新規スクリプト登録

`deps.yaml` に `spec-review-session-init` および `pre-tool-use-spec-review-gate` が script エントリとして登録されなければならない（SHALL）。

#### Scenario: deps.yaml エントリ確認
- **WHEN** `deps.yaml` を参照する
- **THEN** `spec-review-session-init` と `pre-tool-use-spec-review-gate` が script タイプで登録されている
