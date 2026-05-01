#!/usr/bin/env bash
# mock-cld-observe-any.sh
# C1 用 mock daemon fixture (AC5.2)
#
# 使用方法:
#   このスクリプトをバックグラウンドで起動すると、pgrep -f 'cld-observe-any' が
#   確実にマッチするプロセスを生成する。
#
# プロセス引数名: cld-observe-any
# (argv[0] が "bash" になるため、bash -c 実行では arg 文字列を argv に含めて pgrep -f でマッチ)
#
# 起動例:
#   bash -c 'exec -a cld-observe-any-mock bash /path/to/mock-cld-observe-any.sh' &
#   MOCK_PID=$!

set -euo pipefail

# プロセス名に cld-observe-any を含む形で sleep し、pgrep -f がマッチできるようにする
# exec -a でプロセス名を上書きしない環境向けに、スクリプト本体の引数文字列で対応
SCRIPT_NAME="cld-observe-any-mock"

echo "[${SCRIPT_NAME}] mock daemon started (PID=$$)" >&2

# pgrep -f 'cld-observe-any' がマッチするために alive を維持する
# exec を使うとプロセス名が sleep に置き換わり、cld-observe-any がパスから消えるため使わない
# このスクリプト自体を `bash .../mock-cld-observe-any.sh` で起動すれば
# cmdline に cld-observe-any が含まれ pgrep -f でマッチする
while true; do sleep 1; done
