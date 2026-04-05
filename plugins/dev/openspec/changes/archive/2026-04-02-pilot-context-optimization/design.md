## Context

`autopilot-orchestrator.sh` は Phase 実行中（最長60分以上）に多数の `echo "[orchestrator]..."` を stdout に出力する。現状、`co-autopilot/SKILL.md` の orchestrator 呼び出しは `REPORT=$(bash ...)` 形式だが、stderr のリダイレクトがないため stdout/stderr 両方が Pilot の Bash tool output として context window に蓄積される。

なお、line 553-626 付近の Phase 開始/完了ログはすでに `>&2` が付いているが、ループ内部の Issue 進捗ログ（line 192-436）には `>&2` がない。

`autopilot-phase-postprocess.md` の retrospective/patterns は LLM 推論を含む処理だが、その実行時間・コスト推定が session.json に記録されないため、長時間実行の検出手段がない。

## Goals / Non-Goals

**Goals:**
- orchestrator の stdout を JSON レポートのみに限定し、Pilot context への進捗ログ流入をゼロにする
- orchestrator の stderr（進捗ログ）をログファイルに保存し、事後デバッグを可能にする
- postprocess の実行時間を `token_estimate` として session.json に記録する
- `$AUTOPILOT_DIR/logs/` を orchestrator 起動時に自動作成する

**Non-Goals:**
- Worker 側の context compaction 対策
- Pilot セッションの非常駐化
- Phase 間 context の削減（保持が有用なため）
- Claude API usage フィールドの直接参照（Bash tool からアクセス不可）

## Decisions

### Decision 1: `>&2` 追加による stdout 限定

`autopilot-orchestrator.sh` のループ内 `echo "[orchestrator]..."` 全行（line 192〜436）に `>&2` を追加する。`generate_phase_report` の JSON 出力（stdout）はそのまま残す。Phase 開始/完了ログはすでに `>&2` 付きのため変更不要。

**Rationale**: 最小差分で確実な効果。JSON 出力パスを変更する必要がなく、既存の `REPORT=$(bash ...)` 構文がそのまま機能する。

### Decision 2: co-autopilot/SKILL.md の stderr リダイレクト

```
REPORT=$(bash $SCRIPTS_ROOT/autopilot-orchestrator.sh \
  --plan "$PLAN_FILE" \
  --phase "$P" \
  --session "$SESSION_STATE_FILE" \
  --project-dir "$PROJECT_DIR" \
  --autopilot-dir "$AUTOPILOT_DIR" \
  $REPOS_ARG 2>"$AUTOPILOT_DIR/logs/phase-${P}.log")
```

**Rationale**: stderr をログファイルにリダイレクトすることで、Pilot context からログが完全に排除される。ログファイルは `.autopilot/logs/` に保存し git 管理外。

### Decision 3: `mkdir -p "$AUTOPILOT_DIR/logs"` の追加

orchestrator の Phase 実行開始時（`run_phase` 関数内の先頭）に追加する。logs ディレクトリが存在しない場合でもリダイレクトが機能するようにする。

### Decision 4: `token_estimate` = 経過時間ベース推定

postprocess 開始直前に `START_TIME=$(date +%s)`、完了直後に `END_TIME=$(date +%s)` を記録し、`token_estimate=$((END_TIME - START_TIME))` を秒単位で session.json の `retrospective` エントリに追記する。実際のトークン数ではなく「異常な長時間処理の検出」が目的のため経過時間で十分。

## Risks / Trade-offs

- **ログファイルサイズ**: 長時間 Phase では大量のログが生成される可能性がある。ローテーションは現時点では実装しない（Phase 単位で上書きされるため管理可能）
- **token_estimate の精度**: 実際のトークン消費量とは異なる。ただし異常検出の代替指標として十分
- **既存動作への影響**: stderr リダイレクトにより、CI/CD 環境でのログ収集方法が変わる可能性がある。ただし `.autopilot/logs/` に保存されるため情報は保持される
