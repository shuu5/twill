## 1. co-issue/SKILL.md: Step 3.5 追加

- [x] 1.1 `skills/co-issue/SKILL.md` を Read し、Phase 3 完了（TaskUpdate Phase 3 → completed）と Phase 4 開始（TaskCreate「Phase 4: Issue 作成」）の間の位置を特定する
- [x] 1.2 Step 3.5 冒頭: `architecture/domain/glossary.md` の存在チェックを追加（非存在時は出力なしでスキップ）
- [x] 1.3 明示的シグナル検出: 全 Issue body の `<!-- arch-ref-start -->` タグをパースし、参照パスを抽出するロジックを記述
- [x] 1.4 構造的シグナル検出: glossary.md の MUST 用語セクションから用語名を抽出し、Issue body との完全一致照合を記述
- [x] 1.5 構造的シグナル検出: `architecture/` 配下のファイル名パターン（`contexts/*.md` 等）と Issue body の照合を記述
- [x] 1.6 ヒューリスティックシグナル検出: recommended_labels の ctx/* カウントが 3 以上の Issue を検出するロジックを記述
- [x] 1.7 シグナル集約と INFO 出力: 全シグナルを評価後に集約し、1 件以上あれば architecture-spec-dci.md 定義のフォーマットで出力
- [x] 1.8 非ブロッキング確認: INFO 出力後、ユーザー入力なしで Phase 4 に進むことを明記
- [x] 1.9 CRITICAL ブロック時のスキップ条件を Phase 3c ブロック判定の記述に追記

## 2. deps.yaml 更新

- [x] 2.1 `deps.yaml` を Read し、co-issue の参照ファイルセクションを特定する
- [x] 2.2 `architecture/contracts/architecture-spec-dci.md` を co-issue の参照ファイルに追加（Step 3.5 仕様定義の参照元）
- [x] 2.3 `architecture/domain/glossary.md` が co-issue の参照ファイルに未追加であれば追加（Step 3.5 の構造的シグナル検出で使用）

## 3. 検証

- [x] 3.1 `loom check` を実行してエラーがないことを確認
- [x] 3.2 `loom update-readme` を実行して docs を更新
