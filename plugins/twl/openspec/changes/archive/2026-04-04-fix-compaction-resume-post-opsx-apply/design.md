## Context

`workflow-test-ready` Step 4 は「opsx-apply 実行 → IS_AUTOPILOT 判定 → pr-cycle 遷移」を一連の LLM 指示として記述している。`opsx-apply` は `/twl:apply` を通じて全タスクを実装する長時間操作であり、実行中にコンテキスト compaction が発生する可能性が高い。

compaction が発生すると、Step 4 の「opsx-apply 完了後に IS_AUTOPILOT 判定を実行せよ」という指示が消失する。compaction 復帰プロトコルは `change-id-resolve test-scaffold check opsx-apply` の 4 ステップを定義しているが、`post-opsx-apply`（IS_AUTOPILOT 判定）は独立ステップとして含まれていない。

chain ステップの順序は `scripts/chain-steps.sh` が SSOT として管理し、`compaction-resume.sh` はその順序インデックスで完了済みステップを判定する。

## Goals / Non-Goals

**Goals:**

- compaction 後に workflow-test-ready を再起動した際、`post-opsx-apply`（IS_AUTOPILOT 判定）フェーズを検出して自動再実行できること
- compaction 復帰プロトコルに `post-opsx-apply` が独立ステップとして含まれること
- `skillmd-chain-transition`（#134）の設計原則「遷移責務は SKILL.md 側」を維持すること

**Non-Goals:**

- opsx-apply 自体の実装変更
- compaction-resume.sh のコアロジック変更（ステップ順序判定ロジックは既存のまま）
- autopilot 以外の通常フロー（IS_AUTOPILOT=false）への影響

## Decisions

### Decision 1: `post-opsx-apply` を chain-steps.sh に追加

`scripts/chain-steps.sh` の `CHAIN_STEPS` 配列に `post-opsx-apply` を `opsx-apply` の直後（`ts-preflight` の前）に追加する。

これにより `compaction-resume.sh` は既存のインデックス比較ロジックで `post-opsx-apply` を認識できる。

### Decision 2: opsx-apply 開始時・完了時の state 記録を SKILL.md に追加

`workflow-test-ready` SKILL.md Step 4 に以下を追加する:

**a. opsx-apply 開始前**: `state-write.sh` で `current_step=opsx-apply` を記録する

```bash
ISSUE_NUM=$(git branch --show-current | grep -oP '^\w+/\K\d+(?=-)' 2>/dev/null || echo "")
if [[ -n "$ISSUE_NUM" ]]; then
  bash scripts/state-write.sh --type issue --issue "$ISSUE_NUM" --role worker \
    --set "current_step=opsx-apply" 2>/dev/null || true
fi
```

**b. opsx-apply 完了後**: `state-write.sh` で `current_step=post-opsx-apply` を記録してから IS_AUTOPILOT 判定を実行する

```bash
ISSUE_NUM=$(git branch --show-current | grep -oP '^\w+/\K\d+(?=-)' 2>/dev/null || echo "")
if [[ -n "$ISSUE_NUM" ]]; then
  bash scripts/state-write.sh --type issue --issue "$ISSUE_NUM" --role worker \
    --set "current_step=post-opsx-apply" 2>/dev/null || true
fi
```

これにより、IS_AUTOPILOT 判定実行前に `current_step=post-opsx-apply` が確定し、その後 compaction が発生しても復帰可能になる。

### Decision 3: compaction 復帰プロトコルに `post-opsx-apply` ステップを追加

SKILL.md の compaction 復帰プロトコルを以下に更新する:

```bash
ISSUE_NUM=$(git branch --show-current | grep -oP '^\w+/\K\d+(?=-)' || echo "")
for step in change-id-resolve test-scaffold check opsx-apply post-opsx-apply; do
  bash scripts/compaction-resume.sh "$ISSUE_NUM" "$step" || { echo "⏭ $step スキップ"; continue; }
  case "$step" in
    opsx-apply)
      # /twl:opsx-apply <change-id> を Skill tool で実行（Step 4 の手順を再実行）
      ;;
    post-opsx-apply)
      # IS_AUTOPILOT 判定を実行（Step 4 後半の手順を再実行）
      ;;
  esac
done
```

`post-opsx-apply` を `opsx-apply` の後に置くことで、`current_step=post-opsx-apply` 時は `opsx-apply` がスキップされ（インデックス < current）、`post-opsx-apply` のみが実行される。

## Risks / Trade-offs

- **state-write.sh の失敗**: `|| true` で無視するため、失敗しても chain が停止しない。ただし、失敗時は compaction 復帰の精度が低下する（許容範囲）
- **opsx-apply の冪等性**: `current_step=opsx-apply` で compaction 後に re-run する場合、opsx-apply が途中状態で止まっていれば再実行は適切。完了していれば再実行は無駄だが、`/twl:apply` は既存実装を確認して追加適用するため大きな問題はない
- **state-write 記録の遅延**: opsx-apply 完了直後（IS_AUTOPILOT 判定直前）に state を書く設計のため、opsx-apply 実行中の compaction は `current_step=opsx-apply` のまま → 復帰時に opsx-apply を再実行する可能性がある。これは許容される（修正スコープ外）
