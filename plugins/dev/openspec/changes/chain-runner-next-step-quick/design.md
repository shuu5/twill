## Context

現在の `workflow-setup/SKILL.md` は quick 分岐判断を LLM の自然言語理解に依存している。コンテキスト圧縮が発生すると `is_quick=true` の情報が失われ、quick Issue でも全ステップを実行してしまう問題がある。

関連スクリプト:
- `scripts/chain-runner.sh`: step_init で `detect_quick_label` を呼び `is_quick` を判定しているが、state に永続化していない
- `scripts/chain-steps.sh`: `CHAIN_STEPS` 配列を定義（SSOT）
- `scripts/state-write.sh`: `--set key=value` で issue-{N}.json にフィールドを書き込む
- `scripts/state-read.sh`: `--field name` で issue-{N}.json からフィールドを読み取る
- `scripts/compaction-resume.sh`: `current_step` を参照してスキップ判定するが、`is_quick` は参照していない

## Goals / Non-Goals

**Goals:**
- `chain-runner.sh next-step` コマンドの追加（is_quick + current_step → 次ステップ名を stdout に返す）
- `step_init` での `is_quick` 永続化（state-write.sh 経由）
- `chain-steps.sh` に `QUICK_SKIP_STEPS` 配列を追加
- `compaction-resume.sh` で `is_quick` を state から取得しスキップ判定に利用
- `workflow-setup/SKILL.md` の quick 分岐 LLM 判断を除去

**Non-Goals:**
- orchestrator nudge の修正（別 Issue）
- workflow-test-ready 側のガード追加（別 Issue）
- quick ラベル検出ロジック自体の変更

## Decisions

### is_quick の永続化タイミング
`step_init` 完了時（`detect_quick_label` 結果が確定した直後）に `state-write.sh --role worker --set "is_quick=..."` を呼ぶ。既存の `record_current_step` パターンに倣い、エラーは無視（`|| true`）。

### QUICK_SKIP_STEPS の定義場所
`chain-steps.sh` に追加（CHAIN_STEPS と同じファイルで SSOT 維持）:
```bash
QUICK_SKIP_STEPS=(crg-auto-build arch-ref opsx-propose ac-extract change-id-resolve test-scaffold check opsx-apply)
```

### next-step コマンドの実装
```
next-step <issue_num> <current_step>
  1. state-read.sh で is_quick を取得（なければ false）
  2. CHAIN_STEPS を走査し、current_step の次のインデックスから開始
  3. is_quick=true のとき QUICK_SKIP_STEPS に含まれるステップを除外
  4. 最初にヒットしたステップ名を stdout に出力
  5. ステップがなければ "done" を出力
```

### compaction-resume.sh の変更
is_quick チェックを追加:
- `state-read.sh --field is_quick` で is_quick を取得
- `is_quick=true` かつ `QUERY_STEP` が `QUICK_SKIP_STEPS` に含まれる → exit 1（スキップ）
- 既存の current_step 比較ロジックの前に配置

### workflow-setup/SKILL.md の変更
各ステップ間の `quick 分岐判定` 記述を削除し、代わりに:
```
NEXT=$(bash scripts/chain-runner.sh next-step "$ISSUE_NUM" "<current_step>")
```
の出力に従って次ステップを決定する形式に変更。

## Risks / Trade-offs

- **後方互換**: is_quick が存在しない既存 state は false として扱う（state-read.sh の空文字 → false のデフォルト処理で対応）
- **SKILL.md の複雑化**: next-step を使う形式にすると SKILL.md が簡潔になる一方、スクリプト依存が増える。設計哲学「機械的にできることは機械に任せる」に沿うためトレードオフを受容
- **テスト**: is_quick の state 永続化は step_init の既存テストへの影響を確認が必要
