## 1. su-observer SKILL.md Step 4 更新

- [x] 1.1 Step 4 の NOTE プレースホルダー行と 1 行説明を削除
- [x] 1.2 Wave 管理の完全フロー（8 サブステップ）を記述
  - [x] 1.2.1 Issue 群の Wave 分割計画（または既存計画の継続）
  - [x] 1.2.2 Wave N の Issue リスト確定
  - [x] 1.2.3 `session:spawn` で co-autopilot 起動（引数付き）
  - [x] 1.2.4 observe ループ開始（Step 5 の observe を定期実行）
  - [x] 1.2.5 Wave 完了検知 → `commands/wave-collect.md` Read → 実行（WAVE_NUM 引数付き）
  - [x] 1.2.6 `commands/externalize-state.md` Read → 実行（--trigger wave_complete）
  - [x] 1.2.7 `Skill(twl:su-compact)` 呼び出し（SU-6 制約）
  - [x] 1.2.8 次 Wave がある場合は Step 4-2 に戻る。全 Wave 完了でサマリ報告
