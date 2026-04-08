# Spec: Tier 1 — PR Cycle Prompt Compliance Gate

## Context

PR cycle の phase-review / merge-gate で、prompt ファイル（.md）変更時に prompt compliance を機械的に検証する。

## ADDED Requirements

### Requirement: pr-review-manifest に prompt 変更検出ルールを追加する

WHEN PR の変更ファイルに `commands/*.md`, `agents/*.md`, `skills/*/SKILL.md`, `refs/*.md` が含まれる
THEN `pr-review-manifest.sh` が `worker-prompt-compliance` を出力リストに含める

WHEN PR の変更ファイルに .md ファイルが含まれない
THEN `worker-prompt-compliance` は出力されない

### Requirement: worker-prompt-compliance が stale コンポーネントを検出する

WHEN worker-prompt-compliance が spawn される
THEN `twl audit --section 8 --json` を実行し、変更された .md に対応するコンポーネントの prompt_compliance 状態を取得する

WHEN 対象コンポーネントの refined_by が現在の ref-prompt-guide.md ハッシュと不一致
THEN severity=WARNING, confidence=60 の finding を出力する

WHEN 対象コンポーネントの refined_by が未設定
THEN severity=INFO, confidence=40 の finding を出力する

WHEN 対象コンポーネントの refined_by が最新
THEN finding を出力しない（OK としてスキップ）

### Requirement: finding はブロッキングではない

WHEN worker-prompt-compliance の findings が WARNING のみ（CRITICAL なし）
THEN PR cycle は WARN ステータスで続行する（BLOCK しない）

## MODIFIED Requirements

### Requirement: pr-review-manifest.sh のモード対応

WHEN mode が phase-review または merge-gate
THEN prompt 変更検出ルールが適用される

WHEN mode が post-fix-verify
THEN prompt 変更検出ルールは適用されない（fix 対象外）

## Scenarios

### Scenario: deps.yaml と commands/foo.md を同時に変更した PR

WHEN git diff --name-only が `plugins/twl/deps.yaml` と `plugins/twl/commands/foo.md` を含む
THEN manifest は `worker-structure`, `worker-principles`, `worker-prompt-compliance` を出力する
AND worker-prompt-compliance は `foo` の refined_by を検証する

### Scenario: .py ファイルのみ変更した PR

WHEN git diff --name-only が `cli/twl/src/twl/cli.py` のみを含む
THEN manifest は `worker-prompt-compliance` を出力しない

### Scenario: ref-prompt-guide.md を変更した PR

WHEN git diff --name-only が `plugins/twl/refs/ref-prompt-guide.md` を含む
THEN worker-prompt-compliance が spawn される
AND ref-prompt-guide.md 自体の変更によりハッシュが更新されるため、全コンポーネントが stale として検出される
AND status=WARN で reporting する（全件を individual findings として列挙はしない、サマリーのみ）
