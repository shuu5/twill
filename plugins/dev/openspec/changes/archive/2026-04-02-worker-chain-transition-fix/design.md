## Context

autopilot Worker は workflow-setup → test-ready → pr-cycle の 3 workflow を chain 遷移する。各 workflow の SKILL.md が「chain 実行指示（MUST）」セクションで全ステップを `### Step N: name` 形式で明示列挙する設計。

既知のフィードバック: SKILL.md の chain 指示は全ステップ明示列挙が必須。テーブル形式のライフサイクル一覧 + 「以降は自動進行」では Claude が停止する。

現状:
- `workflow-setup/SKILL.md`: chain 実行指示セクションあり（L75-115）→ 正常動作
- `workflow-test-ready/SKILL.md`: chain 実行指示セクション **欠落** → Worker 停止の原因
- `workflow-pr-cycle/SKILL.md`: chain 実行指示セクションあり（L87-127）→ 正常動作

## Goals / Non-Goals

**Goals:**

- workflow-test-ready/SKILL.md に chain 実行指示セクションを追加し、4 ステップを明示列挙
- check.md に PASS/FAIL 後の遷移ルールをチェックポイントとして追加
- opsx-apply.md のフロー制御を Step 形式に統一し、autopilot 遷移を明確化
- 3 workflow 間の chain 遷移が人間介入なしで完了すること

**Non-Goals:**

- autopilot-launch.sh のプロンプト構造変更
- Pilot 側での chain 制御設計変更（対策案 3 は採用しない）
- workflow-setup, workflow-pr-cycle の既存 chain 実行指示の変更

## Decisions

### D1: workflow-test-ready に chain 実行指示セクションを追加

workflow-setup/SKILL.md と同じパターン（`## chain 実行指示（MUST — 全ステップを順に実行せよ。途中で停止するな）`）を採用。Step 1〜4 を明示列挙:

| Step | 内容 |
|------|------|
| 1 | change-id 解決 |
| 2 | テスト生成（条件判定） |
| 3 | check 実行 |
| 4 | opsx-apply 実行 |

**理由**: 既に workflow-setup と workflow-pr-cycle で実績のある同じパターン。フィードバック記憶に合致。

### D2: check.md にチェックポイントを追加

check 結果の PASS/FAIL に応じた遷移を明記:
- 全 PASS → opsx-apply を自動実行
- CRITICAL FAIL → opsx-apply をスキップし停止

ただし遷移制御は workflow-test-ready.md 側に残し、check.md は結果報告に徹する形にする。チェックポイントは「`/dev:opsx-apply` を Skill tool で自動実行。」の1行。

**理由**: check は共通コマンドで workflow-test-ready 以外からも呼ばれるため、遷移判定ロジックは呼び出し元の workflow に配置する。

### D3: opsx-apply.md のフロー制御統一

現在の `### フロー制御（MUST）` を `### Step N:` 形式に変更:
- Step 1: change-id 解決
- Step 2: apply 実行
- Step 3: autopilot 判定 + workflow-pr-cycle 遷移

**理由**: 他の commands と同じ構造に統一し、chain 遷移の信頼性を高める。

## Risks / Trade-offs

- **リスク**: SKILL.md のドキュメント修正のみなので技術的リスクは極めて低い
- **トレードオフ**: chain 実行指示の冗長性が増えるが、Claude の遷移信頼性が上がるため許容
- **制約**: Claude のモデル/バージョン依存性は残るが、明示列挙パターンは他 2 workflow で実績がある
