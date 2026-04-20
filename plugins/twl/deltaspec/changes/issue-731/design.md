## Goals

supervisor hook のテストが production の `main/.supervisor/events/` に直接書き込む副作用を解消する。

- su-observer 稼働中の dev 環境での誤イベント処理リスクを排除
- CI 並行実行時の race condition と orphan ファイル残留リスクを排除
- テスト異常終了（SIGINT / disk full）時の production 汚染リスクを排除

## 採用方式

**(b) env override 採用**: フック側に `TWL_SUPERVISOR_EVENTS_DIR` 環境変数による override 機構を追加。

```bash
# TEST-ONLY: TWL_SUPERVISOR_EVENTS_DIR は test sandbox 専用。production で set しないこと
EVENTS_DIR="${TWL_SUPERVISOR_EVENTS_DIR:-${GIT_COMMON_DIR}/../main/.supervisor/events}"
```

- `:-` bash パラメータ展開で空文字列と unset を同等扱い（誤設定時の fallback 保証）
- bare repo 構造ガード（`#728`）の後段に配置し、override が bare チェックを bypass しない設計
- hook ヘッダーコメントで `TEST-ONLY` を明記し production への env leak を抑止

## 変更点サマリ

### hook 側（5 本）

| ファイル | 変更内容 |
|---|---|
| `supervisor-heartbeat.sh` | `EVENTS_DIR` を `:-` 形式で override 可能に変更 + TEST-ONLY コメント追加 |
| `supervisor-input-wait.sh` | 同上 |
| `supervisor-input-clear.sh` | 同上 |
| `supervisor-skill-step.sh` | 同上 |
| `supervisor-session-end.sh` | 同上 |

### テスト側

| 変更内容 | 詳細 |
|---|---|
| sandbox 移行 | `setup_sandbox()` で `export TWL_SUPERVISOR_EVENTS_DIR="${SANDBOX}/.supervisor/events"` |
| AC-3 副作用検証 | `run_test()` 内で `find $GIT_EVENTS_DIR -newer test_start_marker` により production 汚染を自動検証 |
| AC-6 異常終了耐性 | `trap teardown_sandbox INT TERM EXIT` で強制中断時も sandbox cleanup を保証 |
| semantic bug 修正 | `run_hook_with_autopilot()` の誤った AUTOPILOT_DIR→EVENTS_DIR override 説明を削除 |
| `cleanup_git_event_file()` 廃止 | teardown_sandbox の `rm -rf` で網羅されるため削除 |

### DeltaSpec

- `plugins/twl/deltaspec/changes/issue-731/design.md`（本ファイル）を新規作成
