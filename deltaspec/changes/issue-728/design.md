# Design: supervisor hook non-bare graceful degradation

## Goals

- supervisor hook 5 本（heartbeat, input-wait, input-clear, skill-step, session-end）に bare repo 構造判定ガードを追加し、non-bare 検出時は exit 0 で no-op 終了させる
- architecture spec（vision.md + supervision.md）に bare repo 前提制約を明文化し、architectural constraint として文書化する

## Non-Goals

- 通常 git リポジトリ（`.git/` のみ）への完全対応実装（architecture constraint により Non-Goal）
- Issue #725 の AC 文言の retroactive 書き換え
- SESSION_ID サニタイズ（別 Issue #729）
- `run_hook_with_autopilot()` 関数名乖離の修正（別 Issue #730）
- テスト副作用の解消（別 Issue #731）
- ADR 新規作成

## 変更点一覧

| ファイル | 変更内容 |
|----------|---------|
| `plugins/twl/scripts/hooks/supervisor-heartbeat.sh` | bare repo 構造ガード追加 + コメント統一 |
| `plugins/twl/scripts/hooks/supervisor-input-wait.sh` | bare repo 構造ガード追加 + コメント統一 |
| `plugins/twl/scripts/hooks/supervisor-input-clear.sh` | bare repo 構造ガード追加 + コメント統一 |
| `plugins/twl/scripts/hooks/supervisor-skill-step.sh` | bare repo 構造ガード追加 + コメント統一 |
| `plugins/twl/scripts/hooks/supervisor-session-end.sh` | bare repo 構造ガード追加 + コメント統一 |
| `plugins/twl/architecture/vision.md` | Constraints 節末尾に supervisor hook の bare repo 前提を 1 行追記 |
| `plugins/twl/architecture/domain/contexts/supervision.md` | SU-* 表末尾に SU-8 を新規追加 |
| `plugins/twl/tests/scenarios/supervisor-event-emission-hooks.test.sh` | non-bare 検出テストケース 5 件追加 |

## ガード実装パターン

```bash
# bare repo 構造（main/ 存在）でなければ no-op
GIT_COMMON_DIR=$(git rev-parse --git-common-dir 2>/dev/null)
if [[ -z "$GIT_COMMON_DIR" ]]; then
  exit 0
fi
if [[ ! -d "${GIT_COMMON_DIR}/../main" ]]; then
  exit 0
fi
```

判定に `[[ -d ... ]]` を採用した理由：bare + worktree 構造・non-bare のどちらでも副作用なく正確に分岐できる。`git rev-parse --is-bare-repository` は worktree から実行すると `false` を返すため不採用。
