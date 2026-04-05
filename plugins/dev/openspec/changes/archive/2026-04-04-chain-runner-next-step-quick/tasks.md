## 1. chain-steps.sh に QUICK_SKIP_STEPS 追加

- [x] 1.1 `scripts/chain-steps.sh` に `QUICK_SKIP_STEPS` 配列を追加（crg-auto-build, arch-ref, opsx-propose, ac-extract, change-id-resolve, test-scaffold, check, opsx-apply）

## 2. state-write.sh / state-read.sh の is_quick フィールド対応

- [x] 2.1 `scripts/state-write.sh` の issue-{N}.json スキーマに `is_quick` フィールドを追加（boolean 型、`--set is_quick=...` で設定可能）
- [x] 2.2 `scripts/state-read.sh` で `--field is_quick` が正しく返ることを確認（フィールドなし時は空文字を返す）

## 3. step_init での is_quick 永続化

- [x] 3.1 `scripts/chain-runner.sh` の `step_init` 関数末尾に `state-write.sh --role worker --set "is_quick=$is_quick"` を追加（エラーは `|| true` で無視）

## 4. chain-runner.sh に next-step コマンドを追加

- [x] 4.1 `step_next_step` 関数を実装（引数: issue_num, current_step）
- [x] 4.2 `state-read.sh` で is_quick を取得し、CHAIN_STEPS を走査して次ステップを決定する
- [x] 4.3 is_quick=true の場合 QUICK_SKIP_STEPS を除外する
- [x] 4.4 全ステップ完了時は `done` を出力する
- [x] 4.5 コマンドディスパッチャーに `next-step` を追加

## 5. compaction-resume.sh の is_quick 対応

- [x] 5.1 `scripts/compaction-resume.sh` で `state-read.sh --field is_quick` を取得する処理を追加
- [x] 5.2 is_quick=true かつ QUERY_STEP が QUICK_SKIP_STEPS に含まれる場合 exit 1 を返す（既存判定の前に配置）

## 6. workflow-setup/SKILL.md の quick 分岐機械化

- [x] 6.1 `skills/workflow-setup/SKILL.md` から quick 分岐の LLM 判断記述を除去
- [x] 6.2 各ステップ間で `NEXT=$(bash scripts/chain-runner.sh next-step "$ISSUE_NUM" "<current_step>")` を呼ぶ形式に変更
- [x] 6.3 is_quick=true/false の自然言語分岐判定コードを削除
