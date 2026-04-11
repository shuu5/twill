## Context

不変条件 C（Worker マージ禁止）は `autopilot.md` に定義されているが、Worker が実際に参照する SKILL.md と起動コンテキストに禁止が明記されていない。auto-merge.sh には 4-layer ガード（IS_AUTOPILOT チェック等）が実装されているが、Worker が auto-merge.sh を経由せず直接 `gh pr merge` を呼ぶと全てのガードが無効になる。

**問題の根本**: ガードは auto-merge.sh 内にあるが、Worker が auto-merge.sh を参照することは保証されていない。

## Goals / Non-Goals

**Goals:**
- workflow-pr-merge/SKILL.md に `gh pr merge` 直接実行禁止を明記（不変条件 C）
- autopilot-launch.sh の Worker 起動コンテキスト注入に merge 禁止テキストを追加
- co-autopilot/SKILL.md の不変条件 C に enforcement 箇所の参照リンクを追記

**Non-Goals:**
- auto-merge.sh の 4-layer ガード修正（既存ガードは維持）
- autopilot.md の不変条件定義の変更
- Worker の実装フロー変更（`chain-runner.sh auto-merge` の呼び出しは既存のまま）

## Decisions

**Decision 1: workflow-pr-merge/SKILL.md への禁止追記箇所**

既存の「禁止事項」セクション（不変条件 E, F を記載）の先頭に不変条件 C を追加する。既存の構造を壊さずに最優先で目に入る位置に配置。

**Decision 2: autopilot-launch.sh の注入パターン**

quick ラベル注入（line 232-242）と同一パターン（`CONTEXT` 変数への追記）を使用。常時注入（ラベル条件なし）とする。注入テキストは固定文字列として autopilot-launch.sh 内に記述。

**Decision 3: co-autopilot/SKILL.md の参照リンク**

不変条件一覧（line 117）の不変条件 C 記述に enforcement 箇所への参照を追記する。内容の詳細展開は不要、パス参照のみ。

## Risks / Trade-offs

- **リスク**: 固定テキスト注入はプロンプト長を増やすが、禁止ルール 1 件分なので影響は最小
- **トレードオフ**: 起動コンテキストへの注入は all-or-nothing（条件分岐なし）。不変条件 C はどの Issue でも適用すべきため問題なし
