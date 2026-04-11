## Context

`plugins/twl/skills/co-issue/SKILL.md` Phase 1 は現在 `/twl:explore` を 1 回だけ呼び出し、探索後に `explore-summary.md` を書き出して即 Phase 2 に進む。`co-issue` は Claude Code の Skill として動作し、ユーザーとの対話は `AskUserQuestion` tool を介して行われる。ループ制御は SKILL.md の手続き記述で実現する（外部スクリプト不要）。

## Goals / Non-Goals

**Goals:**
- Phase 1 に `loop-gate`（AskUserQuestion）を設置し、ユーザーが探索継続・Phase 2 移行・手動編集を選択できるようにする
- 追加懸念を `escape-issue-body.sh` でエスケープして次の `/twl:explore` に注入する
- `edit-complete-gate` で手動編集完了を明示確認する
- `Step 1.5`（`/twl:issue-glossary-check`）はループ外（`[A]` 選択後）に配置する
- `co-issue-skill.test.sh` に 4 ケースの静的 grep テストを追加する

**Non-Goals:**
- `/twl:explore` 本体の改修
- Phase 2 以降の変更
- ループ回数上限（max_loops）の導入
- 外部プロセス・ファイル mtime 監視による編集完了検知

## Decisions

### D1: 編集完了シグナル検出に AskUserQuestion (edit-complete-gate) を採用
非同期ファイル監視は Skill 実行モデルで対応不可。AskUserQuestion による明示確認が最小コストかつ既出パターン。`[A] 編集完了` 選択後に `explore-summary.md` を Read し直してループを続行、`[B] キャンセル` で直前 state に戻る。

### D2: ユーザー入力の XML エスケープに `escape-issue-body.sh` を使用
`${CLAUDE_PLUGIN_ROOT}/scripts/escape-issue-body.sh` は `&`, `<`, `>` を HTML エンコードする既存スクリプト。`<additional_concerns>` 要素内容のエスケープとして十分（属性値でないため quote 不要）。

### D3: 呼称を「Step 1.5」に統一（「Phase 1.5」から変更）
`test_no_phase_5_or_above` など `Phase [5-9]` を検査する既存テストとの表記揺れ干渉を防ぐ。

### D4: 最低 1 回ループ後にのみ gate を発火
ゼロ探索で Phase 2 に進めないよう、gate は必ず 1 回以上の `/twl:explore` 実行後に提示する。ループカウンタを内部変数で管理（SKILL.md の手続き記述）。

### D5: テストは静的 grep 形式（既存 co-issue-skill.test.sh スタイル）
実動作のインタラクティブ検証ではなく SKILL.md の構造記述を grep で検証する。

## Risks / Trade-offs

- **コンテキスト蓄積**: ループ回数が多いほど accumulated_concerns が増大し、`/twl:explore` へのプロンプトが長くなる。ユーザーが望む限り回す設計のため、許容する
- **edit-complete-gate の UX**: ファイル編集後に Claude に戻ってボタンを押す 2 ステップが必要。最小実装として許容
- **SKILL.md の行数増加**: Phase 1 セクションが数十行増える。全体の可読性維持のため擬似コード形式で記述
