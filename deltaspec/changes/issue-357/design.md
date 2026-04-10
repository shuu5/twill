## Context

`plugins/twl/deps.yaml` は TWiLL プラグインのコンポーネント依存関係の単一情報源（SSOT）。`co-observer` → `su-observer` リネームに伴い、deps.yaml 内の全参照を一括更新する必要がある。対象箇所は components セクション（エントリ定義）、entry_points セクション（スキル SKILL.md パス）、co-autopilot の calls セクション（呼び出し参照）、インラインコメントの4箇所。

## Goals / Non-Goals

**Goals:**

- deps.yaml 内の全 `co-observer` 参照を `su-observer` に置き換える
- `type: controller` を `type: supervisor` に変更する
- `twl check` と `twl update-readme` が PASS する状態にする

**Non-Goals:**

- SKILL.md 本体の変更（別 Issue / 先行 PR で対応済み前提）
- deps.yaml 以外のファイル変更

## Decisions

1. **一括テキスト置換**: `co-observer` → `su-observer` のリネームは deps.yaml 全体で機械的に適用できるが、`type:` 変更（`controller` → `supervisor`）は co-observer エントリのみに限定する
2. **supervises リスト保持**: `su-observer` が監督するコンポーネント（co-autopilot, co-issue, co-architect, co-project, co-utility）リストは既存の `co-observer` 設定から引き継ぐ
3. **検証を先行**: 編集後は `twl check` を即時実行して壊れた参照がないことを確認する

## Risks / Trade-offs

- deps.yaml は行数が多く手動編集ミスのリスクがある → sed または精密な Edit で対応
- `twl check` が su-observer の SKILL.md 存在を要求する場合、先行ブランチのマージを待つ必要がある（本 Issue は C1 後続扱い）
