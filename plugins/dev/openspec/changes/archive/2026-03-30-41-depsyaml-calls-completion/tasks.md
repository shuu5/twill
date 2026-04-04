## 0. ベースライン記録

- [x] 0.1 `loom validate` で `- agent:`, `- reference:`, `- script:`, `- workflow:` 形式の calls を受け付けるか検証
- [x] 0.2 `loom orphans` の現在の Isolated / Unused 件数を記録
- [x] 0.3 SVG の DOT エッジ数をベースラインとして記録

## 1. Script calls 追加

- [x] 1.1 全コマンド .md ファイルを読み、scripts/ への参照パターンを特定
- [x] 1.2 各コマンドの deps.yaml エントリに `- script:` calls を追加（約 25 件）
- [x] 1.3 `loom check` / `loom validate` PASS 確認

## 2. Workflow calls 追加

- [x] 2.1 controller SKILL.md を読み、起動する workflow を特定
- [x] 2.2 co-autopilot の calls に workflow 参照を追加（workflow-setup, workflow-test-ready, workflow-pr-cycle, workflow-dead-cleanup, workflow-tech-debt-triage）
- [x] 2.3 `loom check` / `loom validate` PASS 確認

## 3. Agent calls 追加

- [x] 3.1 composite コマンドの .md ファイルを読み、spawn する specialist を特定
- [x] 3.2 phase-review, merge-gate, test-scaffold, test-phase, issue-assess, plugin-phase-diagnose, plugin-phase-verify の calls に `- specialist:` を追加
- [x] 3.3 `loom check` / `loom validate` PASS 確認

## 4. Reference calls 追加

- [x] 4.1 agent .md ファイルから reference 参照を特定（ref-specialist-output-schema 等）
- [x] 4.2 reference を消費する composite / controller の calls に `- reference:` を追加
- [x] 4.3 co-issue の calls に ref-issue-template-bug, ref-issue-template-feature を追加
- [x] 4.4 `loom check` / `loom validate` PASS 確認

## 5. Sub-command calls 追加

- [x] 5.1 コマンド .md のチェックポイントセクションから sub-command 呼び出しを特定
- [x] 5.2 型システム制約により atomic→atomic は表現不可と判明。chain 内の呼び出しは workflow の calls で既にカバー済み
- [x] 5.3 `loom check` / `loom validate` PASS 確認

## 6. 検証・SVG 再生成

- [x] 6.1 `loom orphans` 実行 → Isolated 64→27（型制約で表現不可の4 agents + 13 standalone commands + 10 standalone scripts）
- [x] 6.2 `loom update-readme` で SVG 再生成
- [x] 6.3 DOT エッジ数 144→321（123% 増加）
- [x] 6.4 `loom check` / `loom validate` 最終 PASS 確認
