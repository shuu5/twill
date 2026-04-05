#!/usr/bin/env bash
# escape-issue-body.sh - HTML-escape Issue body from stdin
# Usage: echo "$body" | bash scripts/escape-issue-body.sh
# Escapes in order: & -> &amp;, < -> &lt;, > -> &gt;
set -euo pipefail

sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
