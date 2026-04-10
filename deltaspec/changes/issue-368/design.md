## Context

現行 su-observer SKILL.md の Step 4 は以下のプレースホルダーのみ:
```
## Step 4: Wave 管理（後続 Issue で詳細化）
> NOTE: このステップは後続 Issue で詳細実装される。基本構造のみ定義。
Wave 単位の co-autopilot 起動・完了検知・結果集約を担う。
```

設計文書 `architecture/designs/su-observer-skill-design.md` の Step 2（autopilot モード）は 8 サブステップで Wave 管理の完全フローを定義している。この差分を実装する。

既存コマンド:
- `commands/wave-collect.md`: plan.yaml から Issue リストを取得し、Wave サマリを `.supervisor/wave-{N}-summary.md` に生成
- `commands/externalize-state.md`: `--trigger wave_complete` で Wave 完了状態を外部化

Step 6（SU-6 制約）は既に "Step 4 の wave-collect 実行後" を参照しており、Step 4 への実装追加と整合する。

## Goals / Non-Goals

**Goals:**

- Step 4 に Wave 管理の完全なフロー（8 サブステップ）を記述する
- wave-collect の呼出（WAVE_NUM 引数付き）を明示する
- externalize-state の呼出（--trigger wave_complete）を wave-collect 後に明示する
- su-compact の呼出（SU-6 制約）を明示する
- 次 Wave への繰り返しと全 Wave 完了時のサマリ報告を記述する

**Non-Goals:**

- wave-collect.md / externalize-state.md / su-compact 自体の変更
- Step 0 のモード dispatch テーブルの変更
- Step 6（SU-6 制約ブロック）の変更（既に Step 4 wave-collect を参照済み）

## Decisions

**D-1: NOTE プレースホルダーを完全なフローで差し替える**

既存の NOTE 行と 1 行説明を削除し、設計文書の Step 2 フロー（8 サブステップ）で置き換える。Step 番号は現行 SKILL.md の Step 4 のまま変更しない。

**D-2: 呼出順序は wave-collect → externalize-state → su-compact**

1. `commands/wave-collect.md` を Read → 実行（WAVE_NUM 付き）
2. `commands/externalize-state.md` を Read → 実行（--trigger wave_complete）
3. `Skill(twl:su-compact)` を呼び出す（SU-6 制約）

**D-3: 次 Wave ループは明示的に記述する**

次 Wave の Issue がある場合は Step 4-2 に戻ることを明示する。全 Wave 完了時はサマリ報告してユーザーに返す。

## Risks / Trade-offs

**R-1: 設計文書 Step 2 と現 SKILL.md Step 4 のステップ番号不一致**

Issue #368 本文は「Step 2（autopilot モード）」と記述しているが、現 SKILL.md では Step 4 が Wave 管理。Step 番号は変更せず Step 4 に実装し、SU-6 の参照（"Step 4 の wave-collect 実行後"）と整合させる。
