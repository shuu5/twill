## 1. state-write.sh ホワイトリスト拡張

- [x] 1.1 `state-write.sh` の Worker ロール許可フィールドリストに `current_step` を追加する

## 2. chain-runner.sh ステップ進行位置記録

- [x] 2.1 `chain-runner.sh` の各ステップ実行ブロック先頭に `state-write.sh --set "current_step=<step_id>"` 呼び出しを追加する
- [x] 2.2 追加対象ステップを全列挙して漏れなく対応する（init, worktree-create, board-status-update, crg-auto-build, arch-ref, opsx-propose, ac-extract）

## 3. compaction-resume.sh 新規作成

- [x] 3.1 `scripts/compaction-resume.sh` を新規作成する
- [x] 3.2 引数 `<ISSUE_NUM> <step_id>` を受け取り、`current_step` と step の順序を比較してスキップ判定する
- [x] 3.3 完了済み → exit 1、要実行 → exit 0 を返す実装にする
- [x] 3.4 ステップ順序定義（chain 順序配列）を chain-runner.sh から抽出して共有定義化する

## 4. PreCompact hook 実装

- [x] 4.1 `scripts/hooks/pre-compact-checkpoint.sh` を新規作成する
- [x] 4.2 スクリプト内で現在の ISSUE_NUM を state ファイルから取得し `current_step` を issue-{N}.json に書き込む
- [x] 4.3 エラー時は非ゼロ exit してもワークフローが継続するよう、hook 呼び出し側で `|| true` を保証する
- [x] 4.4 `hooks/hooks.json` に PreCompact hook エントリを追加する

## 5. compactPrompt 設定

- [x] 5.1 `settings.json`（または hooks 設定）に `compactPrompt` フィールドを追加する
- [x] 5.2 プロンプト内容: 「compaction サマリには現在の issue 番号・current_step・issue-{N}.json のパスを必ず含めること」を指示する

## 6. workflow SKILL.md 復帰プロトコル追記

- [x] 6.1 `workflow-setup/SKILL.md` に compaction 復帰プロトコルセクションを追記する
- [x] 6.2 `workflow-test-ready/SKILL.md` に compaction 復帰プロトコルセクションを追記する
- [x] 6.3 `workflow-pr-cycle/SKILL.md` に compaction 復帰プロトコルセクションを追記する
- [x] 6.4 復帰プロトコルの内容: 「chain 再開時は `compaction-resume.sh <ISSUE_NUM> <step>` で完了済みステップを確認し、スキップしてから実行すること」

## 7. 手動テスト・検証

- [x] 7.1 chain-runner.sh を実行して issue-{N}.json の `current_step` が更新されることを確認する
- [x] 7.2 compaction-resume.sh のスキップ判定が正しく機能することをユニットテストまたは手動確認する
- [x] 7.3 PreCompact hook が hooks.json に登録されていることを `loom check` で確認する
