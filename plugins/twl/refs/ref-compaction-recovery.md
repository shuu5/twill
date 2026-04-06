---
name: ref-compaction-recovery
description: compaction 復帰プロトコルの共通リファレンス
type: reference
---

# compaction 復帰プロトコル

compaction 後に workflow chain を再開する場合、完了済みステップをスキップすること。

## 基本パターン

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-issue-num.sh" 2>/dev/null || true
ISSUE_NUM=$(resolve_issue_num)
for step in <STEP_LIST>; do
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/compaction-resume.sh" "$ISSUE_NUM" "$step" || { echo "⏭ $step スキップ"; continue; }
  # 通常手順で実行（chain-runner または LLM 実行）
done
```

## ルール

- `compaction-resume.sh <ISSUE_NUM> <step>` が exit 0 → 実行、exit 1 → スキップ（完了済み）
- LLM ステップは issue-{N}.json の状態を確認してから再実行すること
- `<STEP_LIST>` は呼び出し元 SKILL.md の chain 定義に従う
