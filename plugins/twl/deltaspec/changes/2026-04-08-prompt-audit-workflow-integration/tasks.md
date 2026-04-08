# Tasks: Prompt Compliance Audit ワークフロー統合

## Issue: #207

## Tier 1: PR Cycle Gate

- [ ] T1-1: `pr-review-manifest.sh` に .md 変更検出ルール追加
  - `commands/*.md`, `agents/*.md`, `skills/*/SKILL.md`, `refs/*.md` パターン
  - phase-review / merge-gate モードのみ（post-fix-verify は除外）
  - Files: `plugins/twl/scripts/pr-review-manifest.sh`

- [ ] T1-2: `worker-prompt-compliance` specialist 作成
  - haiku model, tools: Bash, Read, Glob
  - `twl audit --section 8 --json` ベース
  - 変更ファイル→コンポーネント名マッピング
  - ref-specialist-output-schema 準拠出力
  - Files: `plugins/twl/agents/worker-prompt-compliance.md`

- [ ] T1-3: `twl audit --section 8 --json` の JSON 出力対応
  - audit_collect の prompt_compliance items を JSON 出力するモード
  - 既存 `--section` フラグとの統合
  - Files: `cli/twl/src/twl/cli.py`, `cli/twl/src/twl/validation/audit.py`

- [ ] T1-4: deps.yaml に worker-prompt-compliance 定義追加
  - Files: `plugins/twl/deps.yaml`

## Tier 2: Full Audit Workflow

- [ ] T2-1: `twl refine` サブコマンド実装
  - `--component <name>`: 単一コンポーネント更新
  - `--batch <file>`: JSON リストから一括更新
  - refined_by + refined_at の自動更新
  - Files: `cli/twl/src/twl/refactor/refine.py`, `cli/twl/src/twl/cli.py`

- [ ] T2-2: `prompt-audit-scan` atomic command 作成
  - `twl audit --section 8 --json` → stale/unreviewed 抽出
  - 優先度ソート、上限 N 件
  - Files: `plugins/twl/commands/prompt-audit-scan.md`

- [ ] T2-3: `prompt-audit-review` composite command 作成
  - worker-prompt-reviewer を parallel Task spawn
  - 結果収集・集約
  - Files: `plugins/twl/commands/prompt-audit-review.md`

- [ ] T2-4: `prompt-audit-apply` atomic command 作成
  - PASS → `twl refine` で更新
  - WARN/FAIL → ユーザー報告 + tech-debt Issue 起票
  - Files: `plugins/twl/commands/prompt-audit-apply.md`

- [ ] T2-5: `workflow-prompt-audit` workflow 作成
  - 3ステップ: scan → review → apply
  - Files: `plugins/twl/skills/workflow-prompt-audit/SKILL.md`

- [ ] T2-6: deps.yaml に Tier 2 コンポーネント定義追加
  - workflow-prompt-audit, prompt-audit-scan, prompt-audit-review, prompt-audit-apply
  - Files: `plugins/twl/deps.yaml`

- [ ] T2-7: co-utility ルーティング追加
  - prompt audit 関連キーワードのルーティング
  - Files: `plugins/twl/skills/co-utility/SKILL.md`

## 検証

- [ ] V1: `twl check` + `twl validate` パス確認
- [ ] V2: PR に .md 変更を含む場合、phase-review で worker-prompt-compliance が spawn されることを確認
- [ ] V3: `twl refine --component <name>` が deps.yaml を正しく更新することを確認
- [ ] V4: workflow-prompt-audit の3ステップが正常に動作することを確認
