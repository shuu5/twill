---
type: workflow
user-invocable: true
spawnable_by: [controller, user]
can_spawn: [composite, atomic, specialist]
tools: [Bash, Skill, Read, Write]
effort: medium
maxTurns: 60
---
# workflow-issue-lifecycle

co-issue v2 Worker runtime。1 issue につき structure → spec-review → aggregate → fix loop → arch-drift → create の全 lifecycle を自律実行する。

## 引数

位置引数 1 つ（per-issue dir の絶対パス）:

```
/twl:workflow-issue-lifecycle <abs-per-issue-dir>
```

## 入力ファイル構造

```
<abs-per-issue-dir>/
  IN/
    draft.md          # issue 本文ドラフト（必須）
    arch-context.md   # architecture コンテキスト（任意）
    policies.json     # ポリシー設定（必須）
    deps.json         # 依存情報（任意）
  STATE               # 現在状態ファイル（workflow が上書き）
  rounds/             # ラウンドごとの成果物
  OUT/
    report.json       # 最終出力
```

## 処理フロー

`refs/lifecycle-processing-flow.md` を Read して全ステップ（Step 0〜Step 7）を順に実行すること（MUST）。スキーマ・制約・禁止事項も同ファイルに記載。

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

`refs/ref-compaction-recovery.md` を Read し従うこと。再開時は `refs/lifecycle-processing-flow.md` を Read してステップを確認し、中断箇所から再実行すること。
