## 1. auto-merge.md autopilot 配下ガード

- [ ] 1.1 auto-merge.md の Step 1 前に autopilot 配下判定ロジックを追加（state-read.sh で status=running 判定）
- [ ] 1.2 autopilot 配下の場合に merge/archive/cleanup を全てスキップし merge-ready 宣言のみ行う分岐を追加
- [ ] 1.3 非 autopilot 時の既存動作が変更されないことを確認

## 2. merge-gate-execute.sh CWD ガード

- [ ] 2.1 環境変数バリデーション後・MODE 判定前に CWD ガードを追加（worktrees/ 配下で exit 1）

## 3. all-pass-check.md state-write 修正

- [ ] 3.1 state-write.sh 呼び出しを旧形式（位置引数）から named-argument 形式に修正
- [ ] 3.2 autopilot 配下判定を追加し、PASS 時に worker ロールで merge-ready 遷移を行う

## 4. 検証

- [ ] 4.1 `loom check` PASS
- [ ] 4.2 `loom validate` PASS
