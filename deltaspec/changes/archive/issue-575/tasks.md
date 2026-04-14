## 1. issue-lifecycle-orchestrator.sh の変更

- [x] 1.1 `usage()` の `--per-issue-dir` 説明に `--model` オプションの説明を追加
- [x] 1.2 変数宣言に `WORKER_MODEL="sonnet"` を追加
- [x] 1.3 引数パーサーに `--model) WORKER_MODEL="$2"; shift 2 ;;` を追加
- [x] 1.4 `spawn_session` 内の `cld-spawn` 呼び出しに `--model "${WORKER_MODEL}"` を追加

## 2. cld-spawn の変更

- [x] 2.1 `Usage` コメントに `--model MODEL` オプションを追加
- [x] 2.2 変数宣言に `CLD_MODEL=""` を追加
- [x] 2.3 引数パーサーに `--model) CLD_MODEL="$2"; shift 2 ;;` を追加
- [x] 2.4 ランチャースクリプト生成部（`printf '%q\n' "${CLD_PATH:-$SCRIPT_DIR/cld}"` の箇所）を `CLD_MODEL` 有無で条件分岐するよう修正

## 3. co-issue SKILL.md の変更

- [x] 3.1 Phase 3 の orchestrator 呼び出し（`bash scripts/issue-lifecycle-orchestrator.sh`）に `--model sonnet` を追加
- [x] 3.2 Phase 4 の retry 呼び出し（`bash scripts/issue-lifecycle-orchestrator.sh ... --resume`）に `--model sonnet` を追加
