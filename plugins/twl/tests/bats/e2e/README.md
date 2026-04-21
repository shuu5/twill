# co-self-improve E2E Tests

End-to-end integration tests for the **co-self-improve framework** (Epic #172).

## 目的と前提

これらのテストは子 3〜7 のすべてのコンポーネントが連携して正しく動作することを検証します。個別の単体テスト（子 3〜7 の bats）では検証できない **統合動作** を確認するのが目的です。

検証対象:
1. **隔離保証**: test-target worktree が main 履歴を汚染しない（orphan branch）
2. **observer 連携**: workflow-observe-loop が atomic 群を呼び出し検出結果を集約する
3. **specialist 連携**: severity >= medium の検出で evaluator specialist が呼び出される
4. **Issue draft 生成**: 検出結果が Issue draft に変換されユーザー確認待ちになる
5. **reference 統合**: pattern catalog / scenario catalog / baselines が正しく参照される

## 依存関係

本テストは以下の子 Issue がすべて merge 済みである場合にのみ PASS します。依存未 merge の場合は各テストが `skip` されます（CI 安定性のため）:

| 子 Issue | 内容 |
|----------|------|
| 子 3 (#175) | test-project-{init,reset,scenario-load} atomic コマンド |
| 子 4 (#176) | observe-once + problem-detect + issue-draft-from-observation |
| 子 5 (#177) | workflow-observe-loop + observe-and-detect composite |
| 子 6 (#178) | observer-evaluator specialist + observer-evaluator-parser.sh |
| 子 7 (#179) | refs/test-scenario-catalog.md, refs/observation-pattern-catalog.md, refs/load-test-baselines.md |

## ローカル実行コマンド

```bash
# smoke テスト（タイムアウト 5 分）
bats --timeout 300 plugins/twl/tests/bats/e2e/co-self-improve-smoke.bats

# regression テスト（タイムアウト 10 分）
bats --timeout 600 plugins/twl/tests/bats/e2e/co-self-improve-regression.bats

# 両方まとめて実行
bats --timeout 600 plugins/twl/tests/bats/e2e/
```

## 実行時間目安

| テストスイート | 通常実行 | skip 時 |
|---------------|----------|---------|
| smoke (7 ケース) | ~1 分 | < 1 秒 |
| regression (5 ケース) | ~3 分 | < 1 秒 |

## Mock / Stub の挙動

e2e tests では以下の外部依存をすべて stub します:

| 外部依存 | stub 方法 | 場所 |
|----------|-----------|------|
| `tmux` | `STUB_BIN/tmux` スクリプト | `git-fixture.bash: mock_tmux_window()` |
| `cld` (Claude agent) | `STUB_BIN/cld` スクリプト | `git-fixture.bash: mock_agent_call()` |
| `gh` (GitHub CLI) | `STUB_BIN/gh` スクリプト | `common.bash: stub_command()` |
| MCP tools | 静的 JSON fixture | テスト内でインライン |

**実際の LLM 呼び出しは一切行いません。** すべてのスペシャリスト呼び出しは mock されます。

## 失敗時のデバッグ方法

### skip が多い場合

依存子 Issue が未 merge のため。対象 Issue のマージ状況を確認:

```bash
gh project item-list "$(twl config get project-board.number)" --owner "$(twl config get project-board.owner)" --format json --limit 200 \
  | jq -r '.items[] | select(.status != "Done") | "\(.content.number) [\(.status)] \(.content.title)"' \
  | grep -E "子 [3-7]"
```

### テストが FAIL する場合

1. エラーメッセージを確認: `bats --verbose-run plugins/twl/tests/bats/e2e/co-self-improve-smoke.bats`
2. sandbox ディレクトリのアーティファクトを確認（`common_teardown` 前に `echo $SANDBOX`）
3. stub の挙動確認: `STUB_BIN` に生成されたスクリプトを直接実行

### aggregated.json が生成されない場合

workflow-observe-loop の出力ディレクトリを確認:
- smoke: `$TMP_REPO/.observation/last/aggregated.json`
- regression: `$TMP_REPO/.observation/last/aggregated.json`

環境変数 `OBSERVATION_DIR` で出力先を変更できる場合はそちらを参照。

## ファイル構成

```
tests/bats/e2e/
├── co-self-improve-smoke.bats      # smoke 7 ケース
├── co-self-improve-regression.bats # regression 5 ケース
└── README.md                       # このファイル

tests/bats/helpers/
└── git-fixture.bash                # e2e 用 git fixture ヘルパー (5 関数)
    ├── init_temp_repo
    ├── cleanup_temp_repo
    ├── mock_tmux_window
    ├── mock_agent_call
    └── verify_orphan_branch
```
