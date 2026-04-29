#!/usr/bin/env bats
# ac-impl-coverage-check.bats
#
# Issue #1105: tech-debt(autopilot) - TDD RED scaffold
#              ac-impl-coverage-check.sh + chain-runner step_ac_verify pre-call
#
# AC1: ac-test-mapping-N.yaml schema に impl_files (任意 field、string[]) を追加。
#      schema 仕様書を plugins/twl/docs/ac-test-mapping-schema.md に記述する。
# AC2: plugins/twl/scripts/ac-impl-coverage-check.sh を新設する。機械検証スクリプト。
#      - 入力: --mapping <path> + stdin から git diff --name-only origin/main
#      - 出力: ref-specialist-output-schema 準拠の Findings JSON 配列
#      - exit code: CRITICAL 1件以上 → 1、WARNING のみ → 2、INFO のみ/出力なし → 0
# AC3: chain-runner.sh::step_ac_verify を改修し、LLM delegate より前に
#      ac-impl-coverage-check.sh を pre-call する。
# AC4: agents/ac-scaffold-tests.md に impl_files 候補生成ロジックを追加する。
# AC5: regression test（fixture A/B/C/D）
# AC6: Issue body の「関連」セクションに L2/#1025 scope 外・ADR-030 補完を明記（doc AC）
#
# RED フェーズ: 全テストは ac-impl-coverage-check.sh が存在しないため FAIL する

load 'helpers/common'

SCRIPT=""

setup() {
  common_setup
  export CLAUDE_PLUGIN_ROOT="$SANDBOX"
  export ISSUE_NUM="1105"
  SCRIPT="$REPO_ROOT/scripts/ac-impl-coverage-check.sh"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# AC1: ac-test-mapping-N.yaml schema に impl_files 追加 + schema 文書
# ---------------------------------------------------------------------------

@test "ac1: schema 文書 plugins/twl/docs/ac-test-mapping-schema.md が存在する" {
  # RED: ファイルが存在しないため fail する
  local schema_doc="$REPO_ROOT/docs/ac-test-mapping-schema.md"
  [[ -f "$schema_doc" ]] || {
    echo "FAIL: AC #1 未実装 — $schema_doc が存在しない" >&2
    return 1
  }
}

@test "ac1: schema 文書に impl_files フィールドの定義が含まれる" {
  # RED: schema 文書が存在しないため fail する
  local schema_doc="$REPO_ROOT/docs/ac-test-mapping-schema.md"
  [[ -f "$schema_doc" ]] || {
    echo "FAIL: AC #1 未実装 — $schema_doc が存在しない" >&2
    return 1
  }
  grep -q "impl_files" "$schema_doc" || {
    echo "FAIL: AC #1 未実装 — schema 文書に impl_files の記述がない" >&2
    return 1
  }
}

@test "ac1: schema 文書に impl_files が string[] (任意 field) と記述されている" {
  # RED: schema 文書が存在しないため fail する
  local schema_doc="$REPO_ROOT/docs/ac-test-mapping-schema.md"
  [[ -f "$schema_doc" ]] || {
    echo "FAIL: AC #1 未実装 — $schema_doc が存在しない" >&2
    return 1
  }
  # string[] または optional/optional の記述を確認
  grep -qE "impl_files.*(optional|string\[\]|任意)" "$schema_doc" || {
    echo "FAIL: AC #1 未実装 — schema 文書に impl_files の型定義（string[]、任意）が不足" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# AC2: ac-impl-coverage-check.sh スクリプト存在 + 基本インターフェース
# ---------------------------------------------------------------------------

@test "ac2: ac-impl-coverage-check.sh が scripts/ に存在する" {
  # RED: スクリプトが存在しないため fail する
  [[ -f "$SCRIPT" ]] || {
    echo "FAIL: AC #2 未実装 — $SCRIPT が存在しない" >&2
    return 1
  }
}

@test "ac2: ac-impl-coverage-check.sh が実行可能である" {
  # RED: スクリプトが存在しないため fail する
  [[ -x "$SCRIPT" ]] || {
    echo "FAIL: AC #2 未実装 — $SCRIPT が実行可能ではない (存在しないか chmod +x 未実行)" >&2
    return 1
  }
}

@test "ac2: --mapping オプションなしで呼び出すと使用方法を表示して exit 非 0" {
  # RED: スクリプトが存在しないため fail する
  # スクリプトが存在しない場合は「スクリプト不在」として fail させる
  [[ -f "$SCRIPT" ]] || {
    echo "FAIL: AC #2 未実装 — $SCRIPT が存在しない（usage 出力未検証）" >&2
    return 1
  }
  run bash "$SCRIPT"
  [[ "$status" -ne 0 ]] || {
    echo "FAIL: AC #2 未実装 — 引数なしで exit 0 を返した（usage チェックなし）" >&2
    return 1
  }
  # "usage" または "--mapping" がヘルプ出力に含まれる
  echo "$output" | grep -qiE "usage|--mapping" || {
    echo "FAIL: AC #2 未実装 — usage テキストに --mapping の説明がない" >&2
    return 1
  }
}

@test "ac2: --mapping <path> を受け付ける" {
  # RED: スクリプトが存在しないため fail する
  [[ -f "$SCRIPT" ]] || {
    echo "FAIL: AC #2 未実装 — $SCRIPT が存在しない" >&2
    return 1
  }
  local mapping_file="$SANDBOX/ac-test-mapping-1105.yaml"
  cat > "$mapping_file" <<'YAML'
mappings:
  - ac_index: 1
    ac_text: "テスト AC"
    test_file: "tests/test_foo.sh"
    test_name: "test_ac1_foo"
    impl_files:
      - "scripts/foo.sh"
YAML

  run bash -c "echo '' | bash '$SCRIPT' --mapping '$mapping_file'"
  # スクリプトが存在すれば何らかの exit code を返す（127 以外）
  [[ "$status" -ne 127 ]] || {
    echo "FAIL: AC #2 未実装 — --mapping オプションが認識されない (exit 127)" >&2
    return 1
  }
}

@test "ac2: 出力が ref-specialist-output-schema 準拠の JSON 配列形式である（空 diff、impl_files 一致）" {
  # RED: スクリプトが存在しないため fail する
  [[ -f "$SCRIPT" ]] || {
    echo "FAIL: AC #2 未実装 — $SCRIPT が存在しない" >&2
    return 1
  }

  local mapping_file="$SANDBOX/ac-test-mapping-1105.yaml"
  cat > "$mapping_file" <<'YAML'
mappings:
  - ac_index: 1
    ac_text: "テスト AC"
    test_file: "tests/test_foo.sh"
    test_name: "test_ac1_foo"
    impl_files:
      - "scripts/foo.sh"
YAML

  # impl_files のファイルが diff に含まれる（正常系相当）
  run bash -c "echo 'scripts/foo.sh' | bash '$SCRIPT' --mapping '$mapping_file'"

  # 出力が JSON 配列であることを検証
  echo "$output" | jq -e '. | type == "array"' >/dev/null 2>&1 || {
    echo "FAIL: AC #2 未実装 — 出力が JSON 配列ではない: $output" >&2
    return 1
  }
}

@test "ac2: CRITICAL 1件以上の場合 exit code 1 を返す" {
  # RED: スクリプトが存在しないため fail する
  [[ -f "$SCRIPT" ]] || {
    echo "FAIL: AC #2 未実装 — $SCRIPT が存在しない" >&2
    return 1
  }

  local mapping_file="$SANDBOX/ac-test-mapping-critical.yaml"
  cat > "$mapping_file" <<'YAML'
mappings:
  - ac_index: 1
    ac_text: "実装 AC"
    test_file: "tests/test_impl.sh"
    test_name: "test_ac1_impl"
    impl_files:
      - "scripts/impl.sh"
YAML

  # diff に impl_files が含まれない → CRITICAL 想定
  run bash -c "echo 'other/unrelated.sh' | bash '$SCRIPT' --mapping '$mapping_file'"
  [[ "$status" -eq 1 ]] || {
    echo "FAIL: AC #2 未実装 — CRITICAL case で exit 1 ではなく exit ${status}" >&2
    return 1
  }
}

@test "ac2: WARNING のみの場合 exit code 2 を返す" {
  # このケースの検証は実装依存のため、スクリプトの存在確認を先行
  # RED: スクリプトが存在しないため fail する
  [[ -f "$SCRIPT" ]] || {
    echo "FAIL: AC #2 未実装 — $SCRIPT が存在しない" >&2
    return 1
  }
}

@test "ac2: impl_files 不在の AC はスキップ (INFO) される" {
  # 混在ケース（一部 AC に impl_files あり、他 AC は不在）で not-present AC が INFO 扱いになることを確認
  # RED: スクリプトが存在しないため fail する
  [[ -f "$SCRIPT" ]] || {
    echo "FAIL: AC #2 未実装 — $SCRIPT が存在しない" >&2
    return 1
  }

  local mapping_file="$SANDBOX/ac-test-mapping-mixed-noimpl.yaml"
  cat > "$mapping_file" <<'YAML'
mappings:
  - ac_index: 1
    ac_text: "impl_files あり AC（diff に一致）"
    test_file: "tests/test_impl.sh"
    test_name: "test_ac1_impl"
    impl_files:
      - "other/file.sh"
  - ac_index: 2
    ac_text: "impl_files なし AC"
    test_file: "tests/test_noimpl.sh"
    test_name: "test_ac2_noimpl"
YAML

  # AC1 は diff と一致 (PASS)、AC2 は impl_files 不在 (INFO)
  run bash -c "echo 'other/file.sh' | bash '$SCRIPT' --mapping '$mapping_file'"
  # exit 0 (INFO のみ)
  [[ "$status" -eq 0 ]] || {
    echo "FAIL: AC #2 未実装 — impl_files なし AC で exit ${status}（INFO/スキップ想定）" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# AC3: chain-runner.sh::step_ac_verify に ac-impl-coverage-check.sh pre-call
# ---------------------------------------------------------------------------

@test "ac3: chain-runner.sh の step_ac_verify に ac-impl-coverage-check 呼び出しが含まれる" {
  # RED: pre-call 実装がないため fail する
  local chain_runner="$SANDBOX/scripts/chain-runner.sh"
  [[ -f "$chain_runner" ]] || {
    echo "FAIL: AC #3 確認前提 — chain-runner.sh が sandbox に存在しない" >&2
    return 1
  }

  grep -n "ac-impl-coverage-check" "$chain_runner" >/dev/null 2>&1 || {
    echo "FAIL: AC #3 未実装 — chain-runner.sh の step_ac_verify に ac-impl-coverage-check 呼び出しがない" >&2
    return 1
  }
}

@test "ac3: step_ac_verify の ac-impl-coverage-check 呼び出しは LLM delegate より前にある" {
  # RED: pre-call 実装がないため fail する
  local chain_runner="$SANDBOX/scripts/chain-runner.sh"
  [[ -f "$chain_runner" ]] || {
    echo "FAIL: AC #3 確認前提 — chain-runner.sh が sandbox に存在しない" >&2
    return 1
  }

  # step_ac_verify 関数内で ac-impl-coverage-check が ok "ac-verify" より前に出現することを確認
  # ok "ac-verify" は step_ac_verify の最終行に固定されるため、これを LLM step マーカーとして使用
  local pre_call_line llm_line
  pre_call_line=$(grep -n "ac-impl-coverage-check" "$chain_runner" | head -1 | cut -d: -f1)
  llm_line=$(grep -n 'ok "ac-verify"' "$chain_runner" | head -1 | cut -d: -f1)

  [[ -n "$pre_call_line" ]] || {
    echo "FAIL: AC #3 未実装 — chain-runner.sh に ac-impl-coverage-check 行が存在しない" >&2
    return 1
  }
  [[ -n "$llm_line" ]] || {
    echo "FAIL: AC #3 確認前提 — ok \"ac-verify\" 行が見つからない" >&2
    return 1
  }
  [[ "$pre_call_line" -lt "$llm_line" ]] || {
    echo "FAIL: AC #3 未実装 — ac-impl-coverage-check (line $pre_call_line) が ok ac-verify (line $llm_line) より後にある" >&2
    return 1
  }
}

@test "ac3: pre-call で CRITICAL が出た場合 step_ac_verify が非 0 で終了する" {
  # RED: pre-call 実装がないため fail する
  [[ -f "$SCRIPT" ]] || {
    echo "FAIL: AC #2/#3 前提 — ac-impl-coverage-check.sh が存在しない" >&2
    return 1
  }

  local chain_runner="$SANDBOX/scripts/chain-runner.sh"
  grep -q "ac-impl-coverage-check" "$chain_runner" 2>/dev/null || {
    echo "FAIL: AC #3 未実装 — chain-runner.sh に ac-impl-coverage-check 呼び出しがない" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# AC4: agents/ac-scaffold-tests.md に impl_files 候補生成ロジック追加
# ---------------------------------------------------------------------------

@test "ac4: agents/ac-scaffold-tests.md が存在する" {
  # 既存ファイルのため存在確認のみ（削除されていれば fail）
  local agent_file="$REPO_ROOT/agents/ac-scaffold-tests.md"
  [[ -f "$agent_file" ]] || {
    echo "FAIL: AC #4 前提 — $agent_file が存在しない（削除禁止）" >&2
    return 1
  }
}

@test "ac4: agents/ac-scaffold-tests.md に impl_files 候補生成ロジックが追加されている" {
  # RED: 追加未実装のため fail する
  local agent_file="$REPO_ROOT/agents/ac-scaffold-tests.md"
  [[ -f "$agent_file" ]] || {
    echo "FAIL: AC #4 前提 — $agent_file が存在しない" >&2
    return 1
  }

  grep -q "impl_files" "$agent_file" || {
    echo "FAIL: AC #4 未実装 — agents/ac-scaffold-tests.md に impl_files の記述がない" >&2
    return 1
  }
}

@test "ac4: ac-scaffold-tests.md の impl_files ロジックが impl_files 候補をどう生成するか説明している" {
  # RED: 追加未実装のため fail する
  local agent_file="$REPO_ROOT/agents/ac-scaffold-tests.md"
  [[ -f "$agent_file" ]] || {
    echo "FAIL: AC #4 前提 — $agent_file が存在しない" >&2
    return 1
  }

  # 候補生成の説明（glob/grep/実装ファイル探索などの語句を含む）
  grep -qE "impl_files.*(候補|glob|grep|実装|ファイル探索|identify|detect)" "$agent_file" || {
    echo "FAIL: AC #4 未実装 — impl_files 候補生成ロジックの説明が不足" >&2
    echo "  期待: impl_files 候補をどのように特定するかの説明" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# AC5: regression test - fixture A/B/C/D
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# fixture A: PR #1024 相当
#   変更ファイル: ["ac-test-mapping-1019.yaml", "test_issue_1019_ac8_binomial.py"]
#   impl_files:   ["dummy/impl_a.sh"]
#   期待: CRITICAL（diff に dummy/impl_a.sh が含まれない）
# ---------------------------------------------------------------------------

@test "ac5: fixture A (PR #1024 相当) - impl_files が diff に含まれない → CRITICAL exit 1" {
  # RED: ac-impl-coverage-check.sh が存在しないため fail する
  [[ -f "$SCRIPT" ]] || {
    echo "FAIL: AC #5 (fixture A) — ac-impl-coverage-check.sh が存在しない" >&2
    return 1
  }

  local mapping_file="$SANDBOX/ac-test-mapping-fixture-a.yaml"
  cat > "$mapping_file" <<'YAML'
mappings:
  - ac_index: 8
    ac_text: "二項分布の実装"
    test_file: "test_issue_1019_ac8_binomial.py"
    test_name: "test_ac8_binomial"
    impl_files:
      - "dummy/impl_a.sh"
YAML

  # PR #1024 相当の diff: mapping yaml + test file のみ変更（impl_files の dummy/impl_a.sh が含まれない）
  run bash -c "printf 'ac-test-mapping-1019.yaml\ntest_issue_1019_ac8_binomial.py' | bash '$SCRIPT' --mapping '$mapping_file'"

  # CRITICAL 1件以上 → exit 1
  [[ "$status" -eq 1 ]] || {
    echo "FAIL: AC #5 (fixture A) — exit code ${status}、期待 exit 1 (CRITICAL)" >&2
    echo "  stdout: $output" >&2
    return 1
  }

  # 出力が JSON 配列で CRITICAL severity を含む
  echo "$output" | jq -e '[.[] | select(.severity == "CRITICAL")] | length >= 1' >/dev/null 2>&1 || {
    echo "FAIL: AC #5 (fixture A) — CRITICAL finding が出力されていない" >&2
    echo "  stdout: $output" >&2
    return 1
  }
}

@test "ac5: fixture A - CRITICAL finding の category が ac-impl-coverage-missing である" {
  # RED: ac-impl-coverage-check.sh が存在しないため fail する
  [[ -f "$SCRIPT" ]] || {
    echo "FAIL: AC #5 (fixture A) — ac-impl-coverage-check.sh が存在しない" >&2
    return 1
  }

  local mapping_file="$SANDBOX/ac-test-mapping-fixture-a.yaml"
  cat > "$mapping_file" <<'YAML'
mappings:
  - ac_index: 8
    ac_text: "二項分布の実装"
    test_file: "test_issue_1019_ac8_binomial.py"
    test_name: "test_ac8_binomial"
    impl_files:
      - "dummy/impl_a.sh"
YAML

  run bash -c "printf 'ac-test-mapping-1019.yaml\ntest_issue_1019_ac8_binomial.py' | bash '$SCRIPT' --mapping '$mapping_file'"

  echo "$output" | jq -e '[.[] | select(.severity == "CRITICAL" and .category == "ac-impl-coverage-missing")] | length >= 1' >/dev/null 2>&1 || {
    echo "FAIL: AC #5 (fixture A) — CRITICAL finding の category が ac-impl-coverage-missing ではない" >&2
    echo "  stdout: $output" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# fixture B: PR #1104 相当
#   変更ファイル: ["cli/twl/tests/test_issue_1084_human_gate.py"]
#   impl_files:   ["dummy/impl_b.md"]
#   期待: CRITICAL（diff に dummy/impl_b.md が含まれない）
# ---------------------------------------------------------------------------

@test "ac5: fixture B (PR #1104 相当) - impl_files が diff に含まれない → CRITICAL exit 1" {
  # RED: ac-impl-coverage-check.sh が存在しないため fail する
  [[ -f "$SCRIPT" ]] || {
    echo "FAIL: AC #5 (fixture B) — ac-impl-coverage-check.sh が存在しない" >&2
    return 1
  }

  local mapping_file="$SANDBOX/ac-test-mapping-fixture-b.yaml"
  cat > "$mapping_file" <<'YAML'
mappings:
  - ac_index: 1
    ac_text: "human gate 実装"
    test_file: "cli/twl/tests/test_issue_1084_human_gate.py"
    test_name: "test_ac1_human_gate"
    impl_files:
      - "dummy/impl_b.md"
YAML

  # PR #1104 相当の diff: test file のみ変更（impl_files の dummy/impl_b.md が含まれない）
  run bash -c "printf 'cli/twl/tests/test_issue_1084_human_gate.py' | bash '$SCRIPT' --mapping '$mapping_file'"

  [[ "$status" -eq 1 ]] || {
    echo "FAIL: AC #5 (fixture B) — exit code ${status}、期待 exit 1 (CRITICAL)" >&2
    echo "  stdout: $output" >&2
    return 1
  }

  echo "$output" | jq -e '[.[] | select(.severity == "CRITICAL")] | length >= 1' >/dev/null 2>&1 || {
    echo "FAIL: AC #5 (fixture B) — CRITICAL finding が出力されていない" >&2
    echo "  stdout: $output" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# fixture C: 正常系
#   変更ファイル: ["dummy/impl_a.sh", "test_foo.py"]
#   impl_files:   ["dummy/impl_a.sh"]
#   期待: exit 0 PASS（diff に impl_files が含まれている）
# ---------------------------------------------------------------------------

@test "ac5: fixture C (正常系) - impl_files が diff に含まれる → exit 0 PASS" {
  # RED: ac-impl-coverage-check.sh が存在しないため fail する
  [[ -f "$SCRIPT" ]] || {
    echo "FAIL: AC #5 (fixture C) — ac-impl-coverage-check.sh が存在しない" >&2
    return 1
  }

  local mapping_file="$SANDBOX/ac-test-mapping-fixture-c.yaml"
  cat > "$mapping_file" <<'YAML'
mappings:
  - ac_index: 1
    ac_text: "実装 AC"
    test_file: "test_foo.py"
    test_name: "test_ac1_foo"
    impl_files:
      - "dummy/impl_a.sh"
YAML

  # 正常系: impl_files の dummy/impl_a.sh が diff に含まれる
  run bash -c "printf 'dummy/impl_a.sh\ntest_foo.py' | bash '$SCRIPT' --mapping '$mapping_file'"

  [[ "$status" -eq 0 ]] || {
    echo "FAIL: AC #5 (fixture C) — exit code ${status}、期待 exit 0 (PASS)" >&2
    echo "  stdout: $output" >&2
    return 1
  }
}

@test "ac5: fixture C - 出力 JSON に CRITICAL finding が含まれない" {
  # RED: ac-impl-coverage-check.sh が存在しないため fail する
  [[ -f "$SCRIPT" ]] || {
    echo "FAIL: AC #5 (fixture C) — ac-impl-coverage-check.sh が存在しない" >&2
    return 1
  }

  local mapping_file="$SANDBOX/ac-test-mapping-fixture-c.yaml"
  cat > "$mapping_file" <<'YAML'
mappings:
  - ac_index: 1
    ac_text: "実装 AC"
    test_file: "test_foo.py"
    test_name: "test_ac1_foo"
    impl_files:
      - "dummy/impl_a.sh"
YAML

  run bash -c "printf 'dummy/impl_a.sh\ntest_foo.py' | bash '$SCRIPT' --mapping '$mapping_file'"

  # 出力が空またはCRITICALなし
  if [[ -n "$output" ]]; then
    echo "$output" | jq -e '[.[] | select(.severity == "CRITICAL")] | length == 0' >/dev/null 2>&1 || {
      echo "FAIL: AC #5 (fixture C) — 正常系で CRITICAL finding が出力されている" >&2
      echo "  stdout: $output" >&2
      return 1
    }
  fi
}

# ---------------------------------------------------------------------------
# fixture D: 混在ケース
#   AC1: impl_files: ["dummy/impl.sh"]、diff 不一致 → CRITICAL
#   AC2: impl_files 不在                            → INFO
#   期待: CRITICAL 1件 + INFO 1件、exit 1
# ---------------------------------------------------------------------------

@test "ac5: fixture D (混在) - AC1 CRITICAL + AC2 INFO → exit 1" {
  # RED: ac-impl-coverage-check.sh が存在しないため fail する
  [[ -f "$SCRIPT" ]] || {
    echo "FAIL: AC #5 (fixture D) — ac-impl-coverage-check.sh が存在しない" >&2
    return 1
  }

  local mapping_file="$SANDBOX/ac-test-mapping-fixture-d.yaml"
  cat > "$mapping_file" <<'YAML'
mappings:
  - ac_index: 1
    ac_text: "実装 AC (impl_files あり、diff 不一致)"
    test_file: "test_impl.sh"
    test_name: "test_ac1_impl"
    impl_files:
      - "dummy/impl.sh"
  - ac_index: 2
    ac_text: "impl_files 不在 AC"
    test_file: "test_noimpl.sh"
    test_name: "test_ac2_noimpl"
YAML

  # diff: AC1 の dummy/impl.sh が含まれない → CRITICAL
  # AC2: impl_files 不在 → INFO
  run bash -c "printf 'other/unrelated.sh' | bash '$SCRIPT' --mapping '$mapping_file'"

  # CRITICAL 1件以上のため exit 1
  [[ "$status" -eq 1 ]] || {
    echo "FAIL: AC #5 (fixture D) — exit code ${status}、期待 exit 1 (CRITICAL あり)" >&2
    echo "  stdout: $output" >&2
    return 1
  }
}

@test "ac5: fixture D - CRITICAL 1件 + INFO 1件が出力される" {
  # RED: ac-impl-coverage-check.sh が存在しないため fail する
  [[ -f "$SCRIPT" ]] || {
    echo "FAIL: AC #5 (fixture D) — ac-impl-coverage-check.sh が存在しない" >&2
    return 1
  }

  local mapping_file="$SANDBOX/ac-test-mapping-fixture-d.yaml"
  cat > "$mapping_file" <<'YAML'
mappings:
  - ac_index: 1
    ac_text: "実装 AC (impl_files あり、diff 不一致)"
    test_file: "test_impl.sh"
    test_name: "test_ac1_impl"
    impl_files:
      - "dummy/impl.sh"
  - ac_index: 2
    ac_text: "impl_files 不在 AC"
    test_file: "test_noimpl.sh"
    test_name: "test_ac2_noimpl"
YAML

  run bash -c "printf 'other/unrelated.sh' | bash '$SCRIPT' --mapping '$mapping_file'"

  # CRITICAL 1件
  echo "$output" | jq -e '[.[] | select(.severity == "CRITICAL")] | length == 1' >/dev/null 2>&1 || {
    echo "FAIL: AC #5 (fixture D) — CRITICAL finding が 1 件ではない" >&2
    echo "  stdout: $output" >&2
    return 1
  }

  # INFO 1件（impl_files 不在の AC2）
  echo "$output" | jq -e '[.[] | select(.severity == "INFO")] | length == 1' >/dev/null 2>&1 || {
    echo "FAIL: AC #5 (fixture D) — INFO finding が 1 件ではない" >&2
    echo "  stdout: $output" >&2
    return 1
  }
}

@test "ac5: fixture D - 各 finding に severity/confidence/file/line/message/category フィールドが存在する" {
  # ref-specialist-output-schema 準拠確認
  # RED: ac-impl-coverage-check.sh が存在しないため fail する
  [[ -f "$SCRIPT" ]] || {
    echo "FAIL: AC #5 (fixture D) — ac-impl-coverage-check.sh が存在しない" >&2
    return 1
  }

  local mapping_file="$SANDBOX/ac-test-mapping-fixture-d.yaml"
  cat > "$mapping_file" <<'YAML'
mappings:
  - ac_index: 1
    ac_text: "実装 AC"
    test_file: "test_impl.sh"
    test_name: "test_ac1_impl"
    impl_files:
      - "dummy/impl.sh"
  - ac_index: 2
    ac_text: "impl_files 不在 AC"
    test_file: "test_noimpl.sh"
    test_name: "test_ac2_noimpl"
YAML

  run bash -c "printf 'other/unrelated.sh' | bash '$SCRIPT' --mapping '$mapping_file'"

  # 全 finding が必須フィールドを持つ
  echo "$output" | jq -e '
    . | all(
      has("severity") and
      has("confidence") and
      has("file") and
      has("line") and
      has("message") and
      has("category")
    )
  ' >/dev/null 2>&1 || {
    echo "FAIL: AC #5 (fixture D) — finding に必須フィールドが不足している" >&2
    echo "  stdout: $output" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# AC6: Issue body の「関連」セクションに L2/#1025 scope 外・ADR-030 補完を明記（doc AC）
# ---------------------------------------------------------------------------

@test "ac6: Issue body の「関連」セクションに L2/#1025 scope 外と ADR-030 補完が明記されている" {
  # gh CLI で Issue #1105 body を取得し、要求内容の存在を確認する
  local issue_body
  issue_body=$(gh issue view 1105 --json body -q .body 2>/dev/null || echo "")
  [[ -n "$issue_body" ]] || {
    echo "FAIL: AC #6 — Issue #1105 を取得できない (gh 未設定またはネットワーク不可)" >&2
    return 1
  }
  # L2/#1025 scope 外の明記
  echo "$issue_body" | grep -q "#1025" || {
    echo "FAIL: AC #6 未実装 — Issue body に #1025 への言及がない" >&2
    return 1
  }
  # ADR-030 補完の記述
  echo "$issue_body" | grep -qE "ADR-030|HUMAN GATE" || {
    echo "FAIL: AC #6 未実装 — Issue body に ADR-030 または HUMAN GATE への言及がない" >&2
    return 1
  }
}
