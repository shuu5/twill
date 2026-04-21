## Context

su-observer は controller (co-issue / co-explore / co-autopilot 等) を spawn する際に `spawn-controller.sh` を経由する。スクリプトは `PROMPT_FILE` からプロンプト本文を読み込み `cld-spawn` に渡すが、現在プロンプトのサイズ検査が存在しない。

観測事象（session 7f960078）では 63 行中 60 行（95%）が skill 自律取得可能な情報の転記であった。根本原因は 4 層（R1: pitfalls-catalog §3.5 誤誘導、R2: SKILL.md 曖昧表現、R3: memory 助言の時代遅れ化、R4: size guard 不在）であり、本実装は R1・R2・R4 を解消する。

## Goals / Non-Goals

**Goals:**

- `pitfalls-catalog.md` §10「spawn prompt 最小化原則」新設（MUST NOT 7 項目 + MUST 5 項目 + `--force-large` 例外 + 境界補足）
- `pitfalls-catalog.md` §3.5 の「全て prompt に包含」→「observer 固有文脈のみ包含（§10 参照）」改訂
- `SKILL.md` 「spawn プロンプトの文脈包含」節に MUST NOT サブ節 + 最小 prompt 例追加
- `spawn-controller.sh` に 30 行 threshold のサイズ guard 追加（stderr 警告 + `--force-large` escape）
- `spawn-controller-prompt-size.bats` に 5 テストケース追加（正常系・異常系・エスケープ系）

**Non-Goals:**

- 他 controller (co-issue 等) の Step 0 改修（既に自律取得実装済）
- memory hash 67772bcb の直接書き換え（別途 observer-lesson 更新で対応）
- `--force-large` 使用履歴の自動ロギング機構
- `--force-large` の監査ログ化

## Decisions

**D1: 30 行 threshold**
Issue body で明示された値を採用。一般的な observer 固有文脈（5-15 行）に対して十分な余裕を持ちつつ、60 行超の冗長 prompt を明確に警告できる境界値。

**D2: `--force-large` エスケープハッチ設計**
- `--force-large` フラグは独立したループで事前検出（既存 `--help/-h` 検査ループとは別）
- 検出後は `cld-spawn` 引数から strip（`NEW_ARGS` 配列で再構築）
- `set --` は `set -u` 安全な `${arr[@]+...}` 形式を使用（空配列での unbound variable エラー防止）

**D3: 挿入位置（意味的）**
`PROMPT_BODY="$(cat "$PROMPT_FILE")"` 代入直後・`FINAL_PROMPT` 生成前。行番号は実装時点で確認（現行 L105）。

**D4: stderr 出力**
`WARN` は stderr に出力。observer は tmux pane もしくは `pipe-pane` log で即時確認可能。stdout は汚染しない。

**D5: bats mock 規約**
既存 `merge-gate-check-spawn.bats` 等の mock cld-spawn 規約を踏襲。`cld-spawn` を PATH 先に mock スクリプトとして配置する方式。

## Risks / Trade-offs

- **既存 spawn の警告ノイズ**: 現在 30 行超の prompt を使用している spawn が存在する場合、実装直後に警告が出るが `--force-large` で明示的に抑制できる（意図的な大 prompt と冗長 prompt を区別可能）
- **line count の誤差**: `wc -l` は末尾改行のないファイルで実行内容と 1 行ずれる可能性があるが、threshold が 30 行であり誤差は実用上無視できる
- **`--force-large` の濫用**: REASON: 行の義務化はドキュメント要件であり技術的強制ではないため、警告を confirm なしに suppress できる。ただし監査ログ不要（スコープ）とした
