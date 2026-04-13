#!/usr/bin/env bash
# spec-review-manifest.sh - issue-spec-review の必須 specialist リスト出力
#
# issue-spec-review.md が読み取り、Agent tool に渡す。
# specialist の追加・削除はこのファイルの編集のみで反映される。
# LLM が「どの specialist を呼ぶか」を判断する余地をなくす。

# 常時必須
echo "twl:twl:issue-critic"
echo "twl:twl:issue-feasibility"

# codex 環境チェック（auth.json ベース）
# codex login status は auth.json/keyring を確認する。
# 各環境で事前に `codex login --with-api-key` を実行しておくこと。
if command -v codex &>/dev/null && codex login status 2>&1 | grep -qi "logged in"; then
  echo "twl:twl:worker-codex-reviewer"
fi
