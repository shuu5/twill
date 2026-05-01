#!/usr/bin/env bats
# worker-codex-reviewer-model-resolution.bats
#
# Issue #1202: tech-debt(worker) codex reviewer OpenAI model update — TDD RED scaffold
#
# AC1:  worker-codex-reviewer.md の gpt-5.1-codex を gpt-5.3-codex に 2 箇所変更
# AC2:  TWILL_CODEX_REVIEW_MODEL env override は維持
# AC3:  probe stdout の `model: <name>` 行を grep で抽出
# AC4:  抽出結果が PROBE_MODEL と不一致なら CODEX_OK=0 (silent fallback)
# AC5:  不一致時は warning ログを出力
# AC6:  retired/deprecated model ID (gpt-4*, gpt-3*, ^o3-, ^o4-) 検出で CODEX_OK=0
# AC7:  gpt-5.1-codex は blocklist に含めない
# AC8:  blocklist はコメントで根拠 (公式 doc URL + 失効確認日) を明記
# AC9:  このテストファイル自体が新設される (このファイルの存在 = AC9 達成)
# AC10: scripts/codex-probe-check.sh としてロジックを切り出す
# AC11: silent fallback シナリオ (requested gpt-5.3-codex / resolved gpt-4o → CODEX_OK=0)
# AC12: blocklist シナリオ (gpt-4.1 / o3-mini 等)
# AC13: empty RESOLVED_MODEL シナリオ (probe 出力に model: 行なし → CODEX_OK=0)
# AC14: non-regression (model 一致 + retired ID 不出現 → CODEX_OK=1)
# AC15: worker-codex-reviewer.md コメント更新 (gpt-5.3-codex 採用理由 + doc URL + 日付) — プロセス AC
# AC16: doobidoo memory 記録 — プロセス AC
#
# RED フェーズ: scripts/codex-probe-check.sh が存在しないため全テストは FAIL する

load '../helpers/common'

PROBE_CHECK_SCRIPT=""
WORKER_AGENT=""

setup() {
  common_setup
  PROBE_CHECK_SCRIPT="$REPO_ROOT/scripts/codex-probe-check.sh"
  WORKER_AGENT="$REPO_ROOT/agents/worker-codex-reviewer.md"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# AC1: worker-codex-reviewer.md の gpt-5.1-codex を gpt-5.3-codex に 2 箇所変更
# ---------------------------------------------------------------------------

@test "ac1: worker-codex-reviewer.md に gpt-5.1-codex が残っていない" {
  # RED: 変更未実装のため fail する
  [[ -f "$WORKER_AGENT" ]] || {
    echo "FAIL: AC #1 前提 — $WORKER_AGENT が存在しない" >&2
    return 1
  }
  if grep -qF 'gpt-5.1-codex' "$WORKER_AGENT"; then
    echo "FAIL: AC #1 未実装 — worker-codex-reviewer.md に gpt-5.1-codex が残っている" >&2
    grep -n 'gpt-5.1-codex' "$WORKER_AGENT" >&2
    return 1
  fi
}

@test "ac1: worker-codex-reviewer.md に gpt-5.3-codex がデフォルト値として 2 箇所以上含まれる" {
  # RED: 変更未実装のため fail する
  [[ -f "$WORKER_AGENT" ]] || {
    echo "FAIL: AC #1 前提 — $WORKER_AGENT が存在しない" >&2
    return 1
  }
  local count
  count=$(grep -cF 'gpt-5.3-codex' "$WORKER_AGENT" || true)
  [[ "$count" -ge 2 ]] || {
    echo "FAIL: AC #1 未実装 — gpt-5.3-codex の出現が ${count} 箇所 (期待: 2 以上)" >&2
    return 1
  }
}

@test "ac1: PROBE_MODEL ラインに gpt-5.3-codex が設定されている" {
  # RED: 変更未実装のため fail する
  [[ -f "$WORKER_AGENT" ]] || {
    echo "FAIL: AC #1 前提 — $WORKER_AGENT が存在しない" >&2
    return 1
  }
  grep -qE 'PROBE_MODEL.*gpt-5\.3-codex' "$WORKER_AGENT" || {
    echo "FAIL: AC #1 未実装 — PROBE_MODEL ラインに gpt-5.3-codex が設定されていない" >&2
    return 1
  }
}

@test "ac1: codex exec ラインに gpt-5.3-codex が設定されている" {
  # RED: 変更未実装のため fail する
  [[ -f "$WORKER_AGENT" ]] || {
    echo "FAIL: AC #1 前提 — $WORKER_AGENT が存在しない" >&2
    return 1
  }
  grep -qE 'codex exec.*gpt-5\.3-codex' "$WORKER_AGENT" || {
    echo "FAIL: AC #1 未実装 — codex exec ラインに gpt-5.3-codex が設定されていない" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# AC2: TWILL_CODEX_REVIEW_MODEL env override は維持
# ---------------------------------------------------------------------------

@test "ac2: worker-codex-reviewer.md に TWILL_CODEX_REVIEW_MODEL env override 構文が残っている" {
  # non-regression: AC #1 変更後も env override 構文が維持されていることを確認
  # (AC #1 実装前は gpt-5.1-codex のまま pass するが、AC #1 実装後に regression を防ぐテスト)
  [[ -f "$WORKER_AGENT" ]] || {
    echo "FAIL: AC #2 前提 — $WORKER_AGENT が存在しない" >&2
    return 1
  }
  grep -qE '\$\{TWILL_CODEX_REVIEW_MODEL:-' "$WORKER_AGENT" || {
    echo "FAIL: AC #2 未実装 — TWILL_CODEX_REVIEW_MODEL env override 構文が除去されている" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# AC3: probe stdout の `model: <name>` 行を grep で抽出
# AC4: 抽出結果が PROBE_MODEL と不一致なら CODEX_OK=0
# AC5: 不一致時は warning ログを出力
# (AC3-5 は codex-probe-check.sh の run_probe_check 関数として検証)
# ---------------------------------------------------------------------------

@test "ac10: scripts/codex-probe-check.sh が存在する" {
  # RED: 新規作成未実装のため fail する
  [[ -f "$PROBE_CHECK_SCRIPT" ]] || {
    echo "FAIL: AC #10 未実装 — $PROBE_CHECK_SCRIPT が存在しない" >&2
    return 1
  }
}

@test "ac10: scripts/codex-probe-check.sh が実行可能である" {
  # RED: 新規作成未実装のため fail する
  [[ -f "$PROBE_CHECK_SCRIPT" ]] || {
    echo "FAIL: AC #10 未実装 — $PROBE_CHECK_SCRIPT が存在しない" >&2
    return 1
  }
  [[ -x "$PROBE_CHECK_SCRIPT" ]] || {
    echo "FAIL: AC #10 未実装 — $PROBE_CHECK_SCRIPT が実行可能でない" >&2
    return 1
  }
}

@test "ac10: scripts/codex-probe-check.sh に source guard が含まれる" {
  # RED: 新規作成未実装のため fail する
  # baseline-bash.md §10: source-only load mode のための guard が必要
  [[ -f "$PROBE_CHECK_SCRIPT" ]] || {
    echo "FAIL: AC #10 未実装 — $PROBE_CHECK_SCRIPT が存在しない" >&2
    return 1
  }
  grep -qE '\[\[ "\$\{BASH_SOURCE\[0\]\}" == "\$\{0\}" \]\]|--source-only|_DAEMON_LOAD_ONLY' \
    "$PROBE_CHECK_SCRIPT" || {
    echo "FAIL: AC #10 未実装 — source guard が存在しない (baseline-bash.md §10 参照)" >&2
    return 1
  }
}

@test "ac3: codex-probe-check.sh は PROBE_OUT から model: 行を grep で抽出する" {
  # RED: codex-probe-check.sh が存在しないため fail する
  [[ -f "$PROBE_CHECK_SCRIPT" ]] || {
    echo "FAIL: AC #3/#10 未実装 — $PROBE_CHECK_SCRIPT が存在しない" >&2
    return 1
  }
  # grep -E "^model:" | head -1 | awk '{print $2}' の実装確認
  grep -qE 'grep.*\^model:|grep.*"model:"' "$PROBE_CHECK_SCRIPT" || {
    echo "FAIL: AC #3 未実装 — codex-probe-check.sh に ^model: 抽出の grep が存在しない" >&2
    return 1
  }
}

@test "ac3: resolved_model 変数が probe 出力から抽出される" {
  # codex-probe-check.sh の実装変数名は resolved_model（小文字）
  [[ -f "$PROBE_CHECK_SCRIPT" ]] || {
    echo "FAIL: AC #3/#10 未実装 — $PROBE_CHECK_SCRIPT が存在しない" >&2
    return 1
  }
  grep -qE 'resolved_model' "$PROBE_CHECK_SCRIPT" || {
    echo "FAIL: AC #3 未実装 — resolved_model 変数が定義されていない" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# AC11: silent fallback シナリオ
#       mock probe 出力: requested=gpt-5.3-codex, resolved=gpt-4o → CODEX_OK=0
# ---------------------------------------------------------------------------

@test "ac11: silent fallback — resolved が gpt-4o の場合 CODEX_OK=0 になる" {
  # RED: codex-probe-check.sh が存在しないため fail する
  [[ -f "$PROBE_CHECK_SCRIPT" ]] || {
    echo "FAIL: AC #11/#10 未実装 — $PROBE_CHECK_SCRIPT が存在しない" >&2
    return 1
  }

  # mock PROBE_OUT: probe が gpt-4o を返す (gpt-5.3-codex を要求したが gpt-4o に fallback)
  local mock_probe_out="model: gpt-4o
version: 1.0
status: ok"

  # codex-probe-check.sh を source して run_probe_check を呼び出す
  run bash -c "
    source '$PROBE_CHECK_SCRIPT'
    PROBE_MODEL='gpt-5.3-codex'
    PROBE_OUT='$mock_probe_out'
    CODEX_OK=1
    run_probe_check
    echo \"CODEX_OK=\$CODEX_OK\"
  "
  echo "$output" | grep -q "CODEX_OK=0" || {
    echo "FAIL: AC #11 未実装 — model mismatch (requested gpt-5.3-codex, resolved gpt-4o) で CODEX_OK が 0 にならない" >&2
    echo "  output: $output" >&2
    return 1
  }
}

@test "ac11: silent fallback — WARN ログが出力される (requested/resolved を含む)" {
  # RED: codex-probe-check.sh が存在しないため fail する
  [[ -f "$PROBE_CHECK_SCRIPT" ]] || {
    echo "FAIL: AC #11/#10 未実装 — $PROBE_CHECK_SCRIPT が存在しない" >&2
    return 1
  }

  local mock_probe_out="model: gpt-4o
version: 1.0
status: ok"

  # AC5: warning ログに requested=$PROBE_MODEL, resolved=$RESOLVED_MODEL が含まれること
  run bash -c "
    source '$PROBE_CHECK_SCRIPT'
    PROBE_MODEL='gpt-5.3-codex'
    PROBE_OUT='$mock_probe_out'
    CODEX_OK=1
    run_probe_check 2>&1
  "
  echo "$output" | grep -qE "WARN.*model resolution mismatch|model resolution mismatch.*WARN" || {
    echo "FAIL: AC #5/#11 未実装 — warning ログが出力されていない" >&2
    echo "  output: $output" >&2
    return 1
  }
  echo "$output" | grep -qE "requested=gpt-5\.3-codex" || {
    echo "FAIL: AC #5/#11 未実装 — warning ログに requested=gpt-5.3-codex が含まれない" >&2
    echo "  output: $output" >&2
    return 1
  }
  echo "$output" | grep -qE "resolved=gpt-4o" || {
    echo "FAIL: AC #5/#11 未実装 — warning ログに resolved=gpt-4o が含まれない" >&2
    echo "  output: $output" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# AC12: blocklist シナリオ
#       probe 出力に gpt-4.1 / o3-mini 等が含まれる場合 CODEX_OK=0
# ---------------------------------------------------------------------------

@test "ac12: blocklist — probe 出力に gpt-4.1 が含まれる場合 CODEX_OK=0 になる" {
  # RED: codex-probe-check.sh が存在しないため fail する
  [[ -f "$PROBE_CHECK_SCRIPT" ]] || {
    echo "FAIL: AC #12/#10 未実装 — $PROBE_CHECK_SCRIPT が存在しない" >&2
    return 1
  }

  local mock_probe_out="model: gpt-4.1
version: 1.0
status: ok"

  run bash -c "
    source '$PROBE_CHECK_SCRIPT'
    PROBE_MODEL='gpt-5.3-codex'
    PROBE_OUT='$mock_probe_out'
    CODEX_OK=1
    run_probe_check
    echo \"CODEX_OK=\$CODEX_OK\"
  "
  echo "$output" | grep -q "CODEX_OK=0" || {
    echo "FAIL: AC #12 未実装 — probe 出力に gpt-4.1 が含まれるが CODEX_OK=0 にならない" >&2
    echo "  output: $output" >&2
    return 1
  }
}

@test "ac12: blocklist — probe 出力に o3-mini が含まれる場合 CODEX_OK=0 になる" {
  # RED: codex-probe-check.sh が存在しないため fail する
  [[ -f "$PROBE_CHECK_SCRIPT" ]] || {
    echo "FAIL: AC #12/#10 未実装 — $PROBE_CHECK_SCRIPT が存在しない" >&2
    return 1
  }

  local mock_probe_out="model: o3-mini
version: 1.0
status: ok"

  run bash -c "
    source '$PROBE_CHECK_SCRIPT'
    PROBE_MODEL='gpt-5.3-codex'
    PROBE_OUT='$mock_probe_out'
    CODEX_OK=1
    run_probe_check
    echo \"CODEX_OK=\$CODEX_OK\"
  "
  echo "$output" | grep -q "CODEX_OK=0" || {
    echo "FAIL: AC #12 未実装 — probe 出力に o3-mini が含まれるが CODEX_OK=0 にならない" >&2
    echo "  output: $output" >&2
    return 1
  }
}

@test "ac12: blocklist — probe 出力に gpt-4o が含まれる場合 CODEX_OK=0 になる (gpt-4* pattern)" {
  # RED: codex-probe-check.sh が存在しないため fail する
  [[ -f "$PROBE_CHECK_SCRIPT" ]] || {
    echo "FAIL: AC #12/#10 未実装 — $PROBE_CHECK_SCRIPT が存在しない" >&2
    return 1
  }

  local mock_probe_out="response model: gpt-4o
status: ok"

  run bash -c "
    source '$PROBE_CHECK_SCRIPT'
    PROBE_MODEL='gpt-5.3-codex'
    PROBE_OUT='$mock_probe_out'
    CODEX_OK=1
    run_probe_check
    echo \"CODEX_OK=\$CODEX_OK\"
  "
  echo "$output" | grep -q "CODEX_OK=0" || {
    echo "FAIL: AC #12 未実装 — probe 出力に gpt-4o (gpt-4* pattern) が含まれるが CODEX_OK=0 にならない" >&2
    echo "  output: $output" >&2
    return 1
  }
}

@test "ac7: blocklist — gpt-5.1-codex が blocklist に含まれない (env override 利用時に誤発火しない)" {
  # RED: codex-probe-check.sh が存在しないため fail する
  [[ -f "$PROBE_CHECK_SCRIPT" ]] || {
    echo "FAIL: AC #7/#10 未実装 — $PROBE_CHECK_SCRIPT が存在しない" >&2
    return 1
  }

  # TWILL_CODEX_REVIEW_MODEL=gpt-5.1-codex で override した場合、
  # probe が gpt-5.1-codex を返せば blocklist は発火しない (CODEX_OK=1 を維持)
  local mock_probe_out="model: gpt-5.1-codex
version: 1.0
status: ok"

  run bash -c "
    source '$PROBE_CHECK_SCRIPT'
    PROBE_MODEL='gpt-5.1-codex'
    PROBE_OUT='$mock_probe_out'
    CODEX_OK=1
    run_probe_check
    echo \"CODEX_OK=\$CODEX_OK\"
  "
  echo "$output" | grep -q "CODEX_OK=1" || {
    echo "FAIL: AC #7 未実装 — gpt-5.1-codex が blocklist に含まれ CODEX_OK=0 になっている (誤発火)" >&2
    echo "  output: $output" >&2
    return 1
  }
}

@test "ac8: codex-probe-check.sh の blocklist に根拠コメント (URL + 失効確認日) が含まれる" {
  # RED: codex-probe-check.sh が存在しないため fail する
  [[ -f "$PROBE_CHECK_SCRIPT" ]] || {
    echo "FAIL: AC #8/#10 未実装 — $PROBE_CHECK_SCRIPT が存在しない" >&2
    return 1
  }
  # blocklist 周辺に URL と日付のコメントが存在することを確認
  grep -qE 'https?://|platform\.openai\.com|openai\.com' "$PROBE_CHECK_SCRIPT" || {
    echo "FAIL: AC #8 未実装 — blocklist 根拠 URL が存在しない" >&2
    return 1
  }
  grep -qE '20[0-9]{2}-[0-9]{2}-[0-9]{2}' "$PROBE_CHECK_SCRIPT" || {
    echo "FAIL: AC #8 未実装 — blocklist 失効確認日 (YYYY-MM-DD) が存在しない" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# AC13: empty RESOLVED_MODEL シナリオ
#       probe 出力に model: 行が存在しない場合 CODEX_OK=0
# ---------------------------------------------------------------------------

@test "ac13: empty RESOLVED_MODEL — probe 出力に model: 行なし → CODEX_OK=0" {
  # RED: codex-probe-check.sh が存在しないため fail する
  [[ -f "$PROBE_CHECK_SCRIPT" ]] || {
    echo "FAIL: AC #13/#10 未実装 — $PROBE_CHECK_SCRIPT が存在しない" >&2
    return 1
  }

  # probe 出力に model: 行が存在しない
  local mock_probe_out="version: 1.0
status: ok
output: some result"

  run bash -c "
    source '$PROBE_CHECK_SCRIPT'
    PROBE_MODEL='gpt-5.3-codex'
    PROBE_OUT='$mock_probe_out'
    CODEX_OK=1
    run_probe_check
    echo \"CODEX_OK=\$CODEX_OK\"
  "
  echo "$output" | grep -q "CODEX_OK=0" || {
    echo "FAIL: AC #13 未実装 — probe 出力に model: 行がないが CODEX_OK=0 にならない (model 取得失敗 = fallback)" >&2
    echo "  output: $output" >&2
    return 1
  }
}

@test "ac13: empty RESOLVED_MODEL — WARN ログに resolved=<empty> が含まれる" {
  # RED: codex-probe-check.sh が存在しないため fail する
  [[ -f "$PROBE_CHECK_SCRIPT" ]] || {
    echo "FAIL: AC #13/#10 未実装 — $PROBE_CHECK_SCRIPT が存在しない" >&2
    return 1
  }

  local mock_probe_out="version: 1.0
status: ok"

  run bash -c "
    source '$PROBE_CHECK_SCRIPT'
    PROBE_MODEL='gpt-5.3-codex'
    PROBE_OUT='$mock_probe_out'
    CODEX_OK=1
    run_probe_check 2>&1
  "
  # AC5: 空文字列の場合は resolved=<empty> で出力
  echo "$output" | grep -qE "resolved=<empty>|resolved=$" || {
    echo "FAIL: AC #5/#13 未実装 — WARN ログに resolved=<empty> が含まれない" >&2
    echo "  output: $output" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# AC14: non-regression — 正常応答で CODEX_OK=1 を維持
# ---------------------------------------------------------------------------

@test "ac14: non-regression — model 一致 + retired ID 不出現 → CODEX_OK=1 を維持" {
  # RED: codex-probe-check.sh が存在しないため fail する
  [[ -f "$PROBE_CHECK_SCRIPT" ]] || {
    echo "FAIL: AC #14/#10 未実装 — $PROBE_CHECK_SCRIPT が存在しない" >&2
    return 1
  }

  # 正常応答: requested と resolved が一致し、retired model ID も含まれない
  local mock_probe_out="model: gpt-5.3-codex
version: 1.0
status: ok
output: review result here"

  run bash -c "
    source '$PROBE_CHECK_SCRIPT'
    PROBE_MODEL='gpt-5.3-codex'
    PROBE_OUT='$mock_probe_out'
    CODEX_OK=1
    run_probe_check
    echo \"CODEX_OK=\$CODEX_OK\"
  "
  echo "$output" | grep -q "CODEX_OK=1" || {
    echo "FAIL: AC #14 未実装 — 正常応答 (model 一致、retired ID なし) で CODEX_OK=1 が維持されない" >&2
    echo "  output: $output" >&2
    return 1
  }
}

@test "ac14: non-regression — CODEX_OK=1 の場合 WARN ログが出力されない" {
  # RED: codex-probe-check.sh が存在しないため fail する
  [[ -f "$PROBE_CHECK_SCRIPT" ]] || {
    echo "FAIL: AC #14/#10 未実装 — $PROBE_CHECK_SCRIPT が存在しない" >&2
    return 1
  }

  local mock_probe_out="model: gpt-5.3-codex
version: 1.0
status: ok"

  run bash -c "
    source '$PROBE_CHECK_SCRIPT'
    PROBE_MODEL='gpt-5.3-codex'
    PROBE_OUT='$mock_probe_out'
    CODEX_OK=1
    run_probe_check 2>&1
  "
  echo "$output" | grep -qE "^WARN:" && {
    echo "FAIL: AC #14 未実装 — 正常応答なのに WARN ログが出力されている" >&2
    echo "  output: $output" >&2
    return 1
  }
  return 0
}

# ---------------------------------------------------------------------------
# AC15: worker-codex-reviewer.md コメント更新 (gpt-5.3-codex 採用理由 + doc URL + 日付)
# (プロセス AC — ファイル内コメントの存在確認)
# ---------------------------------------------------------------------------

@test "ac15: worker-codex-reviewer.md に gpt-5.3-codex 採用理由コメントが含まれる" {
  # RED: コメント更新未実装のため fail する
  [[ -f "$WORKER_AGENT" ]] || {
    echo "FAIL: AC #15 前提 — $WORKER_AGENT が存在しない" >&2
    return 1
  }
  grep -qE 'https?://|platform\.openai\.com|openai\.com' "$WORKER_AGENT" || {
    echo "FAIL: AC #15 未実装 — worker-codex-reviewer.md に公式 doc URL が存在しない" >&2
    return 1
  }
}

@test "ac15: worker-codex-reviewer.md に失効確認日 2026-05-01 が含まれる" {
  # RED: コメント更新未実装のため fail する
  [[ -f "$WORKER_AGENT" ]] || {
    echo "FAIL: AC #15 前提 — $WORKER_AGENT が存在しない" >&2
    return 1
  }
  grep -q '2026-05-01' "$WORKER_AGENT" || {
    echo "FAIL: AC #15 未実装 — worker-codex-reviewer.md に失効確認日 2026-05-01 が存在しない" >&2
    return 1
  }
}
