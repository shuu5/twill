# ADR-012: Architecture Drift Detection の重大度レベル再設計（INFO → WARNING 昇格）

## Status
Accepted

## Context

`issue-arch-drift.md`（co-issue Step 3.5）は 3 層シグナルで architecture drift を検出するが、すべて INFO レベル・非ブロッキングである。

`plugins/twl/architecture/vision.md` は「陳腐化は有害」と明記しているが、INFO 通知では「検討してください」のみで強制メカニズムがない。その結果、明示的な arch-ref タグや不変条件変更を含む Issue が処理された後も、architecture spec が更新されない事例が観察されている。

### 3 層シグナルの性質差

| シグナル | 内容 | 確信度 |
|----------|------|--------|
| 明示的（explicit） | `<!-- arch-ref-start -->` タグで直接指定 | 高い（作者が明示） |
| 構造的（structural） | 不変条件・Entity Schema・Workflow 変更言及 | 高い（用語完全一致） |
| ヒューリスティック（heuristic） | ctx/* ラベルが 3 件以上 | 低い（間接的推測） |

明示的・構造的シグナルは作者または用語完全一致に基づくため、確信度が高い。これらを INFO のまま維持することは「有害な陳腐化」を黙認することと等しい。

## Decision

### 1. シグナルごとの重大度レベルを分離する

| シグナル | 変更前 | 変更後 |
|----------|--------|--------|
| 明示的（explicit） | INFO | **WARNING** |
| 構造的（structural） | INFO | **WARNING** |
| ヒューリスティック（heuristic） | INFO | INFO（変更なし） |

### 2. WARNING 時の対応義務

WARNING シグナル検出時は、AskUserQuestion tool で co-architect delegation の確認を行う。

- **ブロッキングではない**: ユーザーが「スキップ」を選択した場合は続行可
- **確認後続行**: 「後で更新する」「今すぐ更新する」「スキップ」を選択肢として提示
- 非ブロッキングの原則は維持しつつ、ユーザーの意識を確実に引き上げる

### 3. ヒューリスティックは INFO のまま維持

ctx/* ラベルの数は間接的な指標であり、false positive が多い。強制的な対応義務を課すと、無用な中断が増加する。

## Consequences

### Positive
- 明示的・構造的シグナルの見落としがなくなる
- architecture spec の陳腐化リスクが低減する
- vision.md の「陳腐化は有害」の方針に実装が追いつく

### Negative
- co-issue フローに AskUserQuestion が追加されるため、対象 Issue では対話ステップが増加する

### Mitigations
- 選択肢に「スキップ」を含め、ユーザーが速度を優先できる
- WARNING 表示後にユーザーが確認するまで待機するが、フロー自体は停止しない（非ブロッキング）
