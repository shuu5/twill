## Context

`scripts/autopilot-orchestrator.sh` の `poll_phase()` は entries（`repo_id:issue_num` 形式）の配列を受け取るが、内部で `issue_num` のみを連想配列キーとして使用している。現行の autopilot では同一 Phase に異リポ同一番号が入るシナリオは想定外だが、クロスリポ対応（ADR-007）の拡張に備えてキーを entry 形式に統一する。

変更対象は `poll_phase()` 内部のみ。`cleanup_worker()` / `check_and_nudge()` の引数インターフェースは維持する（呼び出し側からは entry を渡している）。`state-read.sh` / `state-write.sh` は `--repo` 引数を既にサポートしている。

## Goals / Non-Goals

**Goals:**
- `issue_to_entry` / `cleaned_up` / `issue_list` のキーを entry 形式（`repo_id:issue_num`）に統一
- `state-read/state-write` 呼び出しに `--repo "$repo_id"` を渡す（`_default` 以外）
- `window_name` / tmux ウィンドウ名にクロスリポ時 `repo_id` を含める
- 単一リポ（`_default`）の既存動作を完全に維持

**Non-Goals:**
- `autopilot-launch.sh` の `REPO_ID` 形式変更
- `state-read.sh` / `state-write.sh` の `--issue` バリデーション変更
- plan.yaml の Phase 分割ロジック変更

## Decisions

### entry キーへの移行

```bash
# Before
for e in "${entries[@]}"; do
  local _issue="${e#*:}"
  issue_list+=("$_issue")
  issue_to_entry["$_issue"]="$e"
done

# After
for e in "${entries[@]}"; do
  issue_list+=("$e")          # entry 形式のまま
  issue_to_entry["$e"]="$e"   # キーも entry 形式
done
```

ループ変数名を `issue` → `entry` に変更し、entry から `repo_id` と `issue_num` を分離:
```bash
local repo_id="${entry%%:*}"
local issue_num="${entry#*:}"
```

### state-read/state-write の --repo 渡し

`_default` 時は従来通り `--issue "$issue_num"` のみ。クロスリポ時は `--repo "$repo_id"` を追加:
```bash
if [[ "$repo_id" != "_default" ]]; then
  state_read_args+=(--repo "$repo_id")
fi
```

### window_name 生成

```bash
if [[ "$repo_id" == "_default" ]]; then
  window_name="ap-#${issue_num}"
else
  window_name="ap-${repo_id}-#${issue_num}"
fi
```

### cleaned_up キー

`cleaned_up[$entry]` として entry 形式に統一。

## Risks / Trade-offs

- **リスク**: tmux ウィンドウ名が長くなる（クロスリポ時）。`repo_id` が長い場合 tmux の名前長制限に抵触する可能性。ただし現行の `repo_id` 形式（例: `loom`, `loom-plugin-dev`）では問題なし。
- **後方互換性**: 単一リポ（`_default`）はウィンドウ名・state パスが変わらないため既存スクリプトへの影響なし。
