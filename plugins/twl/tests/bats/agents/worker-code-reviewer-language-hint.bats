#!/usr/bin/env bats
# worker-code-reviewer-language-hint.bats - language hint 機構の静的検証 (Issue #1081)
#
# RED フェーズ: 実装前は全件 FAIL。実装後 GREEN になることを期待する。
# AC1-AC6 に対応する。

load '../helpers/common'

setup() {
  common_setup
  AGENT_MD="$REPO_ROOT/agents/worker-code-reviewer.md"
  FASTAPI_MD="$REPO_ROOT/agents/worker-fastapi-reviewer.md"
  HONO_MD="$REPO_ROOT/agents/worker-hono-reviewer.md"
  NEXTJS_MD="$REPO_ROOT/agents/worker-nextjs-reviewer.md"
  R_MD="$REPO_ROOT/agents/worker-r-reviewer.md"
  DEPS_YAML="$REPO_ROOT/deps.yaml"
  TECH_STACK_SH="$REPO_ROOT/scripts/tech-stack-detect.sh"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# AC1: 4 agent ファイルが削除されていること
# ---------------------------------------------------------------------------

@test "AC1: worker-fastapi-reviewer.md は削除されている" {
  [ ! -f "$FASTAPI_MD" ]
}

@test "AC1: worker-hono-reviewer.md は削除されている" {
  [ ! -f "$HONO_MD" ]
}

@test "AC1: worker-nextjs-reviewer.md は削除されている" {
  [ ! -f "$NEXTJS_MD" ]
}

@test "AC1: worker-r-reviewer.md は削除されている" {
  [ ! -f "$R_MD" ]
}

# ---------------------------------------------------------------------------
# AC2: worker-code-reviewer.md に language hint 機構が追加されていること
# ---------------------------------------------------------------------------

@test "AC2: worker-code-reviewer.md frontmatter に languages フィールドが存在する" {
  CONTENT="$(cat "$AGENT_MD")"
  echo "$CONTENT" | grep -qE '^languages:'
}

@test "AC2: frontmatter languages に fastapi/hono/nextjs/r/generic 5 値が列挙されている" {
  CONTENT="$(cat "$AGENT_MD")"
  echo "$CONTENT" | grep -qF 'fastapi'
  echo "$CONTENT" | grep -qF 'hono'
  echo "$CONTENT" | grep -qF 'nextjs'
  echo "$CONTENT" | grep -qF 'generic'
  # r は "nextjs" 等と混在するため frontmatter 区間内で確認
  echo "$CONTENT" | grep -qE '^\s*-\s*r\s*$'
}

@test "AC2: worker-code-reviewer.md に 言語別観点 (language hint) セクションが存在する" {
  CONTENT="$(cat "$AGENT_MD")"
  echo "$CONTENT" | grep -qF '## 言語別観点'
}

@test "AC2: worker-code-reviewer.md に呼び出し規約 (language=<name>: 形式) が明記されている" {
  CONTENT="$(cat "$AGENT_MD")"
  echo "$CONTENT" | grep -qE 'language=<name>:|language=fastapi:|language=hono:'
}

# ---------------------------------------------------------------------------
# AC3: deps.yaml に 4 agent 参照が残存していない
# ---------------------------------------------------------------------------

@test "AC3: deps.yaml に worker-fastapi-reviewer の参照が存在しない" {
  run grep -c 'worker-fastapi-reviewer' "$DEPS_YAML"
  [ "$output" = "0" ]
}

@test "AC3: deps.yaml に worker-hono-reviewer の参照が存在しない" {
  run grep -c 'worker-hono-reviewer' "$DEPS_YAML"
  [ "$output" = "0" ]
}

@test "AC3: deps.yaml に worker-nextjs-reviewer の参照が存在しない" {
  run grep -c 'worker-nextjs-reviewer' "$DEPS_YAML"
  [ "$output" = "0" ]
}

@test "AC3: deps.yaml に worker-r-reviewer の参照が存在しない" {
  run grep -c 'worker-r-reviewer' "$DEPS_YAML"
  [ "$output" = "0" ]
}

@test "AC3: tech-stack-detect.sh の旧 reviewer マッピングが worker-code-reviewer に統一されている" {
  # 旧 reviewer 名が残存していないこと (grep で存在を確認し、存在すれば FAIL)
  run grep -E 'worker-(fastapi|hono|nextjs|r)-reviewer' "$TECH_STACK_SH"
  [ "$status" -ne 0 ]
}

@test "AC3: tech-stack-detect.sh が language hint (language=xxx 形式) を出力する" {
  CONTENT="$(cat "$TECH_STACK_SH")"
  echo "$CONTENT" | grep -qE 'language='
}

# ---------------------------------------------------------------------------
# AC4: language hint 動作テスト (agent body 静的検証)
# ---------------------------------------------------------------------------

@test "AC4: language=fastapi: agent body に async def が含まれる" {
  CONTENT="$(cat "$AGENT_MD")"
  echo "$CONTENT" | grep -qF 'async def'
}

@test "AC4: language=fastapi: agent body に Pydantic v2 が含まれる" {
  CONTENT="$(cat "$AGENT_MD")"
  echo "$CONTENT" | grep -qF 'Pydantic v2'
}

@test "AC4: language=fastapi: agent body に Annotated が含まれる" {
  CONTENT="$(cat "$AGENT_MD")"
  echo "$CONTENT" | grep -qF 'Annotated'
}

@test "AC4: language=hono: agent body に Zod スキーマ整合性 が含まれる" {
  CONTENT="$(cat "$AGENT_MD")"
  echo "$CONTENT" | grep -qF 'Zod スキーマ'
}

@test "AC4: language=hono: agent body に @hono/zod-openapi が含まれる" {
  CONTENT="$(cat "$AGENT_MD")"
  echo "$CONTENT" | grep -qF '@hono/zod-openapi'
}

@test "AC4: language=nextjs: agent body に Server Component が含まれる" {
  CONTENT="$(cat "$AGENT_MD")"
  echo "$CONTENT" | grep -qE 'Server.*Component'
}

@test "AC4: language=nextjs: agent body に 'use client' が含まれる" {
  CONTENT="$(cat "$AGENT_MD")"
  echo "$CONTENT" | grep -qF "'use client'"
}

@test "AC4: language=r: agent body に tidyverse が含まれる" {
  CONTENT="$(cat "$AGENT_MD")"
  echo "$CONTENT" | grep -qF 'tidyverse'
}

@test "AC4: language=r: agent body に .Rmd が含まれる" {
  CONTENT="$(cat "$AGENT_MD")"
  echo "$CONTENT" | grep -qF '.Rmd'
}

# ---------------------------------------------------------------------------
# AC5: chain integrity — deps.yaml 静的チェック
# (twl check 実行は AC5 最終確認で行う。ここでは参照残存ゼロを静的に検証)
# ---------------------------------------------------------------------------

@test "AC5: deps.yaml に削除 4 agent への参照がゼロ件である" {
  run grep -cE 'worker-(fastapi|hono|nextjs|r)-reviewer' "$DEPS_YAML"
  [ "$output" = "0" ]
}

# ---------------------------------------------------------------------------
# AC6: tech-stack-detect.sh のディスパッチが worker-code-reviewer に統一されている
# (specialist-audit が依存する上流ソース — 旧 reviewer 名が SPECIALISTS に混入しない)
# ---------------------------------------------------------------------------

@test "AC6: tech-stack-detect.sh の R ファイル検出ルールが worker-r-reviewer を使用していない" {
  # R detection ルール内に旧 reviewer 名が存在しないこと
  run grep 'worker-r-reviewer' "$TECH_STACK_SH"
  [ "$status" -ne 0 ]
}

@test "AC6: tech-stack-detect.sh の FastAPI 検出ルールが worker-fastapi-reviewer を使用していない" {
  run grep 'worker-fastapi-reviewer' "$TECH_STACK_SH"
  [ "$status" -ne 0 ]
}

@test "AC6: tech-stack-detect.sh の Next.js 検出ルールが worker-nextjs-reviewer を使用していない" {
  run grep 'worker-nextjs-reviewer' "$TECH_STACK_SH"
  [ "$status" -ne 0 ]
}

@test "AC6: tech-stack-detect.sh が少なくとも 1 つの worker-code-reviewer 参照を持つ" {
  run grep -c 'worker-code-reviewer' "$TECH_STACK_SH"
  [ "$output" -ge 1 ]
}
