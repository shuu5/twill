# Test Scenarios: su-observer stagnate 検知 / Worker idle 検知

Source: `deltaspec/changes/issue-475/specs/su-observer-stall-detection/spec.md`
Generated: 2026-04-11
Coverage: edge-cases
Type: unit (document-verification)

---

## Requirement: 監視チャンネルマトリクス

### Scenario: Worker stall 検知

**WHEN** co-autopilot 起動後、cld-observe-loop を `--pattern 'ap-*' --interval 180` で起動し、いずれかの Worker の state file `updated_at` が `AUTOPILOT_STAGNATE_SEC`（デフォルト 600s）以上更新されていない
**THEN** su-observer は WARN を出力し、intervention-catalog の pattern-7 照合を実行しなければならない（SHALL）

| # | テスト名 | 検証対象 | 検証方法 |
|---|---------|---------|---------|
| 1 | SKILL.md に cld-observe-loop --pattern 'ap-*' --interval 180 が定義されている | `skills/su-observer/SKILL.md` | `grep -iP "cld-observe-loop.*--pattern.*ap-\*.*--interval\s*180"` |
| 2 | SKILL.md に AUTOPILOT_STAGNATE_SEC 環境変数が定義されている | `skills/su-observer/SKILL.md` | `grep -iP "AUTOPILOT_STAGNATE_SEC"` |
| 3 | SKILL.md に stagnate 検知時 WARN 出力が定義されている | `skills/su-observer/SKILL.md` | `grep -iP "WARN\|stagnate.*検知"` |
| 4 | SKILL.md に pattern-7 照合が定義されている | `skills/su-observer/SKILL.md` | `grep -iP "pattern-7"` |
| E1 | [edge] intervention-catalog への参照が存在する | `skills/su-observer/SKILL.md` | `grep -iP "intervention-catalog"` |
| E2 | [edge] AUTOPILOT_STAGNATE_SEC デフォルト値 600s が明記されている | `skills/su-observer/SKILL.md` | `grep -P "600"` |

### Scenario: 監視チャンネル並行実行

**WHEN** su-observer が co-autopilot supervise モードに入る
**THEN** Monitor tool（Pilot tail）と cld-observe-loop（Worker 群）を同時に起動しなければならない（SHALL）。どちらか一方のみの起動は禁止とする

| # | テスト名 | 検証対象 | 検証方法 |
|---|---------|---------|---------|
| 1 | SKILL.md に監視チャンネルマトリクス テーブルが存在する | `skills/su-observer/SKILL.md` | テーブルヘッダー `\|.*チャンネル.*\|.*目的.*\|` の存在確認 |
| 2 | Monitor tool (Pilot tail) チャンネルが定義されている | `skills/su-observer/SKILL.md` | `grep -iP "Monitor\s*tool\s*\(Pilot\)"` |
| 3 | cld-observe-loop (Worker 群 polling) チャンネルが定義されている | `skills/su-observer/SKILL.md` | `grep -P "cld-observe-loop"` |
| 4 | issue-*.json mtime 監視チャンネルが定義されている | `skills/su-observer/SKILL.md` | `grep -P "issue-\*\.json.*mtime\|state stagnate"` |
| 5 | gh pr list チャンネルが定義されている | `skills/su-observer/SKILL.md` | `grep -P "gh pr list"` |
| 6 | session-comm.sh capture チャンネルが定義されている | `skills/su-observer/SKILL.md` | `grep -P "session-comm\.sh.*capture"` |
| E1 | [edge] 監視チャンネルが5つ定義されている | `skills/su-observer/SKILL.md` | Python で テーブル行数を検証 |
| E2 | [edge] Monitor と cld-observe-loop の同時起動が必須と明記されている | `skills/su-observer/SKILL.md` | `grep -iP "同時\|並行\|concurrent"` |

---

## Requirement: state stagnate 検知（observe-once 拡張）

### Scenario: stagnate ファイル検出

**WHEN** observe-once を実行し、`.autopilot/issues/issue-*.json` のいずれかの mtime が `AUTOPILOT_STAGNATE_SEC` 秒以上古い
**THEN** JSON 出力の `stagnate_files` 配列に該当ファイルパスを含め、stdout に `WARN: state stagnate detected: <path>` を出力しなければならない（SHALL）

| # | テスト名 | 検証対象 | 検証方法 |
|---|---------|---------|---------|
| 1 | observe-once.md に stagnate_files フィールドが定義されている | `commands/observe-once.md` | `grep -P "stagnate_files"` |
| 2 | observe-once.md に .autopilot/issues/issue-*.json mtime チェックが定義されている | `commands/observe-once.md` | `grep -P "\.autopilot/issues/issue-\*\.json"` |
| 3 | observe-once.md に AUTOPILOT_STAGNATE_SEC 参照が定義されている | `commands/observe-once.md` | `grep -P "AUTOPILOT_STAGNATE_SEC"` |
| 4 | observe-once.md に 'WARN: state stagnate detected: <path>' 出力が定義されている | `commands/observe-once.md` | `grep -iP "WARN.*state stagnate detected"` |
| E1 | [edge] WARN フォーマットに <path> プレースホルダーが含まれる | `commands/observe-once.md` | `grep -P "stagnate.*<path>\|stagnate.*\$\{.*\}"` |
| E2 | [edge] stagnate_files が配列型 (string[]) として定義されている | `commands/observe-once.md` | `grep -P "stagnate_files.*string\[\]\|stagnate_files.*\[\]"` |

### Scenario: stagnate なし

**WHEN** observe-once を実行し、全 state file の mtime が `AUTOPILOT_STAGNATE_SEC` 秒以内
**THEN** `stagnate_files` は空配列 `[]` を出力し、WARN は出力しない（SHALL）

| # | テスト名 | 検証対象 | 検証方法 |
|---|---------|---------|---------|
| 1 | observe-once.md に stagnate なし時の stagnate_files: [] が定義されている | `commands/observe-once.md` | `grep -P "\[\]\|空配列\|empty array"` |
| E1 | [edge] JSON 出力例に stagnate_files フィールドが含まれている | `commands/observe-once.md` | Python で JSON コードブロックを解析 |
| E2 | [edge] 既存 JSON フィールド（window, timestamp, lines, capture, session_state）が全て保持されている | `commands/observe-once.md` | 各フィールドの存在確認 |

---

## Requirement: Worker idle 検知パターン（intervention-catalog pattern-7）

### Scenario: 自動回復（pattern-7）

**WHEN** state `updated_at` が 600 秒以上古い AND 対象 Worker pane の tail に `>>> 実装完了:` を含む文字列が検出される
**THEN** su-observer は Layer 0 Auto として `/twl:workflow-pr-verify --spec issue-<N>` を対象 Worker window に inject し、InterventionRecord を記録しなければならない（SHALL）

| # | テスト名 | 検証対象 | 検証方法 |
|---|---------|---------|---------|
| 1 | intervention-catalog.md に pattern-7 が定義されている | `refs/intervention-catalog.md` | `grep -iP "pattern-7"` |
| 2 | pattern-7 が Layer 0 Auto に分類されている | `refs/intervention-catalog.md` | Python で Layer 0 セクション内に pattern-7 が存在するか確認 |
| 3 | pattern-7 検出条件に 600 秒 stagnate が含まれている | `refs/intervention-catalog.md` | `grep -P "600\|AUTOPILOT_STAGNATE_SEC"` |
| 4 | pattern-7 検出条件に '>>> 実装完了:' が含まれている | `refs/intervention-catalog.md` | `grep -P ">>> 実装完了:"` |
| 5 | pattern-7 修復手順に /twl:workflow-pr-verify inject が定義されている | `refs/intervention-catalog.md` | `grep -P "workflow-pr-verify"` |
| 6 | pattern-7 事後処理に InterventionRecord 記録が定義されている | `refs/intervention-catalog.md` | Python で pattern-7 セクション内に InterventionRecord が存在するか確認 |
| E1 | [edge] pattern-7 inject 先が Worker window と明記されている | `refs/intervention-catalog.md` | `grep -iP "Worker.*window"` |
| E2 | [edge] --spec issue-<N> 引数形式が定義されている | `refs/intervention-catalog.md` | `grep -P "--spec issue-<N>\|--spec issue-"` |

### Scenario: 検出条件が部分的にしか満たされない場合

**WHEN** state stagnate は検出されたが worker pane に `>>> 実装完了:` が含まれない
**THEN** pattern-7 ではなく Layer 1 Confirm（パターン4: Worker 長時間 idle）として処理しなければならない（SHALL）

| # | テスト名 | 検証対象 | 検証方法 |
|---|---------|---------|---------|
| 1 | pattern-4 (Worker 長時間 idle) が Layer 1 Confirm に存在する | `refs/intervention-catalog.md` | Python で Layer 1 セクション内に pattern-4 が存在するか確認 |
| E1 | [edge] pattern-7 の検出条件が AND 結合であることが明示されている | `refs/intervention-catalog.md` | Python で pattern-7 セクション内に AND/かつ が存在するか確認 |
| E2 | [edge] '>>> 実装完了:' なし時に pattern-4 へのフォールバックが記述されている | `refs/intervention-catalog.md` | `grep -iP "stagnate.*pattern-4\|pattern-4.*フォールバック"` |

---

## Requirement: observe-once JSON 出力スキーマ拡張

### Scenario: JSON フィールド追加

**WHEN** observe-once を実行する
**THEN** 出力 JSON に `stagnate_files: string[]` フィールドを含まなければならない（SHALL）。既存フィールド（`window`, `timestamp`, `lines`, `capture`, `session_state`）は変更しない

| # | テスト名 | 検証対象 | 検証方法 |
|---|---------|---------|---------|
| 1 | JSON スキーマに stagnate_files が追加されている | `commands/observe-once.md` | `grep -P "stagnate_files"` |
| 2 | 既存フィールド 'window' が保持されている | `commands/observe-once.md` | `grep -P '"window"'` |
| 3 | 既存フィールド 'timestamp' が保持されている | `commands/observe-once.md` | `grep -P '"timestamp"'` |
| 4 | 既存フィールド 'session_state' が保持されている | `commands/observe-once.md` | `grep -P '"session_state"'` |
| E1 | [edge] stagnate_files が session_state より後に追加されている（前方互換） | `commands/observe-once.md` | Python で JSON コードブロック内のフィールド順序を確認 |
| E2 | [edge] mtime チェック用の Step が追加されている | `commands/observe-once.md` | `grep -iP "Step.*mtime\|mtime.*Step"` |

---

## 実行方法

```bash
# plugin-twl worktree で実行（scenario runner 経由）
cd plugins/twl
bash tests/scenarios/su-observer-stagnate-detect.test.sh

# または全シナリオ一括実行
bash tests/run-tests.sh --scenarios-only
```
