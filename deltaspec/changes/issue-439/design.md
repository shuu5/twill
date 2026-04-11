## Context

merge-gate はプルリクエストのマージ前最終判定を担う composite ステップ。現在は ac-verify checkpoint と all-pass-check checkpoint を読み込むが、phase-review checkpoint（specialist review 結果）は読み込んでいない。

phase-review は `workflow-pr-verify` チェーン内の `phase-review` ステップでのみ実行される。chain が実行されなければ checkpoint は生成されず、merge-gate はそれを検出しない。Wave 18-25 で 28 PRs が specialist review なしでマージされた実績がある。

修正対象:
- `plugins/twl/commands/merge-gate.md` — ドメインルール記述
- `cli/twl/src/twl/autopilot/mergegate.py` — 実装（merge 判定ロジック）

## Goals / Non-Goals

**Goals:**

- merge-gate が `phase-review.json` checkpoint の存在を検査する
- `phase-review.json` 不在時に REJECT を返す
- `scope/direct` / `quick` ラベル付き Issue は phase-review チェックをスキップ
- `phase-review.json` の CRITICAL findings (confidence >= 80) を判定に統合
- `--force` 実行時も phase-review 不在を WARNING としてログ記録

**Non-Goals:**

- phase-review 自体の実行ロジックの変更
- ac-verify checkpoint の既存ロジックの変更
- worktree-guard / worker-window-guard / running-guard の変更

## Decisions

### 1. merge-gate.md への phase-review checkpoint 統合

`checkpoint 統合（MUST）` セクションに以下を追加:

```bash
PHASE_REVIEW_STATUS=$(python3 -m twl.autopilot.checkpoint read --step phase-review --field status 2>/dev/null || echo "MISSING")
PHASE_REVIEW_FINDINGS=$(python3 -m twl.autopilot.checkpoint read --step phase-review --field findings 2>/dev/null || echo "[]")
```

### 2. scope/direct / quick ラベル例外

`gh issue view "$ISSUE_NUM" --json labels` でラベルを取得し、`scope/direct` または `quick` が含まれる場合は phase-review チェックをスキップ。

### 3. REJECT 条件の拡張

既存の severity フィルタ判定セクションを拡張:
- `PHASE_REVIEW_STATUS == "MISSING"` かつ例外ラベルなし → REJECT
- COMBINED_FINDINGS に phase-review の CRITICAL findings も統合
- `--force` 使用時でも MISSING は WARNING ログを出力

### 4. mergegate.py への _check_phase_review_guard() 追加

merge-gate.md のドメインルールに対応して、Python 実装側にも `_check_phase_review_guard()` を追加し、`execute()` メソッドの checkpoint 検査フローで呼び出す。

ただし、merge-gate.md は LLM composite コマンドであり、実際の checkpoint 読み取りと判定は LLM が担う。mergegate.py はコマンドオーケストレーター（`auto-merge` モード）で使用されるため、Python 側にも同等のガードを追加する。

## Risks / Trade-offs

- **既存テストへの影響**: phase-review.json が存在しない既存テスト環境では REJECT が返る。テストフィクスチャに phase-review.json を追加する必要がある。
- **スキップ条件の判定**: `scope/direct` / `quick` ラベルの取得は GitHub API 呼び出しを必要とする。API 失敗時はチェックを続行（fail-open ではなく、ラベル不明の場合は phase-review 必須とする）。
- **後方互換性**: 既存の autopilot Wave では phase-review.json が生成されていない可能性があるが、本 fix はこれを意図的に REJECT する（防衛的設計）。
