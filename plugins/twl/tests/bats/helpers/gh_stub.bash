#!/usr/bin/env bash
# gh_stub.bash - shared gh CLI / git / doobidoo MCP stubs for autopilot-pilot-* bats tests

# setup_gh_stubs: Create default gh stubs for precheck/rebase/verdict tests
# Call after common_setup
setup_gh_stubs() {
  # Default: gh pr diff --stat returns minimal output
  stub_command "gh" '
case "$*" in
  *"pr diff"*"--stat"*)
    echo " file1.ts | 10 ++++"
    echo " file2.ts | 5 ++--"
    echo " 2 files changed, 12 insertions(+), 3 deletions(-)"
    ;;
  *"pr view"*"--json"*)
    echo "{\"title\":\"test PR\",\"body\":\"test body\",\"additions\":12,\"deletions\":3}"
    ;;
  *"issue view"*"--json body"*)
    echo "{\"body\":\"## AC\\n- [ ] テストを追加\"}"
    ;;
  *"issue view"*"--json comments"*)
    echo "{\"comments\":[{\"body\":\"done\"}]}"
    ;;
  *"issue view"*"--json title,body,comments"*)
    echo "{\"title\":\"test issue\",\"body\":\"test body\",\"comments\":[]}"
    ;;
  *"issue view"*"--json state"*)
    echo "{\"state\":\"CLOSED\"}"
    ;;
  *"issue close"*)
    echo "closed"
    ;;
  *)
    echo "gh stub: unmatched args: $*" >&2
    exit 0
    ;;
esac
'
}

# setup_gh_high_deletion: gh stubs simulating high deletion PR
setup_gh_high_deletion() {
  stub_command "gh" '
case "$*" in
  *"pr diff"*"--stat"*)
    echo " src/old-module.ts | 200 ----"
    echo " src/another.ts   | 50 ----"
    echo " src/third.ts     | 30 ----"
    echo " src/fourth.ts    | 20 ----"
    echo " src/fifth.ts     | 10 ----"
    echo " src/sixth.ts     | 5 ----"
    echo " 6 files changed, 0 insertions(+), 315 deletions(-)"
    ;;
  *"issue view"*"--json body"*)
    echo "{\"body\":\"## AC\\n- [ ] テストを追加\"}"
    ;;
  *"issue view"*"--json comments"*)
    echo "{\"comments\":[{\"body\":\"done\"}]}"
    ;;
  *)
    exit 0
    ;;
esac
'
}

# setup_gh_ac_fail: gh stubs simulating AC spot-check failure
setup_gh_ac_fail() {
  stub_command "gh" '
case "$*" in
  *"pr diff"*"--stat"*)
    echo " file.ts | 5 ++"
    echo " 1 file changed, 5 insertions(+), 0 deletions(-)"
    ;;
  *"issue view"*"--json body"*)
    echo "{\"body\":\"## AC\\n- [ ] Issue にコメントを追加\"}"
    ;;
  *"issue view"*"--json comments"*)
    echo "{\"comments\":[]}"
    ;;
  *)
    exit 0
    ;;
esac
'
}

# setup_git_rebase_clean: git stubs for clean rebase scenario
setup_git_rebase_clean() {
  stub_command "git" '
case "$*" in
  *"fetch origin main"*)
    echo "Already up to date."
    ;;
  *"rebase origin/main"*)
    echo "Successfully rebased"
    exit 0
    ;;
  *"push --force-with-lease"*)
    echo "pushed"
    exit 0
    ;;
  *"diff --name-only --diff-filter=U"*)
    # No conflicts
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
'
}

# setup_git_rebase_conflict_small: git stubs for 1 conflict scenario
setup_git_rebase_conflict_small() {
  stub_command "git" '
case "$*" in
  *"fetch origin main"*)
    echo "Already up to date."
    ;;
  *"rebase origin/main"*)
    echo "CONFLICT (content): Merge conflict in file.ts" >&2
    exit 1
    ;;
  *"diff --name-only --diff-filter=U"*)
    echo "file.ts"
    ;;
  *"rebase --continue"*)
    echo "Successfully rebased"
    exit 0
    ;;
  *"push --force-with-lease"*)
    echo "pushed"
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
'
}

# setup_git_rebase_conflict_large: git stubs for 4+ conflict scenario
setup_git_rebase_conflict_large() {
  stub_command "git" '
case "$*" in
  *"fetch origin main"*)
    echo "Already up to date."
    ;;
  *"rebase origin/main"*)
    echo "CONFLICT (content): multiple conflicts" >&2
    exit 1
    ;;
  *"diff --name-only --diff-filter=U"*)
    echo "file1.ts"
    echo "file2.ts"
    echo "file3.ts"
    echo "file4.ts"
    ;;
  *"rebase --abort"*)
    echo "aborted"
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
'
}
