## Why

co-issue が Issue を精緻化して作成しても、その Issue が architecture spec に影響するかどうかの検出が行われていない。結果として #210-#212（CWD リセット根本解決）のように autopilot context の中核概念を変更する Issue が architecture spec 更新なしで実装され、spec 乖離が蓄積される。architecture-spec-dci.md の「更新トリガー」セクションは条件を列挙しているが、**検出する仕組みがなかった**。

## What Changes

- `skills/co-issue/SKILL.md`: Phase 3 完了後・Phase 4 開始前に Step 3.5（architecture drift detection）を追加
  - 3 層シグナル検出: 明示的（`<!-- arch-ref-start -->` タグ）・構造的（glossary MUST 用語 + architecture/ ファイル名照合）・ヒューリスティック（ctx/* ラベル数 >= 3）
  - シグナルあり → INFO レベルで一覧表示し `/twl:co-architect` の実行を提案（非ブロッキング）
  - シグナルなし → Step 3.5 をスキップ（出力なし）
- `deps.yaml`: co-issue の参照ファイルに architecture/ context ファイルを追加

## Capabilities

### New Capabilities

- **Step 3.5: Architecture Drift Detection**: co-issue Phase 3 完了後に実行。作成予定 Issue が architecture spec に影響するかを 3 シグナルで検出し、ユーザーに `/twl:co-architect` の実行を INFO 提案する

### Modified Capabilities

- **co-issue フロー**: Phase 3 と Phase 4 の間に Step 3.5 が挿入される。`architecture/` 非存在時は Step 3.5 全体をスキップ（既存プロジェクトへの影響なし）

## Impact

| 対象 | 変更種別 |
|------|---------|
| `skills/co-issue/SKILL.md` | Step 3.5 追加 |
| `deps.yaml` | co-issue 参照ファイル更新 |

`architecture/` 非存在時は Step 3.5 がスキップされ、既存プロジェクトへの影響なし。検出は INFO レベルのみで co-issue フローを停止しない。
