## 1. deps.yaml 準備

- [ ] 1.1 issue-structure の spawnable_by を [controller] → [controller, workflow] に拡張
- [ ] 1.2 issue-spec-review (composite) の spawnable_by を [controller] → [controller, workflow] に拡張
- [ ] 1.3 issue-review-aggregate の spawnable_by を [controller] → [controller, workflow] に拡張
- [ ] 1.4 issue-arch-drift の spawnable_by を [controller] → [controller, workflow] に拡張
- [ ] 1.5 issue-create の spawnable_by を [controller] → [controller, workflow] に拡張
- [ ] 1.6 workflow-issue-lifecycle エントリ（type: workflow, spawnable_by, can_spawn）を追加
- [ ] 1.7 issue-lifecycle-orchestrator エントリ（scripts セクション）を追加
- [ ] 1.8 `twl check` で PASS 確認

## 2. issue-create.md 拡張

- [ ] 2.1 --repo <owner/repo> オプションを引数テーブルに追加
- [ ] 2.2 引数解析ステップに --repo 抽出を追加
- [ ] 2.3 Issue 作成ステップに --repo 分岐（gh issue create -R <repo> --body-file）を追加
- [ ] 2.4 既存テストが全て PASS することを確認

## 3. workflow-issue-lifecycle SKILL.md 新規作成

- [ ] 3.1 plugins/twl/skills/workflow-issue-lifecycle/ ディレクトリ作成
- [ ] 3.2 SKILL.md 作成（frontmatter: type=workflow, user-invocable=true, spawnable_by=[controller,user], can_spawn=[composite,atomic,specialist]）
- [ ] 3.3 冒頭で spec-review-session-init.sh 1 呼び出し実装
- [ ] 3.4 per-issue dir 入力インターフェース（$1 = abs path）実装
- [ ] 3.5 IN/ ファイル読み込み（draft.md, arch-context.md, policies.json, deps.json）実装
- [ ] 3.6 round loop 全分岐実装（CRITICAL再ループ/WARNING終了/clean終了/circuit_broken/codex_unreliable）
- [ ] 3.7 STATE ファイル書き込み（running/reviewing/fixing/done/failed/circuit_broken）実装
- [ ] 3.8 OUT/report.json 書き込み（status/issue_url/rounds/findings_final/warnings_acknowledged）実装
- [ ] 3.9 ファイル経由 I/O 確認（IN/ 以外のパス・env var 参照なし）

## 4. issue-lifecycle-orchestrator.sh 新規作成

- [ ] 4.1 plugins/twl/scripts/issue-lifecycle-orchestrator.sh 作成
- [ ] 4.2 --per-issue-dir 引数パーサー実装（絶対パス検証 + パストラバーサル対策）
- [ ] 4.3 */IN/draft.md が存在するサブディレクトリ検出実装
- [ ] 4.4 決定論的 window 名 coi-<sid8>-<index> 実装
- [ ] 4.5 flock による window 名衝突回避実装
- [ ] 4.6 || continue による失敗局所化実装
- [ ] 4.7 Resume 対応（done スキップ / failed リセット）実装
- [ ] 4.8 printf '%q' クォートで tmux 引数を安全に渡す実装
- [ ] 4.9 cld 位置引数起動（-p/--print 不使用）実装
- [ ] 4.10 wrapper script 方式でプロンプトを渡す実装
- [ ] 4.11 OUT/report.json ポーリング完了検知実装（MAX_POLL * POLL_INTERVAL タイムアウト）
- [ ] 4.12 chmod +x で実行可能に設定

## 5. テスト追加

- [ ] 5.1 plugins/twl/tests/bats/scripts/issue-lifecycle-orchestrator.bats 新規作成（flock/||continue/決定論的命名/resume/MAX_PARALLEL）
- [ ] 5.2 plugins/twl/tests/scenarios/workflow-issue-lifecycle-smoke.test.sh 新規作成（CI モック対応、gh issue create スキップ）
- [ ] 5.3 bats テスト PASS 確認
- [ ] 5.4 co-issue-phase3-specialist.bats 互換確認

## 6. 最終検証

- [ ] 6.1 twl validate / structure check 違反なし確認
- [ ] 6.2 spec-review-orchestrator.sh 非改変確認（diff）
- [ ] 6.3 workflow-issue-refine/SKILL.md 非改変確認（diff）
- [ ] 6.4 co-issue/SKILL.md 非改変確認（diff）
- [ ] 6.5 twl update-readme 実行
