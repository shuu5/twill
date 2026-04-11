## 1. state.py: RBAC 修正（pr フィールド追加）

- [x] 1.1 `cli/twl/src/twl/autopilot/state.py:34` の `_PILOT_ISSUE_ALLOWED_KEYS` に `"pr"` を追加する

## 2. state.py: `_autopilot_dir()` bare sibling 対応

- [x] 2.1 main worktree path が判明した時点で `Path(main_wt).parent / ".autopilot"` が存在するか確認し、存在すれば即 return するロジックを追加する
- [x] 2.2 bare sibling が存在しない場合は従来通り `Path(main_wt) / ".autopilot"` を返すよう fallback を維持する

## 3. state.py: エラーメッセージ改善

- [x] 3.1 `_resolve_file()` のファイル不在時エラーメッセージに「試したパス一覧」と「`export AUTOPILOT_DIR=<path>` 推奨」を追加する

## 4. autopilot-orchestrator.sh: AUTOPILOT_DIR 未設定 warning

- [x] 4.1 `autopilot-orchestrator.sh` の引数パース後（`export AUTOPILOT_DIR` の直後）で `AUTOPILOT_DIR` が空の場合に stderr へ warning を出力する

## 5. co-autopilot/SKILL.md: AUTOPILOT_DIR export 必須化明示

- [x] 5.1 `plugins/twl/skills/co-autopilot/SKILL.md` の orchestrator 起動セクションに「`AUTOPILOT_DIR` は必ず export すること（未設定時は fallback が bare sibling を自動解決するが保証されない）」を追記する

## 6. テスト追加

- [x] 6.1 `cli/twl/tests/autopilot/test_state.py` に `test_autopilot_dir_bare_sibling` を追加（bare sibling が存在する場合に bare sibling を返すことを検証）
- [x] 6.2 `cli/twl/tests/autopilot/test_state.py` に `test_autopilot_dir_main_worktree_fallback` を追加（bare sibling が存在しない場合に main worktree 配下を返すことを検証）
- [x] 6.3 `cli/twl/tests/autopilot/test_state.py` に `test_pilot_pr_write_allowed` を追加（Pilot role で `pr` フィールドの書き込みが許可されることを検証）
- [x] 6.4 `pytest cli/twl/tests/autopilot/test_state.py -v` で全テスト通過を確認する（6/6 PASS）
