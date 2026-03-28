## 1. co-autopilot SKILL.md 実装

- [x] 1.1 旧 controller-autopilot の SKILL.md を読み込み、Step 構成を chain-driven 形式に変換
- [x] 1.2 co-autopilot SKILL.md に Step 0〜5 を実装（引数解析、plan.yaml 生成、計画承認、セッション初期化、Phase ループ、完了サマリー）
- [x] 1.3 self-improve ECC 照合ロジックを Phase ループ内（autopilot-patterns 呼び出し後）に組み込み
- [x] 1.4 TaskCreate/TaskUpdate による Phase 進捗管理を追加

## 2. co-issue SKILL.md 実装

- [x] 2.1 旧 controller-issue の SKILL.md を読み込み、4 Phase フローを移植
- [x] 2.2 co-issue SKILL.md に Phase 1〜4 を実装（問題探索、分解判断、精緻化ループ、一括作成）
- [x] 2.3 explore-summary 検出フロー（B-7 stub）を完全実装
- [x] 2.4 TaskCreate/TaskUpdate による Phase 進捗管理を追加
- [x] 2.5 Phase 4 完了後のクリーンアップと次ステップ案内を実装

## 3. co-project SKILL.md 実装

- [x] 3.1 旧 controller-project / controller-project-migrate / controller-project-snapshot の SKILL.md を読み込み
- [x] 3.2 co-project SKILL.md に Step 0（3モードルーティング: create / migrate / snapshot）を実装
- [x] 3.3 create モードの Step 1〜4 を実装（入力確認、project-create、Rich Mode チェック、governance 適用）
- [x] 3.4 migrate モードの Step 1〜3 を実装（現在地確認、project-migrate、governance 再適用）
- [x] 3.5 snapshot モードの Step 1〜5 を実装（入力確認、analyze、classify、generate、完了レポート）

## 4. co-architect SKILL.md 実装

- [x] 4.1 旧 controller-architect の SKILL.md を読み込み、Step 構成を移植
- [x] 4.2 co-architect SKILL.md に Step 0〜8 を実装（--group 分岐、コンテキスト収集、探索、完全性チェック、Phase 計画、Issue 分解、整合性チェック、ユーザー確認、一括作成）
- [x] 4.3 TaskCreate/TaskUpdate による Step 進捗管理を追加

## 5. Issue テンプレート移植

- [x] 5.1 旧 plugin の Issue テンプレートを確認し、refs/ref-issue-template-bug.md を作成
- [x] 5.2 refs/ref-issue-template-feature.md を作成

## 6. deps.yaml 更新と検証

- [x] 6.1 deps.yaml の skills セクション（4 controllers）の can_spawn を実装に合わせて更新
- [x] 6.2 deps.yaml の refs セクションに ref-issue-template-bug, ref-issue-template-feature を追加
- [x] 6.3 `loom check` を実行して全参照の整合性を検証
- [x] 6.4 `loom update-readme` を実行して README を更新
