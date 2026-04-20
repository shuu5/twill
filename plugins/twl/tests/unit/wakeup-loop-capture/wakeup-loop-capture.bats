#!/usr/bin/env bats
# wakeup-loop-capture.bats
# Requirement: autopilot-pilot-wakeup-loop Step C の session-comm.sh capture 経由化
# Spec: Issue #686（tmux capture-pane バリデーション迂回 修正）
# Coverage: --type=unit --coverage=static
#
# 検証する仕様:
#   AC-1. Finding 2 の修正: tmux capture-pane -t <window> 直接呼び出しが 0 件
#   AC-2/4b. session-comm.sh が 1 件以上登場する
#   AC-3/4d. Finding 1 regression guard: HOTFIX #732 コメントが 2 箇所存在する
#   AC-4c. SESSION_SCRIPTS パス解決パターンが literal で 1 件以上存在する
#   AC-4e. resolve_target バリデーション言及が 1 件以上存在する
#   AC-4f. multi-worker 独立評価の言及が 1 件以上存在する
#   AC-7.  ANSI-stripped 出力でも input-waiting regex が検知される（fixture ベース）
#
# 検証方針:
#   markdown ファイル内の literal 文字列 grep のみで静的検証する。
#   CLAUDE_PLUGIN_ROOT など実行時環境変数に依存する runtime 挙動は本 bats では検証しない。

load '../../bats/helpers/common.bash'

# ---------------------------------------------------------------------------
# setup
# ---------------------------------------------------------------------------

setup() {
  common_setup
}

teardown() {
  common_teardown
}

# ===========================================================================
# Requirement: Finding 2 の修正（AC-1）
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: tmux capture-pane -t <window> 直接呼び出しが除去されている（AC-1）
# WHEN grep -Fn 'tmux capture-pane -t <window>' autopilot-pilot-wakeup-loop.md を実行する
# THEN 0 件であること（Finding 2 regression 防止）
# ---------------------------------------------------------------------------

@test "wakeup-loop-capture[ac1]: tmux capture-pane -t <window> 直接呼び出しが 0 件である" {
  local target="$REPO_ROOT/commands/autopilot-pilot-wakeup-loop.md"

  [[ -f "$target" ]]

  local count
  count=$(grep -Fn 'tmux capture-pane -t <window>' "$target" | wc -l)
  [ "$count" -eq 0 ]
}

# ===========================================================================
# Requirement: session-comm.sh 経由化（AC-2/4b）
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: session-comm.sh への言及が存在する（AC-4b）
# WHEN grep -Fc 'session-comm.sh' autopilot-pilot-wakeup-loop.md を実行する
# THEN 1 以上であること（置換が実施されたことの verify）
# ---------------------------------------------------------------------------

@test "wakeup-loop-capture[ac4b]: session-comm.sh への言及が 1 件以上存在する" {
  local target="$REPO_ROOT/commands/autopilot-pilot-wakeup-loop.md"

  [[ -f "$target" ]]

  local count
  count=$(grep -Fc 'session-comm.sh' "$target")
  [ "$count" -ge 1 ]
}

# ===========================================================================
# Requirement: SESSION_SCRIPTS パス解決（AC-4c）
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: SESSION_SCRIPTS パターンが literal で存在する（AC-4c）
# WHEN grep で SESSION_SCRIPTS="${CLAUDE_PLUGIN_ROOT}/../session/scripts" を検索する
# THEN 1 件以上存在すること
# ---------------------------------------------------------------------------

@test "wakeup-loop-capture[ac4c]: SESSION_SCRIPTS パス解決パターンが literal で存在する" {
  local target="$REPO_ROOT/commands/autopilot-pilot-wakeup-loop.md"

  [[ -f "$target" ]]

  local count
  count=$(grep -Fn 'SESSION_SCRIPTS="${CLAUDE_PLUGIN_ROOT}/../session/scripts"' "$target" | wc -l)
  [ "$count" -ge 1 ]
}

# ===========================================================================
# Requirement: Finding 1 regression guard（AC-3/4d）
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: HOTFIX #732 コメントが 2 箇所存在する（AC-3/4d）
# WHEN grep -Fc 'HOTFIX #732' autopilot-pilot-wakeup-loop.md を実行する
# THEN 2 であること（HTML コメントと blockquote の 2 箇所）
# ---------------------------------------------------------------------------

@test "wakeup-loop-capture[ac4d]: HOTFIX #732 コメントが 2 箇所存在する" {
  local target="$REPO_ROOT/commands/autopilot-pilot-wakeup-loop.md"

  [[ -f "$target" ]]

  local count
  count=$(grep -Fc 'HOTFIX #732' "$target")
  [ "$count" -eq 2 ]
}

# ===========================================================================
# Requirement: resolve_target バリデーション言及（AC-4e）
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: resolve_target またはバリデーションの語が存在する（AC-4e）
# WHEN Step C 説明文を grep する
# THEN 「resolve_target」または「バリデーション」が 1 件以上存在すること
# ---------------------------------------------------------------------------

@test "wakeup-loop-capture[ac4e]: resolve_target またはバリデーションの語が 1 件以上存在する" {
  local target="$REPO_ROOT/commands/autopilot-pilot-wakeup-loop.md"

  [[ -f "$target" ]]

  local count
  count=$(grep -Ec 'resolve_target|バリデーション' "$target")
  [ "$count" -ge 1 ]
}

# ===========================================================================
# Requirement: multi-worker 独立評価（AC-4f）
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: 各 worker 独立評価の言及が存在する（AC-4f）
# WHEN Step C 説明文を grep する
# THEN 「独立」または「各 worker」が 1 件以上存在すること
# ---------------------------------------------------------------------------

@test "wakeup-loop-capture[ac4f]: 独立または各 worker の語が 1 件以上存在する" {
  local target="$REPO_ROOT/commands/autopilot-pilot-wakeup-loop.md"

  [[ -f "$target" ]]

  local count
  count=$(grep -Ec '独立|各 worker' "$target")
  [ "$count" -ge 1 ]
}

# ===========================================================================
# Requirement: ANSI-stripped 出力での input-waiting regex 検知（AC-7）
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: ANSI エスケープを含む出力を strip 後も input-waiting regex が検知される（AC-7）
# WHEN ANSI エスケープシーケンスを含む input-waiting パターンを fixture として用意し strip する
# THEN 各 input-waiting パターンが ANSI strip 後も grep で検知されること
# ---------------------------------------------------------------------------

@test "wakeup-loop-capture[ac7]: ANSI strip 後も 'Enter to select' が検知される" {
  local stripped
  # ANSI escape code \e[32m...\e[0m を付加した fixture
  stripped=$(printf '\e[32mEnter to select\e[0m' | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g; s/\x1b\][^\x07]*\x07//g; s/\x1b(B//g')
  echo "$stripped" | grep -qE 'Enter to select'
}

@test "wakeup-loop-capture[ac7]: ANSI strip 後も 'よろしいですか' が検知される" {
  local stripped
  stripped=$(printf '\e[1mよろしいですか？\e[0m' | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g; s/\x1b\][^\x07]*\x07//g; s/\x1b(B//g')
  echo "$stripped" | grep -qE 'よろしいですか[？?]'
}

@test "wakeup-loop-capture[ac7]: ANSI strip 後も '❯ <数字>.' が検知される（unicode 絵文字保持）" {
  local stripped
  # ANSI カラーコードを付加しても unicode 絵文字 ❯ は保持される
  stripped=$(printf '\e[36m❯ 1. option\e[0m' | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g; s/\x1b\][^\x07]*\x07//g; s/\x1b(B//g')
  echo "$stripped" | grep -qP '❯ \d+\.'
}

@test "wakeup-loop-capture[ac7]: ANSI strip 後も '[y/N]' が検知される" {
  local stripped
  stripped=$(printf 'Continue? \e[33m[y/N]\e[0m' | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g; s/\x1b\][^\x07]*\x07//g; s/\x1b(B//g')
  echo "$stripped" | grep -qE '\[y/N\]'
}
