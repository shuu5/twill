#!/usr/bin/env bats
# tech-stack-detect.bats - unit tests for scripts/tech-stack-detect.sh

load '../helpers/common'

setup() {
  common_setup

  # Create a git repo in sandbox
  git init "$SANDBOX/test-project" 2>/dev/null
  cd "$SANDBOX/test-project"
  git commit --allow-empty -m "initial" 2>/dev/null

  mkdir -p "$SANDBOX/test-project/scripts"
  cp "$REPO_ROOT/scripts/tech-stack-detect.sh" "$SANDBOX/test-project/scripts/"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Requirement: utility scripts unit test
# ---------------------------------------------------------------------------

@test "tech-stack-detect outputs nothing for unrecognized files" {
  cd "$SANDBOX/test-project"
  run bash -c "echo 'README.md' | bash scripts/tech-stack-detect.sh"

  assert_success
  assert_output ""
}

@test "tech-stack-detect detects R files" {
  cd "$SANDBOX/test-project"
  run bash -c "echo 'analysis.R' | bash scripts/tech-stack-detect.sh"

  assert_success
  assert_output --partial "worker-r-reviewer"
}

@test "tech-stack-detect detects Rmd files" {
  cd "$SANDBOX/test-project"
  run bash -c "echo 'report.Rmd' | bash scripts/tech-stack-detect.sh"

  assert_success
  assert_output --partial "worker-r-reviewer"
}

@test "tech-stack-detect detects supabase migrations" {
  cd "$SANDBOX/test-project"
  run bash -c "echo 'supabase/migrations/001.sql' | bash scripts/tech-stack-detect.sh"

  assert_success
  assert_output --partial "worker-supabase-migration-checker"
}

@test "tech-stack-detect detects E2E test files" {
  cd "$SANDBOX/test-project"
  run bash -c "echo 'e2e/login.spec.ts' | bash scripts/tech-stack-detect.sh"

  assert_success
  assert_output --partial "worker-e2e-reviewer"
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

@test "tech-stack-detect handles empty input" {
  cd "$SANDBOX/test-project"
  run bash -c "echo '' | bash scripts/tech-stack-detect.sh"

  assert_success
  assert_output ""
}

@test "tech-stack-detect handles multiple file types" {
  cd "$SANDBOX/test-project"
  run bash -c "printf 'analysis.R\nsupabase/migrations/001.sql\n' | bash scripts/tech-stack-detect.sh"

  assert_success
  assert_output --partial "worker-r-reviewer"
  assert_output --partial "worker-supabase-migration-checker"
}

@test "tech-stack-detect tsx requires next.config for nextjs detection" {
  cd "$SANDBOX/test-project"

  # Without next.config.* -- should not detect nextjs
  run bash -c "echo 'app.tsx' | bash scripts/tech-stack-detect.sh"
  [[ "$output" != *"worker-nextjs-reviewer"* ]]

  # With next.config.js -- should detect
  touch next.config.js
  run bash -c "echo 'app.tsx' | bash scripts/tech-stack-detect.sh"
  assert_output --partial "worker-nextjs-reviewer"
  rm -f next.config.js
}

@test "tech-stack-detect does not duplicate specialists" {
  cd "$SANDBOX/test-project"
  run bash -c "printf 'a.R\nb.R\nc.Rmd\n' | bash scripts/tech-stack-detect.sh"

  assert_success
  # Should only appear once
  local count
  count=$(echo "$output" | grep -c "worker-r-reviewer" || true)
  [ "$count" -eq 1 ]
}

# ---------------------------------------------------------------------------
# AC1: Hono PASS - .ts + import hono -> worker-code-reviewer language=hono
# RED: Hono 検出ロジック未実装のため fail する
# ---------------------------------------------------------------------------

@test "ac1: tech-stack-detect detects hono via import hono in ts file" {
  # AC: .ts ファイル変更 + PROJECT_ROOT 配下に import.*hono を含む .ts -> language=hono
  # RED: 実装前は fail する
  cd "$SANDBOX/test-project"

  # .ts ファイルに Hono import を配置
  mkdir -p src
  printf "import { Hono } from 'hono'\n" > src/app.ts

  run bash -c "echo 'src/app.ts' | bash scripts/tech-stack-detect.sh"

  assert_success
  assert_output --partial "worker-code-reviewer language=hono"
}

# ---------------------------------------------------------------------------
# AC1b: Hono PASS - .ts + from hono 形式でも検出される
# RED: Hono 検出ロジック未実装のため fail する
# ---------------------------------------------------------------------------

@test "ac1b: tech-stack-detect detects hono via from hono in ts file" {
  # AC: .ts ファイル変更 + PROJECT_ROOT 配下に from hono を含む .ts -> language=hono
  # RED: 実装前は fail する
  cd "$SANDBOX/test-project"

  mkdir -p src
  printf "import type { Context } from 'hono'\n" > src/handler.ts

  run bash -c "echo 'src/handler.ts' | bash scripts/tech-stack-detect.sh"

  assert_success
  assert_output --partial "worker-code-reviewer language=hono"
}

# ---------------------------------------------------------------------------
# AC2: .tsx のみ変更の場合 Hono 検出をトリガしない
# .ts ファイルに Hono import があっても .tsx 変更のみでは Hono 非検出
# ---------------------------------------------------------------------------

@test "ac2: tech-stack-detect does not trigger hono detection on tsx-only changes" {
  # AC: .tsx のみ変更 -> Hono 出力なし（.ts に Hono import があっても）
  # この boundary テストは実装後も保証される
  cd "$SANDBOX/test-project"

  # プロジェクト内に Hono import を持つ .ts ファイルを置く
  mkdir -p src
  printf "import { Hono } from 'hono'\n" > src/app.ts

  # 変更ファイルとして .tsx のみを渡す
  run bash -c "echo 'src/page.tsx' | bash scripts/tech-stack-detect.sh"

  assert_success
  [[ "$output" != *"worker-code-reviewer language=hono"* ]]
}

# ---------------------------------------------------------------------------
# AC3: regression - FastAPI 検出が本変更で壊れない
# ---------------------------------------------------------------------------

@test "ac3-regression: fastapi detection still works after hono addition" {
  # AC: .py + from fastapi -> worker-code-reviewer language=fastapi が出力される
  cd "$SANDBOX/test-project"

  mkdir -p app
  printf "from fastapi import FastAPI\n" > app/main.py

  run bash -c "echo 'app/main.py' | bash scripts/tech-stack-detect.sh"

  assert_success
  assert_output --partial "worker-code-reviewer language=fastapi"
}

# ---------------------------------------------------------------------------
# AC3: regression - Next.js 検出が本変更で壊れない
# ---------------------------------------------------------------------------

@test "ac3-regression: nextjs detection still works after hono addition" {
  # AC: .tsx + next.config.js -> worker-code-reviewer language=nextjs が出力される
  cd "$SANDBOX/test-project"

  touch next.config.js

  run bash -c "echo 'app/page.tsx' | bash scripts/tech-stack-detect.sh"

  assert_success
  assert_output --partial "worker-code-reviewer language=nextjs"

  rm -f next.config.js
}

# ---------------------------------------------------------------------------
# AC3: regression - R 検出が本変更で壊れない
# ---------------------------------------------------------------------------

@test "ac3-regression: r detection still works after hono addition" {
  # AC: .R ファイル -> worker-code-reviewer language=r が出力される
  cd "$SANDBOX/test-project"

  run bash -c "echo 'analysis.R' | bash scripts/tech-stack-detect.sh"

  assert_success
  assert_output --partial "worker-code-reviewer language=r"
}

# ---------------------------------------------------------------------------
# AC3: regression - supabase 検出が本変更で壊れない
# ---------------------------------------------------------------------------

@test "ac3-regression: supabase detection still works after hono addition" {
  # AC: supabase/migrations/* -> worker-supabase-migration-checker が出力される
  cd "$SANDBOX/test-project"

  run bash -c "echo 'supabase/migrations/001_init.sql' | bash scripts/tech-stack-detect.sh"

  assert_success
  assert_output --partial "worker-supabase-migration-checker"
}

# ---------------------------------------------------------------------------
# AC3: regression - e2e 検出が本変更で壊れない
# ---------------------------------------------------------------------------

@test "ac3-regression: e2e detection still works after hono addition" {
  # AC: e2e/*.spec.ts -> worker-e2e-reviewer が出力される
  cd "$SANDBOX/test-project"

  run bash -c "echo 'e2e/login.spec.ts' | bash scripts/tech-stack-detect.sh"

  assert_success
  assert_output --partial "worker-e2e-reviewer"
}

# ---------------------------------------------------------------------------
# AC4: L14 の「Hono 検出は未実装」コメントが削除されている
# RED: 未削除の間は fail する
# ---------------------------------------------------------------------------

@test "ac4: hono-todo-comment is removed from tech-stack-detect.sh" {
  # AC: L14 の「Hono 検出は未実装」コメントを削除または正の記述に置換
  # RED: コメントが残っている間は fail する
  cd "$SANDBOX/test-project"

  run grep "Hono 検出は未実装" scripts/tech-stack-detect.sh

  # grep が何もヒットしない（exit code 1）ことを期待 -> 残っていれば assert_failure が pass
  assert_failure
}

# ---------------------------------------------------------------------------
# AC5: negative - .ts のみで Hono import なし -> language=hono 出力なし
# ---------------------------------------------------------------------------

@test "ac5-negative: ts-only without hono import does not output hono" {
  # AC: .ts ファイル変更だが Hono import なし -> worker-code-reviewer language=hono が出力されない
  # RED: 実装前は判定ロジックがないため pass してしまう可能性があるが、
  #      Hono 検出実装後も正しく非検出であることを保証する
  cd "$SANDBOX/test-project"

  mkdir -p src
  printf "const x = 1;\n" > src/util.ts

  run bash -c "echo 'src/util.ts' | bash scripts/tech-stack-detect.sh"

  assert_success
  [[ "$output" != *"worker-code-reviewer language=hono"* ]]
}
