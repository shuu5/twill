## 1. su-observer SKILL.md 書き換え

- [x] 1.1 既存の su-observer SKILL.md を読み込み、モード判定テーブルとモード分岐ロジックを特定する
- [x] 1.2 Step 0（セッション初期化）を作成: bare repo 検証、SupervisorSession 復帰 / 新規作成、Project Board 状態取得、doobidoo 記憶復元
- [x] 1.3 Step 1（常駐ループ）を作成: モードテーブルなし、LLM が文脈から判断して spawn / observe / intervene / report / compact を選択
- [x] 1.4 Step 1 に session plugin スクリプト群の具体的参照を追加: `cld-spawn`、`cld-observe`、`cld-observe-loop`、`session-state.sh`、`session-comm.sh`
- [x] 1.5 Step 2（セッション終了）を作成
- [x] 1.6 `Skill(twl:co-self-improve)` 直接呼出しを `cld-spawn` 経由に変更
- [x] 1.7 SU-1〜SU-7 制約が全て維持されていることを確認

## 2. su-observer-skill-design.md 修正

- [x] 2.1 既存の su-observer-skill-design.md を読み込み、6 モードのルーティングテーブルを特定する
- [x] 2.2 6 モードのルーティングテーブルを削除する
- [x] 2.3 行動判断ガイドライン（どのような文脈でどの行動が適切かの指針）を追加する
- [x] 2.4 ステップ構造を SKILL.md と一致させる（Step 0 初期化 / Step 1 常駐ループ / Step 2 終了）

## 3. supervision.md 軽微修正

- [x] 3.1 supervision.md のワークフロー図に「モード」という単語が使われているか確認する
- [x] 3.2 「モード」という単語が存在する場合は削除または言い換える（分岐ラベルは文脈判断の例示として維持）

## 4. co-self-improve SKILL.md 修正

- [x] 4.1 既存の co-self-improve SKILL.md を読み込み、Skill() 直接呼出しに依存した記述を特定する
- [x] 4.2 su-observer から spawn される場合の情報受取手順を冒頭に追加する（対象 session、タスク内容、観察モード）
- [x] 4.3 Skill() 直接呼出しに依存した記述を削除または spawn 前提に修正する

## 5. deps.yaml 更新

- [x] 5.1 deps.yaml の su-observer エントリを読み込み、supervises フィールドを確認する
- [x] 5.2 su-observer.supervises に co-self-improve を追加する
- [x] 5.3 `twl check` で deps.yaml の整合性を検証する
- [x] 5.4 `twl update-readme` で README を更新する
