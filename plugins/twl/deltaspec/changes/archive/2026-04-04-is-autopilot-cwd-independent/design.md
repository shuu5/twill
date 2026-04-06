## Context

現在、IS_AUTOPILOT 判定と Issue 番号取得は `git branch --show-current` から branch 名を解析する方式に依存している。Worker が worktree ディレクトリで起動される設計では CWD リセット後も正しいブランチで動作するが、branch 依存の判定ロジック自体が脆弱であるため defense in depth として state file ベースに統一する。

AUTOPILOT_DIR は autopilot セッション起動時に環境変数として設定される。Worker セッションには AUTOPILOT_DIR が渡されるため、`$AUTOPILOT_DIR/issues/issue-*.json` を読むことで CWD に依存せず Issue 番号を取得できる。

## Goals / Non-Goals

**Goals:**
- `resolve_issue_num()` bash 関数を新設し、AUTOPILOT_DIR 設定時は state file スキャン優先で動作させる
- `chain-runner.sh` および `post-skill-chain-nudge.sh` を `resolve_issue_num()` に移行する
- `refs/ref-dci.md` の DCI 標準パターンを state file ベースに更新する
- SKILL.md 群・commands の bash スニペットを統一パターンに更新する

**Non-Goals:**
- Worker の worktree 起動方式の変更（先行 Issue で実施済み前提）
- state-read.sh の API 変更（既存インターフェース維持）
- auto-merge.sh の Layer 構造変更

## Decisions

### 1. `resolve_issue_num()` を scripts/ に共有関数として定義

`scripts/resolve-issue-num.sh` として独立ファイルに実装し、各スクリプトから `source` する方式を採用。

**ロジック:**
```bash
resolve_issue_num() {
  local issue_num=""
  # Priority 1: AUTOPILOT_DIR state file scan
  if [ -n "${AUTOPILOT_DIR:-}" ] && [ -d "$AUTOPILOT_DIR/issues" ]; then
    issue_num=$(
      for f in "$AUTOPILOT_DIR/issues/issue-"*.json; do
        [ -f "$f" ] || continue
        jq -r 'if .status == "running" then .issue else empty end' "$f" 2>/dev/null \
          || { echo "WARNING: broken JSON: $f" >&2; continue; }
      done | sort -n | head -1
    )
  fi
  # Priority 2: Fallback to git branch
  if [ -z "$issue_num" ]; then
    issue_num=$(git branch --show-current 2>/dev/null \
      | grep -oP '^\w+/\K\d+(?=-)' || echo "")
  fi
  echo "$issue_num"
}
```

### 2. chain-runner.sh の `extract_issue_num()` を置換

`source scripts/resolve-issue-num.sh` を追加し、`extract_issue_num()` の呼び出し箇所を `resolve_issue_num()` に変更。後方互換のため `extract_issue_num()` は `resolve_issue_num()` のエイリアスとして一時的に残すかどうかは不要（呼び出し側を全て変更するため廃止）。

### 3. SKILL.md bash スニペットの統一パターン

各 SKILL.md の IS_AUTOPILOT 判定ブロックを以下の統一パターンに変更:
```bash
source "$(git rev-parse --show-toplevel)/scripts/resolve-issue-num.sh" 2>/dev/null || true
ISSUE_NUM=$(resolve_issue_num)
```

AUTOPILOT_DIR が設定されていない手動実行時は git branch フォールバックが働くため、既存の手動ワークフローへの影響はない。

### 4. refs/ref-dci.md の更新

DCI 標準パターンの ISSUE_NUM 取得を state file ベース優先に変更し、git branch をフォールバックとして明記する。

## Risks / Trade-offs

- **AUTOPILOT_DIR 未設定時の挙動**: 手動実行時（AUTOPILOT_DIR 未設定）は git branch フォールバックで動作するため既存挙動を維持する。リスク低。
- **複数 running issue 時の一意性**: 最小番号採用ルールで決定論的だが、意図しない Issue に紐づく可能性がある。ただし通常1 Worker = 1 Issue のため実用上問題なし。
- **source のパス解決**: `git rev-parse --show-toplevel` を使うことで worktree 内からでもリポジトリルートを特定できる。
