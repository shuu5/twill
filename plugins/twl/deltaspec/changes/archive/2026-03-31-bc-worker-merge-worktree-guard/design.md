## Context

autopilot アーキテクチャでは Pilot（main/ worktree で動作）が複数の Worker（feature worktree で動作）を管理する。以下の不変条件が定義されている:

- **不変条件B**: Worktree 削除は Pilot 専任
- **不変条件C**: Worker はマージ禁止（merge-ready 宣言のみ）

現状、`auto-merge.md` と `merge-gate-execute.sh` にこれらの不変条件を強制するガードが存在しない。Worker が pr-cycle チェーンを完走すると、autopilot 配下かどうかに関係なく merge と worktree 削除を実行してしまう。

## Goals / Non-Goals

**Goals:**

- `auto-merge.md` で autopilot 配下判定を行い、該当時は merge/worktree 削除をスキップ
- `merge-gate-execute.sh` で CWD ガードを追加し、worktrees/ 配下からの実行を拒否
- `all-pass-check.md` で autopilot 配下時に merge-ready 宣言を行う

**Non-Goals:**

- `--auto`/`--auto-merge` フラグの廃止（#47 のスコープ）
- `state-write.sh` の構文修正（#54 のスコープ）
- 不変条件の自動テスト追加（別 Issue）

## Decisions

### 1. autopilot 配下判定パターン

`state-read.sh --type issue --issue "$ISSUE_NUM" --field status` で issue-{N}.json の status を取得。`running` であれば autopilot 配下と判定する。

```bash
AUTOPILOT_STATUS=$(bash scripts/state-read.sh --type issue --issue "$ISSUE_NUM" --field status 2>/dev/null || echo "")
IS_AUTOPILOT=$([[ "$AUTOPILOT_STATUS" == "running" ]] && echo true || echo false)
```

**理由**: state-read.sh は既に jq インジェクション防止・バリデーション・存在しないファイルへの graceful 対応を実装済み。新規の判定ロジックを追加する必要がない。

### 2. CWD ガードパターン（worktree-delete.sh と同一）

```bash
cwd=$(pwd)
if [[ "$cwd" == */worktrees/* ]]; then
  echo "ERROR: merge-gate-execute.sh は main/ worktree から実行してください" >&2
  exit 1
fi
```

**理由**: `worktree-delete.sh:30-39` で既に同一パターンが使用されており、一貫性を維持。

### 3. auto-merge.md の分岐

autopilot 配下時:
1. `state-write.sh` で status を `merge-ready` に遷移
2. merge/cleanup/worktree 削除を一切実行しない
3. 正常終了（Pilot に委譲）

非 autopilot 時: 従来通り merge → archive → cleanup を実行。

### 4. all-pass-check.md の分岐

全ステップ PASS 判定後、autopilot 配下判定を行い、該当時は `state-write.sh` で merge-ready に遷移。判定パターンは auto-merge.md と同一。

## Risks / Trade-offs

- **#54 依存**: state-write.sh の構文が #54 で修正される前提。#54 未マージ時は state-write 呼び出しの構文を現行に合わせる必要あり
- **CWD ガードの限界**: `cd` で CWD を変更された場合はガードをバイパスできるが、LLM ガイダンス文書の制約としては十分
- **issue-{N}.json 不在時のフォールバック**: state-read.sh が空文字列を返すため、IS_AUTOPILOT=false となり従来動作を維持。安全側に倒れる
