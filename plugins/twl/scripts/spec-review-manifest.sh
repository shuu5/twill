#!/usr/bin/env bash
# spec-review-manifest.sh - issue-spec-review の必須 specialist リスト出力
#
# issue-spec-review.md が読み取り、Agent tool に渡す。
# specialist の追加・削除はこのファイルの編集のみで反映される。
# LLM が「どの specialist を呼ぶか」を判断する余地をなくす。

cat << 'EOF'
twl:twl:issue-critic
twl:twl:issue-feasibility
twl:twl:worker-codex-reviewer
EOF
