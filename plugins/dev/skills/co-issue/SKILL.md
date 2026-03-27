---
name: dev:co-issue
description: 要望をGitHub Issueに変換するワークフロー
type: controller
spawnable_by:
- user
---

# co-issue

Issue 作成（要望→Issue 変換）。

## explore-summary 検出（B-7 統合）

### 起動時チェック（MUST）

co-issue 起動時に `.controller-issue/explore-summary.md` の存在を確認する。

```
IF .controller-issue/explore-summary.md が存在する:
  → AskUserQuestion: 「前回の探索結果が残っています。継続しますか？」
    [A] 継続する → Phase 1（探索）をスキップし Phase 2（分解判断）から続行
    [B] 最初から → explore-summary.md を削除し、通常の Phase 1 から開始
ELSE:
  → 通常の Phase 1（探索）から開始（既存動作に影響なし）
```

**既存動作への非影響**: explore-summary.md が存在しない場合、co-issue は従来通りの Phase 1 から開始する。B-7 統合は既存フローの動作を一切変更しない。

（C-1 以降で Phase 1-4 を実装）
