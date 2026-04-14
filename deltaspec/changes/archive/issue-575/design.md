## Context

`issue-lifecycle-orchestrator.sh` は co-issue v2 の Pilot 側スクリプトで、`cld-spawn` を通じて Worker セッションを tmux で起動する。現在モデル指定機能がなく、`cld` のデフォルト（opus）で Worker が起動している。

伝搬チェーンは3段階:
`co-issue SKILL.md` → `issue-lifecycle-orchestrator.sh` → `cld-spawn` → `cld`

参照: `autopilot-orchestrator.sh` は `autopilot-launch.sh` を経由して2段階でモデルを渡すが、`issue-lifecycle-orchestrator.sh` は `cld-spawn` を直接呼ぶ異なる経路のため、完全な流用はできない。

## Goals / Non-Goals

**Goals:**
- `issue-lifecycle-orchestrator.sh` に `--model` フラグを追加し、Worker セッションのモデルを外部から指定可能にする
- `cld-spawn` に `--model` オプションを追加し、ランチャースクリプト内の `cld` 起動コマンドに反映する
- `co-issue SKILL.md` の orchestrator 呼び出しに `--model sonnet` を付与してコスト削減を実現する

**Non-Goals:**
- `effort` 設定の Worker 伝搬（frontmatter `effort: high` は controller 設定として現状維持）
- `autopilot-orchestrator.sh` の変更（既に `--model` 対応済み）
- `--model` の値のバリデーション（cld コマンド側に委譲）

## Decisions

### 1. `issue-lifecycle-orchestrator.sh`: `--model` フラグ追加

```bash
WORKER_MODEL="sonnet"  # デフォルト

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model) WORKER_MODEL="$2"; shift 2 ;;
    ...
  esac
done
```

`spawn_session` の `cld-spawn` 呼び出しに `--model "${WORKER_MODEL}"` を追加:
```bash
"${SESSION_SCRIPTS}/cld-spawn" --cd "$(pwd)" --window-name "${window_name}" --env-file ~/.secrets --model "${WORKER_MODEL}"
```

`spawn_session` 関数シグネチャも `WORKER_MODEL` をグローバル変数として参照（既存の `MAX_PARALLEL` と同パターン）。

### 2. `cld-spawn`: `--model` オプション追加

引数パーサーに追加:
```bash
--model) CLD_MODEL="$2"; shift 2 ;;
```

ランチャースクリプト生成部でモデルフラグを条件付き注入:
```bash
if [[ -n "${CLD_MODEL:-}" ]]; then
  printf '%q --model %q\n' "${CLD_PATH:-$SCRIPT_DIR/cld}" "${CLD_MODEL}"
else
  printf '%q\n' "${CLD_PATH:-$SCRIPT_DIR/cld}"
fi
```

### 3. `co-issue SKILL.md`: Phase 3 と Phase 4 の呼び出し更新

Phase 3（orchestrator 呼び出し）:
```bash
bash scripts/issue-lifecycle-orchestrator.sh \
  --per-issue-dir "${LEVEL_DIR}" \
  --model sonnet
```

Phase 4（retry 呼び出し）:
```bash
bash scripts/issue-lifecycle-orchestrator.sh \
  --per-issue-dir ".controller-issue/<session-id>/per-issue/" \
  --resume \
  --model sonnet
```

## Risks / Trade-offs

- `--resume` との組み合わせ: resume 時は `WORKER_MODEL` がデフォルト（sonnet）に戻るが、`co-issue SKILL.md` 側で `--model sonnet` を明示するため問題なし
- 既存テストへの影響: `cld-spawn` のランチャースクリプト生成部の変更はスタブテストに影響する可能性がある（`CLD_PATH` 変数差し替えで対応済みパターン）
