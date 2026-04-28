#!/usr/bin/env bats
# orchestrator-phase-results.bats
# Requirement: orchestrator が PHASE_COMPLETE と同時に phase-N-results.json を atomic 書き込み（issue-1028）
# Spec: issue-1028 / orchestrator が PHASE_COMPLETE signal を stdout だけでなくファイルにも書く
# Coverage: --type=unit
#
# 検証する仕様:
#   1. generate_phase_report 実行で phase-N-results.json が atomic に書き込まれる
#   2. ファイル内容に "signal":"PHASE_COMPLETE" が含まれる
#   3. stdout への出力は引き続き維持される（regression）
#   4. 既存 phase-N-results.json が >5 分前のものは自動 archive される

load '../../bats/helpers/common.bash'

setup() {
  common_setup

  ORCHESTRATOR_SH="$REPO_ROOT/scripts/autopilot-orchestrator.sh"
  export ORCHESTRATOR_SH

  # generate_phase_report を bats プロセスに source（関数定義のみ抽出して eval）
  # autopilot-orchestrator.sh は top-level に main 処理（exit を含む）があるため
  # ファイル全体を source できない。
  #
  # M6 (Quality Review follow-up): 旧版は `awk '/^fn\(\) \{/,/^\}$/'` で関数末尾を
  # 単純に `^}$` で判定していたが、関数内に行頭 `}` が出現すると誤切断する脆弱性が
  # あった。本実装では brace-counting awk で開閉を厳密に追跡し、ネスト brace に対応する。
  local fn_def
  fn_def=$(awk '
    BEGIN { capturing = 0; depth = 0 }
    /^generate_phase_report\(\) \{/ {
      capturing = 1
      depth = 1
      print
      next
    }
    capturing {
      print
      line = $0
      open_count = gsub(/\{/, "&", line)
      close_count = gsub(/\}/, "&", line)
      depth += open_count - close_count
      if (depth == 0) exit
    }
  ' "$ORCHESTRATOR_SH")
  eval "$fn_def"
}

teardown() {
  common_teardown
}

# generate_phase_report が依存する python3 -m twl.autopilot.state read を stub する
_stub_state_read() {
  local statuses="$1"  # "9001:done 9002:failed 9003:skipped" 形式

  cat > "$STUB_BIN/python3" <<EOF
#!/usr/bin/env bash
# python3 stub: --field status を返す
if [[ "\$*" == *"--field status"* ]]; then
  for issue_arg in "\$@"; do
    if [[ "\$issue_arg" =~ ^[0-9]+\$ ]]; then
      issue="\$issue_arg"
      break
    fi
  done
  case "\$issue" in
$(echo "$statuses" | tr ' ' '\n' | awk -F: '{print "    "$1") echo \""$2"\" ;;"}')
    *) echo "" ;;
  esac
elif [[ "\$*" == *"--field changed_files"* ]]; then
  echo ""
else
  exec /usr/bin/python3 "\$@"
fi
EOF
  chmod +x "$STUB_BIN/python3"
}

# ===========================================================================
# AC1: generate_phase_report 実行で phase-N-results.json が atomic に書き込まれる
# ===========================================================================

@test "phase-results[atomic-write][RED]: generate_phase_report で phase-1-results.json が作成される" {
  _stub_state_read "9001:done 9002:failed 9003:skipped"

  # 実行（jq は実体を使用）
  generate_phase_report 1 9001 9002 9003 > /dev/null

  local results_file="$AUTOPILOT_DIR/phase-1-results.json"
  [[ -f "$results_file" ]] || {
    echo "FAIL: phase-1-results.json が作成されなかった: $results_file" >&2
    return 1
  }
}

# ===========================================================================
# AC2 (content): ファイル内容に "signal":"PHASE_COMPLETE" が含まれる
# ===========================================================================

@test "phase-results[content][RED]: phase-N-results.json の内容に signal=PHASE_COMPLETE が含まれる" {
  _stub_state_read "9001:done"

  generate_phase_report 2 9001 > /dev/null

  local results_file="$AUTOPILOT_DIR/phase-2-results.json"
  [[ -f "$results_file" ]] || return 1

  grep -F '"signal": "PHASE_COMPLETE"' "$results_file" || {
    echo "FAIL: phase-2-results.json の内容に PHASE_COMPLETE signal が含まれない" >&2
    cat "$results_file" >&2
    return 1
  }
  grep -F '"phase": 2' "$results_file" || {
    echo "FAIL: phase-2-results.json に phase: 2 が含まれない" >&2
    return 1
  }
}

# ===========================================================================
# AC3 (regression): stdout への出力は引き続き維持される
# ===========================================================================

@test "phase-results[regression]: generate_phase_report の stdout 出力は維持される" {
  _stub_state_read "9001:done 9002:failed"

  local stdout_output
  stdout_output=$(generate_phase_report 3 9001 9002)

  echo "$stdout_output" | grep -F '"signal": "PHASE_COMPLETE"' || {
    echo "FAIL: stdout に PHASE_COMPLETE signal が含まれない" >&2
    echo "stdout: $stdout_output" >&2
    return 1
  }
}

# ===========================================================================
# AC4 (stale archive): 既存 phase-N-results.json が >5 分前のものは自動 archive される
# ===========================================================================

@test "phase-results[stale-archive][RED]: 5 分以上前の phase-N-results.json は自動 archive される" {
  _stub_state_read "9001:done"

  local results_file="$AUTOPILOT_DIR/phase-4-results.json"

  # 既存 stale ファイルを作成（10 分前のタイムスタンプに設定）
  echo '{"signal":"PHASE_COMPLETE","phase":4,"stale":true}' > "$results_file"
  local stale_ts
  stale_ts=$(date -d '10 minutes ago' +%Y%m%d%H%M.%S 2>/dev/null || date -v-10M +%Y%m%d%H%M.%S 2>/dev/null)
  touch -t "$stale_ts" "$results_file"

  # generate_phase_report 実行（新しい内容を書き込む前に stale を archive）
  generate_phase_report 4 9001 > /dev/null

  # 検証: archive ディレクトリに stale ファイルが移動している
  local archive_count
  archive_count=$(find "$AUTOPILOT_DIR/archive" -name "stale-phase-4-*" -type d 2>/dev/null | wc -l)
  [[ "$archive_count" -ge 1 ]] || {
    echo "FAIL: stale phase-4-results.json が archive されていない" >&2
    ls -la "$AUTOPILOT_DIR/archive" 2>/dev/null >&2 || true
    return 1
  }

  # 検証: 新しい phase-4-results.json が atomic 書き込みされている
  [[ -f "$results_file" ]] || {
    echo "FAIL: 新しい phase-4-results.json が作成されていない" >&2
    return 1
  }
  # 中身は新しい内容（stale: true は含まれない）
  if grep -q '"stale": true' "$results_file" 2>/dev/null; then
    echo "FAIL: phase-4-results.json が更新されていない（stale 内容のまま）" >&2
    return 1
  fi
}

# ===========================================================================
# AC5 (regression): 直近 5 分以内の phase-N-results.json は archive されない（上書き）
# ===========================================================================

@test "phase-results[regression]: 5 分以内の phase-N-results.json は archive されず上書きされる" {
  _stub_state_read "9001:done"

  local results_file="$AUTOPILOT_DIR/phase-5-results.json"

  # 既存 fresh ファイルを作成（現時刻、archive 不要）
  echo '{"signal":"PHASE_COMPLETE","phase":5,"old":true}' > "$results_file"

  generate_phase_report 5 9001 > /dev/null

  # 検証: archive されていない（5 分以内）
  local archive_count
  archive_count=$(find "$AUTOPILOT_DIR/archive" -name "stale-phase-5-*" -type d 2>/dev/null | wc -l)
  [[ "$archive_count" -eq 0 ]] || {
    echo "FAIL: fresh phase-5-results.json が誤って archive された" >&2
    return 1
  }

  # 検証: 新しい内容で上書きされている
  [[ -f "$results_file" ]] || return 1
  if grep -q '"old": true' "$results_file" 2>/dev/null; then
    echo "FAIL: phase-5-results.json が上書きされていない" >&2
    return 1
  fi
  grep -F '"signal": "PHASE_COMPLETE"' "$results_file" || return 1
}

# ===========================================================================
# M3 (#1028 follow-up): cross-device mv EXDEV fallback
# AUTOPILOT_DIR が cross-device symlink の場合 mv -f が EXDEV で失敗する。
# cp フォールバックが実装されていることを structural に確認する。
# ===========================================================================

@test "phase-results[M3 structural]: phase-N-results.json 書き込みに cp fallback が含まれる" {
  awk '/^generate_phase_report\(\) \{/,/^\}$/' "$ORCHESTRATOR_SH" | grep -F 'cp "$_tmp_file"' || {
    echo "FAIL: generate_phase_report() に cp fallback (EXDEV 対策) が含まれていない" >&2
    return 1
  }
}

# ===========================================================================
# M4 (#1028 follow-up): stat -c '%Y' / -f '%m' GNU/BSD fallback
# macOS (BSD stat) では -c '%Y' が利用不可。GNU/BSD 互換の fallback が
# 実装されていることを structural に確認する。
# ===========================================================================

@test "phase-results[M4 structural]: stat に GNU (-c %Y) と BSD (-f %m) の fallback chain が含まれる" {
  awk '/^generate_phase_report\(\) \{/,/^\}$/' "$ORCHESTRATOR_SH" | grep -F "stat -c '%Y'" || {
    echo "FAIL: generate_phase_report() に GNU stat (-c %Y) が含まれていない" >&2
    return 1
  }
  awk '/^generate_phase_report\(\) \{/,/^\}$/' "$ORCHESTRATOR_SH" | grep -F "stat -f '%m'" || {
    echo "FAIL: generate_phase_report() に BSD stat (-f %m) fallback が含まれていない" >&2
    return 1
  }
}

# ===========================================================================
# M3 functional: mv stub fail で cp fallback が動作することを確認
# ===========================================================================

@test "phase-results[M3 functional]: mv が失敗しても cp fallback で phase-N-results.json が作成される" {
  _stub_state_read "9001:done"

  # generate_phase_report 内の mv を fail させる stub
  # ただし archive ロジックでも mv を使用するため、fresh ファイル状態に限定
  cat > "$STUB_BIN/mv" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
  chmod +x "$STUB_BIN/mv"

  generate_phase_report 6 9001 > /dev/null

  local results_file="$AUTOPILOT_DIR/phase-6-results.json"
  [[ -f "$results_file" ]] || {
    echo "FAIL: mv 失敗時に cp fallback で phase-6-results.json が作成されなかった" >&2
    return 1
  }
  grep -F '"signal": "PHASE_COMPLETE"' "$results_file" || {
    echo "FAIL: cp fallback で書き込まれた phase-6-results.json の内容が壊れている" >&2
    return 1
  }
}

# ===========================================================================
# M6 (Quality Review follow-up): brace-counting awk による関数抽出のロバストネス
# 旧 awk (`/^fn\(\) \{/,/^\}$/`) は関数内に行頭 `}` が出現すると誤切断する
# 脆弱性があった。本テストは brace-counting awk が以下のケースで誤切断しないことを確認:
#   - 文字列内の {} (jq JSON テンプレート等)
#   - ${} 変数展開の brace
#   - 本体末尾の `}` を正しく終端として認識
# ===========================================================================

@test "phase-results[M6 robust-extraction]: brace-counting awk が文字列内 {} を含む関数を正しく抽出する" {
  local fixture="$SANDBOX/test-orch-fixture.sh"
  cat > "$fixture" <<'FIXTURE'
#!/usr/bin/env bash
# Top-level guard
echo "should NOT be captured top"

generate_phase_report() {
  local _data='{"key": "value"}'
  local _ap="${AUTOPILOT_DIR%/}"
  if [[ -n "$_data" ]]; then
    echo "${_data}"
  fi
  echo "function end marker"
}

other_function() {
  echo "should NOT be captured other"
}
FIXTURE

  local fn_def
  fn_def=$(awk '
    BEGIN { capturing = 0; depth = 0 }
    /^generate_phase_report\(\) \{/ {
      capturing = 1
      depth = 1
      print
      next
    }
    capturing {
      print
      line = $0
      open_count = gsub(/\{/, "&", line)
      close_count = gsub(/\}/, "&", line)
      depth += open_count - close_count
      if (depth == 0) exit
    }
  ' "$fixture")

  echo "$fn_def" | grep -q 'function end marker' || {
    echo "FAIL: brace-counting awk が関数本体末尾 (function end marker) まで抽出できていない" >&2
    echo "Extracted:" >&2
    echo "$fn_def" >&2
    return 1
  }
  if echo "$fn_def" | grep -q 'should NOT be captured'; then
    echo "FAIL: brace-counting awk が関数外 (other_function) を誤って含めた" >&2
    return 1
  fi
}

@test "phase-results[M6 setup-uses-brace-counting]: bats setup の関数抽出が brace-counting 版である" {
  # この bats ファイル自身に brace-counting awk が含まれることを確認
  # 旧 `awk '/^fn\(\) \{/,/^\}$/'` パターンが setup 内に残っていないことを保証
  grep -F 'gsub(/\{/' "$BATS_TEST_FILENAME" || {
    echo "FAIL: bats setup が brace-counting awk を使用していない（旧パターンが残存）" >&2
    return 1
  }
  grep -F 'open_count - close_count' "$BATS_TEST_FILENAME" || {
    echo "FAIL: bats setup の brace counting ロジックが含まれていない" >&2
    return 1
  }
}
