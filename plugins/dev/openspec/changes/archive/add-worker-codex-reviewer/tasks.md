## 1. worker-codex-reviewer agent 作成

- [x] 1.1 `agents/worker-codex-reviewer.md` を新規作成（frontmatter: type=specialist, model=sonnet, tools=[Bash,Read,Glob,Grep], skills=[ref-issue-quality-criteria, ref-specialist-output-schema]）
- [x] 1.2 環境チェック処理を実装（`command -v codex` + `CODEX_API_KEY` チェック → 失敗時に `status: PASS, findings: []` で即完了）
- [x] 1.3 `<review_target>` / `<target_files>` の入力解析処理を実装
- [x] 1.4 Issue body を一時ファイルに書き出し `codex exec --sandbox read-only` を実行するプロンプトを実装
- [x] 1.5 codex の自由形式出力を specialist 共通スキーマ（status + findings[]）に変換する処理を実装
- [x] 1.6 findings の category を `codex-review` に設定

## 2. co-issue Phase 3b 修正

- [x] 2.1 `skills/co-issue/SKILL.md` Phase 3b の spawn ブロックに `Agent(subagent_type="dev:dev:worker-codex-reviewer", ...)` を追加（既存 issue-critic/issue-feasibility と同形式）
- [x] 2.2 Step 3c の結果集約テーブルに worker-codex-reviewer 行を追加

## 3. deps.yaml 更新

- [x] 3.1 `deps.yaml` の agents セクションに worker-codex-reviewer を specialist として登録（spawnable_by, can_spawn, skills, description を設定）
- [x] 3.2 co-issue の calls に `specialist: worker-codex-reviewer` を追加
- [x] 3.3 co-issue の tools に `worker-codex-reviewer` を追加

## 4. 検証

- [x] 4.1 `loom check` を実行して PASS を確認
- [x] 4.2 `loom update-readme` を実行
