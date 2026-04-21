## Why

su-observer が controller を spawn する際、skill が Step 0 で自律取得可能な情報（Issue body / comments / explore summary / Phase 手順）を prompt に転記する習性が再発している。直近の観測（session 7f960078）では 63 行中 60 行（95%）が冗長転記であり、LLM budget を圧迫し skill 自律性を阻害する構造的問題となっている。

## What Changes

- `plugins/twl/skills/su-observer/refs/pitfalls-catalog.md`: §10「spawn prompt 最小化原則」新設（MUST NOT 表 7 項目 + MUST 5 項目 + `--force-large` 例外 + 境界補足）+ §3.5 改訂（「全て prompt に包含」→「observer 固有文脈のみ包含、§10 参照」）
- `plugins/twl/skills/su-observer/SKILL.md`: L331-338「spawn プロンプトの文脈包含」節に `#### MUST NOT: skill 自律取得可能情報の転記` サブ節と最小 prompt 例（co-issue refine 用 5-10 行テンプレ）を追加
- `plugins/twl/skills/su-observer/scripts/spawn-controller.sh`: PROMPT_BODY 代入直後・FINAL_PROMPT 生成前に 30 行 threshold のサイズ guard を追加（`--force-large` で suppress、strip して cld-spawn に渡さない）
- `plugins/twl/tests/bats/scripts/spawn-controller-prompt-size.bats`: 5 テストケース新規追加（30 行以下 OK / 31 行以上 WARN / --force-large suppress / --force-large strip / 空 prompt OK）
- `plugins/twl/deps.yaml`: 新規 bats ファイル登録（必要に応じて既存規約に従う）

## Capabilities

### New Capabilities

- `spawn-controller.sh` が 30 行超の prompt に対して stderr に `WARN: prompt size` を出力する（§10 spawn prompt 最小化原則への違反を即時通知）
- `--force-large` フラグで警告を suppress でき、かつ cld-spawn 引数から自動 strip される（エスケープハッチ付き安全設計）
- pitfalls-catalog §10 が起動時 memory 検索でヒットし、再発を構造的に抑止する

### Modified Capabilities

- pitfalls-catalog §3.5 の「全て prompt に包含」が §10 への明示的参照を伴う最小化原則に改訂される
- SKILL.md の「spawn プロンプトの文脈包含」節が MUST / MUST NOT 二軸に整理され、典型的な最小 prompt 例が参照可能になる

## Impact

- `plugins/twl/skills/su-observer/refs/pitfalls-catalog.md`: §10 新設（+55 行）、§3.5 改訂（1 行修正）
- `plugins/twl/skills/su-observer/SKILL.md`: L331-338 周辺に +25 行
- `plugins/twl/skills/su-observer/scripts/spawn-controller.sh`: PROMPT_BODY 直後に +20 行
- `plugins/twl/tests/bats/scripts/spawn-controller-prompt-size.bats`: 新規 +70 行
- `plugins/twl/deps.yaml`: +数行（bats 登録）
- 非回帰: Issue #798 co-issue refine を最小 prompt（5-10 行）で再 spawn し品質同等確認（AC6）
