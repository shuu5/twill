## Context

co-issue v2 では Pilot (Issue #492) が Worker に 1 issue の lifecycle を委譲する。Worker runtime として以下が必要:
- 1 issue の全フェーズ（structure → spec-review → aggregate → fix loop → arch-drift → create）を自律実行する skill
- N issue を並列バッチ処理する orchestrator script

PR #467 (Issue #447) で `spec-review-orchestrator.sh` が merge 済み。本 Issue はそのコードパターン（tmux + polling + MAX_PARALLEL + flock）を流用し、lifecycle 全体を担う orchestrator と workflow を実装する。

ADR-017 (Issue #490) の設計原則:
- P1: dispatch/state 遷移/並列制御は bash に閉じ込める
- P2: 全入出力はファイル経由（env var 一切不使用）
- P3: N per session = 1 不変量
- P4: 失敗局所化（`|| continue` + per-window 独立）
- P5: 状態は state ファイル + deterministic window 名で外部化

## Goals / Non-Goals

**Goals:**

- `workflow-issue-lifecycle` SKILL.md 新規作成（round loop + file-based I/O）
- `issue-lifecycle-orchestrator.sh` 新規作成（spec-review-orchestrator.sh パターン流用）
- `issue-create.md` に `--repo` オプション追加（後方互換）
- deps.yaml の spawnable_by 拡張 5 件 + 新エントリ 2 件
- bats テスト + smoke scenario

**Non-Goals:**

- `co-issue/SKILL.md` 改修（Issue #492）
- `workflow-issue-refine/SKILL.md` 改修・削除（Issue #493）
- `spec-review-orchestrator.sh` 改修（PR #467 成果物）
- `CO_ISSUE_V2` feature flag（Issue #492）
- 3 scripts 分割方式（orchestrator 1 script に集約）
- 並列度動的調整（env var のみで override）

## Decisions

### D1: workflow-issue-lifecycle の入力インターフェース

per-issue dir の絶対パスを位置引数として受け取る（`$1`）。IN/ サブディレクトリに `draft.md`, `arch-context.md`, `policies.json`, `deps.json` を配置。

**理由**: ファイル経由 I/O（ADR-017 P2）で Pilot/Worker 間 handoff を完全に decoupling。

### D2: issue-lifecycle-orchestrator.sh の入力

`--per-issue-dir <abs-path>` で `.controller-issue/<sid>/per-issue/` を受け取る。`*/IN/draft.md` が存在するサブディレクトリを対象として検出。

**理由**: spec-review-orchestrator.sh が `--issues-dir` を使うパターンを踏襲しつつ、per-issue dir 構造に合わせた命名。

### D3: 決定論的 window 名

`coi-<sid8>-<index>` 形式。`sid8` は per-issue-dir のパスから先頭 8 文字を抽出（簡易規則）。

**理由**: ADR-017 P5 の「deterministic window 名で外部化」準拠。flock で衝突回避。

### D4: cld 起動方式

`cld '<prompt>'` 位置引数形式（`-p/--print` 禁止）。プロンプトは wrapper script 経由で渡す（spec-review-orchestrator.sh の実装パターンと同一）。

**理由**: autopilot-launch.sh L364 の前例に従う。

### D5: issue-create --repo 実装

`--repo` 指定時のみ内部で `--body-file` 経由に切り替える（issue-cross-repo-create.md L100-104 の security allow-list パターン借用）。未指定時は既存動作（後方互換）。

**理由**: `gh issue create -R <owner/repo>` で cross-repo 起票が可能。body に改行を含む場合の安全な渡し方として `--body-file` が推奨。

### D6: round loop の STATE 管理

per-issue dir の `STATE` ファイルに現在状態を書き込む（running / reviewing / fixing / done / failed / circuit_broken）。orchestrator がポーリングで完了検知（`OUT/report.json` の存在確認）。

**理由**: ADR-017 P5 準拠。STATE ファイルで外部から状態観察可能。

## Risks / Trade-offs

- **tmux セッション依存**: cld セッションが tmux に依存するため CI 環境では smoke test に mock が必要
- **per-issue dir パストラバーサル**: spec-review-orchestrator.sh と同等の検証（絶対パス + `..` 禁止）で対応
- **round loop の max_rounds**: 超過時は circuit_broken で明示的に失敗扱い（無限ループ回避）
- **codex unreliable**: codex 2 回失敗で `status: codex_unreliable` として graceful degradation
