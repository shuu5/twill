## Context

`chain-runner.sh` は `chain-steps.sh` を source して `QUICK_SKIP_STEPS` と `DIRECT_SKIP_STEPS` の両配列を取得する。`step_next_step()` と `step_chain_status()` は `is_quick` フラグによる `QUICK_SKIP_STEPS` スキップを実装しているが、`mode=direct` による `DIRECT_SKIP_STEPS` スキップを実装していない。Python `chain.py` の `next_step()` は両方を正しく処理しており、Bash と Python の間に実装差異がある（ADR-015 Decision 3 参照）。

## Goals / Non-Goals

**Goals:**
- `step_next_step()` に `mode=direct` 時の `DIRECT_SKIP_STEPS` スキップロジックを追加する
- `step_chain_status()` に `mode=direct` 時のスキップ表示を追加する
- Python `chain.py` の `next_step()` と動作を一致させる

**Non-Goals:**
- `chain-steps.sh` の `DIRECT_SKIP_STEPS` 定義変更
- Python `chain.py` の変更
- その他の `step_*` 関数への影響

## Decisions

**Decision 1: `mode` の state 読み込み**

`step_next_step()` は既に `is_quick` を `python3 -m twl.autopilot.state read ... --field is_quick` で取得している。同じパターンで `mode` を取得し、`"direct"` と比較する。

実装イメージ:
```bash
# mode を state から取得
local mode
mode="$(python3 -m twl.autopilot.state read --autopilot-dir "$(resolve_autopilot_dir)" --type issue --issue "$issue_num" --field mode 2>/dev/null || echo "")"

# ...ループ内...
if [[ "$mode" == "direct" ]] && printf '%s\n' "${DIRECT_SKIP_STEPS[@]}" | grep -qxF "$step"; then
  continue
fi
```

**Decision 2: `step_chain_status()` の表示**

`QUICK_SKIP_STEPS` スキップ時は `(skipped/quick)` ラベルを付けている。`DIRECT_SKIP_STEPS` スキップ時は `(skipped/direct)` ラベルを付け、同じ `⊘` 記号を使う。

**Decision 3: mode 取得失敗時のデフォルト**

`mode` 取得に失敗した場合は空文字列として扱い、`DIRECT_SKIP_STEPS` スキップを行わない（既存の `is_quick` と同様）。

## Risks / Trade-offs

- **影響範囲は最小**: `step_next_step()` と `step_chain_status()` の 2 関数のみ変更。他のロジックに影響なし。
- **state 読み込みコスト**: `mode` 取得のために `python3 -m twl.autopilot.state read` を 1 回追加するが、既存の `is_quick` 取得と同様のパターンで問題なし。
