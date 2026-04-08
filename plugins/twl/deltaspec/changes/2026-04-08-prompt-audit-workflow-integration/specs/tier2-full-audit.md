# Spec: Tier 2 — 全体監査ワークフロー

## Context

stale/未レビューのコンポーネントを特定し、worker-prompt-reviewer で実質レビュー後、結果を deps.yaml に反映する。

## ADDED Requirements

### Requirement: workflow-prompt-audit が3ステップで全体監査を実行する

WHEN ユーザーが co-utility 経由で prompt audit を要求する
THEN workflow-prompt-audit が起動される
AND Step 1 (prompt-audit-scan) → Step 2 (prompt-audit-review) → Step 3 (prompt-audit-apply) の順に実行される

### Requirement: prompt-audit-scan が対象を特定する

WHEN prompt-audit-scan が実行される
THEN `twl audit --section 8 --json` を実行する
AND stale + unreviewed のコンポーネントを抽出する
AND 優先度順にソートする（前回 FAIL > stale > unreviewed）
AND 上限 N 件（デフォルト 15、引数で変更可能）に絞り込む
AND 対象リスト JSON を出力する

WHEN 全コンポーネントが OK（stale/unreviewed がゼロ）
THEN 「全コンポーネント最新」と報告して workflow を正常終了する

### Requirement: prompt-audit-review が並列レビューを実行する

WHEN prompt-audit-scan が対象リストを出力した
THEN 各対象に対して worker-prompt-reviewer を Task spawn する（並列実行）
AND 各 specialist に component_path, component_type, token_target を渡す
AND 全 specialist の結果を収集して JSON で集約する

### Requirement: prompt-audit-apply が結果を反映する

WHEN worker-prompt-reviewer が PASS を返したコンポーネント
THEN `twl refine --component <name>` で refined_by を現在ハッシュに更新する
AND refined_at を当日日付に更新する

WHEN worker-prompt-reviewer が WARN/FAIL を返したコンポーネント
THEN findings サマリーをユーザーに表示する
AND ユーザー確認後、tech-debt Issue として起票する（1 Issue にまとめる）

WHEN deps.yaml が更新された
THEN `twl check` と `twl validate` で整合性を検証する

### Requirement: twl refine サブコマンドが deps.yaml を更新する

WHEN `twl refine --component <name>` が実行される
THEN deps.yaml の該当コンポーネントの refined_by を `ref-prompt-guide@<current_hash>` に更新する
AND refined_at を `YYYY-MM-DD` 形式の当日日付に更新する
AND deps.yaml を書き戻す

WHEN `twl refine --batch <file>` が実行される
THEN JSON ファイルからコンポーネントリストを読み込み、各コンポーネントに対して同じ更新を行う

WHEN 対象コンポーネントが deps.yaml に存在しない
THEN エラーメッセージを出力して exit 1 する

### Requirement: co-utility にルーティングを追加する

WHEN ユーザー入力が prompt audit, プロンプト監査, prompt compliance, refined 関連
THEN co-utility が `/twl:workflow-prompt-audit` を Skill 実行する

## Scenarios

### Scenario: ref-prompt-guide.md 更新後の全体監査

WHEN ref-prompt-guide.md が更新された後にワークフローを実行する
THEN prompt-audit-scan が全コンポーネントを stale として検出する
AND 上限 15 件に絞り込んでレビューを実行する
AND PASS コンポーネントの refined_by が新ハッシュに更新される
AND 残りのコンポーネントは次回実行時にレビューされる

### Scenario: 全コンポーネントが最新の場合

WHEN 全コンポーネントの refined_by が最新ハッシュと一致する
THEN prompt-audit-scan が「全コンポーネント最新」と報告する
AND workflow が Step 1 で正常終了する（Step 2/3 はスキップ）

### Scenario: コスト制御

WHEN 100 件以上の stale コンポーネントがある
THEN prompt-audit-scan が上限 15 件に絞り込む
AND 1回のワークフロー実行で消費するトークンを制限する
AND 残りは次回実行時にカバーする
