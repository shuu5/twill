## 1. サニタイズブロック実装

- [ ] 1.1 `supervisor-heartbeat.sh`: SESSION_ID フォールバック `fi` 直後にサニタイズブロックを挿入
- [ ] 1.2 `supervisor-input-wait.sh`: SESSION_ID フォールバック `fi` 直後にサニタイズブロックを挿入
- [ ] 1.3 `supervisor-input-clear.sh`: SESSION_ID フォールバック `fi` 直後（TARGET_FILE 構築前）にサニタイズブロックを挿入
- [ ] 1.4 `supervisor-skill-step.sh`: SESSION_ID フォールバック `fi` 直後にサニタイズブロックを挿入
- [ ] 1.5 `supervisor-session-end.sh`: SESSION_ID フォールバック `fi` 直後にサニタイズブロックを挿入

## 2. Architecture spec 更新

- [ ] 2.1 `plugins/twl/architecture/domain/contexts/supervision.md` の SU-* 表末尾に SU-9 を追加

## 3. テスト追加

- [ ] 3.1 `supervisor-event-emission-hooks.test.sh` に `run_hook_capture_stderr()` helper を追加
- [ ] 3.2 path-traversal 攻撃パターンのテストケース追加
- [ ] 3.3 UUID 正常系テストケース追加

## 4. 検証

- [ ] 4.1 bats テストを実行し全 PASS を確認
