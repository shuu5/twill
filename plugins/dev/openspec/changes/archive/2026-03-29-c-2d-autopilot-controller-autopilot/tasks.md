## 1. セッション管理コマンド（3個）

- [x] 1.1 `commands/autopilot-init.md` 作成: autopilot-init.sh + session-create.sh ラッパー、旧マーカー残存警告
- [x] 1.2 `commands/autopilot-launch.md` 作成: state-write --init、DEV_AUTOPILOT_SESSION 廃止、crash-detect.sh フック設定
- [x] 1.3 `commands/autopilot-poll.md` 作成: state-read ポーリング、crash-detect.sh 連携、single/phase モード

## 2. Phase 実行コマンド（2個）

- [x] 2.1 `commands/autopilot-phase-execute.md` 作成: state-read/write での状態管理、sequential/parallel モード、不変条件 D/E/F
- [x] 2.2 `commands/autopilot-phase-postprocess.md` 作成: collect → retrospective → patterns → cross-issue チェーン

## 3. 後処理/分析コマンド（4個）

- [x] 3.1 `commands/autopilot-collect.md` 作成: state-read で done Issue 判定、PR 差分収集
- [x] 3.2 `commands/autopilot-retrospective.md` 作成: state-read での情報集約、doobidoo 保存、PHASE_INSIGHTS 生成
- [x] 3.3 `commands/autopilot-patterns.md` 作成: state-read での failure 取得、パターン検出、self-improve Issue 起票
- [x] 3.4 `commands/autopilot-cross-issue.md` 作成: session-add-warning.sh 経由の警告追記

## 4. サマリー/監査コマンド（2個）

- [x] 4.1 `commands/autopilot-summary.md` 作成: state-read での集計、session-archive.sh、通知
- [x] 4.2 `commands/session-audit.md` 作成: JSONL 分析、Haiku Agent、5 カテゴリ検出

## 5. deps.yaml + co-autopilot 更新

- [x] 5.1 deps.yaml に 11 コマンドを追加（type: atomic、spawnable_by 設定）
- [x] 5.2 co-autopilot の calls セクションに 11 コマンド追加
- [x] 5.3 co-autopilot SKILL.md 更新: マーカーファイル/DEV_AUTOPILOT_SESSION 参照を全削除し、新コマンドへの呼び出しフローに書き換え

## 6. 検証

- [x] 6.1 loom check で構造検証
- [x] 6.2 loom update-readme で README 更新
- [x] 6.3 マーカーファイル参照の残存チェック（grep "MARKER_DIR\|\.done\|\.fail\|\.merge-ready\|DEV_AUTOPILOT_SESSION" で 0 件確認）
