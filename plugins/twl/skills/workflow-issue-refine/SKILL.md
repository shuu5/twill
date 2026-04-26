---
type: workflow
user-invocable: true
spawnable_by: [controller, user]
can_spawn: [composite, atomic, specialist]
tools: [Bash, Skill, Read, Write]
effort: medium
maxTurns: 60
---
# workflow-issue-refine

既存 Issue の refine（精緻化）workflow。1 issue につき spec-review → aggregate → fix loop → arch-drift → body 更新の lifecycle を自律実行する。

`workflow-issue-lifecycle` の構造を踏襲しつつ、Step 3（issue-structure）を省略し、Step 6（issue-create）を Step 6'（gh issue edit による body 更新）に置換する。

## 引数

位置引数 1 つ（per-issue dir の絶対パス）:

```
/twl:workflow-issue-refine <abs-per-issue-dir>
```

## 入力ファイル構造

```
<abs-per-issue-dir>/
  IN/
    draft.md              # 改善後の issue body（必須）
    existing-issue.json   # 既存 Issue 情報（必須: { "number": N, "current_body": "...", "repo": "owner/repo" }）
    arch-context.md       # architecture コンテキスト（任意）
    policies.json         # ポリシー設定（必須）
    deps.json             # 依存情報（任意）
  STATE                   # 現在状態ファイル（workflow が上書き）
  rounds/                 # ラウンドごとの成果物
  OUT/
    report.json           # 最終出力
```

## 処理フロー

`refs/refine-processing-flow.md` を Read して全ステップ（Step 0〜Step 7）を順に実行すること（MUST）。スキーマ・制約・禁止事項も同ファイルに記載。

## STATE 遷移

| 値 | 意味 |
|---|---|
| `running` | 起動・初期化中 |
| `reviewing` | spec-review 実行中 |
| `fixing` | body 修正中 |
| `done` | 正常完了 |
| `failed` | 回復不能エラー |
| `circuit_broken` | max_rounds 到達・CRITICAL 未解消 |

## compaction 復帰プロトコル

`refs/ref-compaction-recovery.md` を Read し従うこと。再開時は `refs/refine-processing-flow.md` を Read してステップを確認し、中断箇所から再実行すること。
