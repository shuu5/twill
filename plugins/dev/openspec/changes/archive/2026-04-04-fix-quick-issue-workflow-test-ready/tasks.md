## 1. workflow-setup SKILL.md Step 4 の quick 分岐追加

- [x] 1.1 `skills/workflow-setup/SKILL.md` Step 4 のシェルスニペットに is_quick 取得ロジックを追加（state-read.sh または gh issue view でラベル確認）
- [x] 1.2 is_quick=true かつ IS_AUTOPILOT=true の場合に MUST NOT で test-ready を禁止し、quick フロー案内を出力する分岐を追加（is_quick チェックを IS_AUTOPILOT チェックより先に配置）
- [x] 1.3 is_quick=false の場合は従来通り IS_AUTOPILOT=true → test-ready 実行の指示を維持

## 2. autopilot-launch.sh の quick ラベル対応

- [x] 2.1 `scripts/autopilot-launch.sh` に quick ラベル検出ロジックを追加（gh issue view でラベル確認）
- [x] 2.2 quick ラベルがある場合、PROMPT に quick フロー指示（直接実装→merge-gate のみ）の情報を付加

## 3. workflow-test-ready SKILL.md の quick 判定ガード追加

- [x] 3.1 `skills/workflow-test-ready/SKILL.md` の先頭に is_quick 判定ブロックを追加
- [x] 3.2 quick Issue の場合は「quick Issue はこのスキルをスキップ。merge-gate のみ実行してください」と出力して即座に終了する指示を記述

## 4. 動作確認

- [x] 4.1 quick ラベル付き Issue の state に is_quick=true が記録されていること（state-read.sh で確認）
- [x] 4.2 workflow-setup の Step 4 で is_quick=true の場合に test-ready Skill が呼ばれないことをコードレビューで確認
- [x] 4.3 workflow-test-ready の先頭 quick ガードが正しく分岐することをコードレビューで確認
