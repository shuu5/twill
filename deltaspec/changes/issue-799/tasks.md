## 1. pitfalls-catalog 改訂（R1 対策）

- [ ] 1.1 `plugins/twl/skills/su-observer/refs/pitfalls-catalog.md` §3.5 の「**全て** prompt に包含」を「**observer 固有文脈のみ**を包含（§10 参照、自律取得可能情報は MUST NOT）」に改訂
- [ ] 1.2 `pitfalls-catalog.md` §10「spawn prompt 最小化原則」を新設（MUST NOT 表 7 項目以上 + MUST 5 項目 + `--force-large` 例外 + 境界補足「observer own-read vs skill auto-fetch」）

## 2. spawn-controller.sh size guard 追加（R4 対策）

- [ ] 2.1 `plugins/twl/skills/su-observer/scripts/spawn-controller.sh` の PROMPT_BODY 代入行を特定する（意味的位置: `PROMPT_BODY="$(cat "$PROMPT_FILE")"` 行直後、`FINAL_PROMPT` 生成前）
- [ ] 2.2 `--force-large` 検出ループを独立実装（既存 `--help/-h` ループとは別、size guard 判定直前）
- [ ] 2.3 `PROMPT_LINE_COUNT=$(printf '%s\n' "$PROMPT_BODY" | wc -l)` + 30 行 threshold 判定 + stderr 警告出力を実装
- [ ] 2.4 `NEW_ARGS` 配列で `--force-large` を strip、`set -- "${NEW_ARGS[@]+${NEW_ARGS[@]}}"` で `$@` を更新（set -u 安全な形式）

## 3. bats テスト追加（size guard 検証）

- [ ] 3.1 既存 bats mock 規約を確認（`plugins/twl/tests/bats/scripts/merge-gate-check-spawn.bats` 等参照）
- [ ] 3.2 `plugins/twl/tests/bats/scripts/spawn-controller-prompt-size.bats` を新規作成（5 テストケース: 30 行以下 OK / 31 行超 WARN / --force-large suppress / --force-large strip / 空 prompt OK）
- [ ] 3.3 `plugins/twl/deps.yaml` に新規 bats ファイルを登録（既存規約に従う、必要な場合）
- [ ] 3.4 `bats plugins/twl/tests/bats/scripts/spawn-controller-prompt-size.bats` で全テスト PASS を確認

## 4. SKILL.md 補強（R2 対策）

- [ ] 4.1 `plugins/twl/skills/su-observer/SKILL.md` の「spawn プロンプトの文脈包含」節（L331-338 周辺）を特定
- [ ] 4.2 `#### MUST NOT: skill 自律取得可能情報の転記` サブ節を追加（7 項目列挙: Issue body・comments・explore summary・architecture・Phase 手順・past memory 生データ・bare repo/worktree 構造）
- [ ] 4.3 co-issue refine 向け最小 prompt 例（5-10 行型テンプレ）を追加（§10 MUST 5 項目を網羅）

## 5. 非回帰検証（AC6）

- [ ] 5.1 Issue #798 に対して §10 MUST 5 項目のみの最小 prompt（5-10 行）を作成
- [ ] 5.2 `spawn-controller.sh` の size guard で `WARN: prompt size` が出ないことを確認
- [ ] 5.3 再 spawn された co-issue refine が `issue-critic` PASS を達成することを確認
- [ ] 5.4 前回実装（63 行 prompt）と品質同等確認（AC 精緻化・technical accuracy 欠落なし）
- [ ] 5.5 Issue #799 に完了コメント記録（prompt 行数、specialist-audit 結果、observed quality 比較）
