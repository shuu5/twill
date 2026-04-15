#!/usr/bin/env bash
# spec-review-manifest.sh - issue-spec-review の必須 specialist リスト出力
#
# issue-spec-review.md が読み取り、Agent tool に渡す。
# specialist の追加・削除はこのファイルの編集のみで反映される。
# LLM が「どの specialist を呼ぶか」を判断する余地をなくす。

# 常時必須（環境に依存しない — #697）
# worker-codex-reviewer は codex 不在時に graceful skip（status: PASS, findings: []）する
echo "twl:twl:issue-critic"
echo "twl:twl:issue-feasibility"
echo "twl:twl:worker-codex-reviewer"
