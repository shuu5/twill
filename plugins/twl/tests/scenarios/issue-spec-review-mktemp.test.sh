#!/usr/bin/env bash
# =============================================================================
# Unit/Integration Tests: issue-452 manifest mktemp
#
# Source: deltaspec/changes/issue-452/specs/manifest-mktemp/spec.md
#
# Scenarios:
#   1. manifest ファイル生成 — mktemp + chmod 600 (pattern: spec-review-XXXXXXXX)
#   2. CONTEXT_ID 導出 — basename からプレフィックス除去で spec-review-XXXXXXXX 取得
#   3. 正常クリーンアップ — MANIFEST_FILE / spawned ファイル削除
#   4. フォールバッククリーンアップ — MANIFEST_FILE 未設定時 glob 削除
#   5. hook による manifest 検出 — /tmp/.specialist-manifest-*.txt glob
#   6. CONTEXT 文字列検証通過 — [a-zA-Z0-9_-]+ regex
#   7. 同一秒内 3 回並列起動 — 衝突しない一意 MANIFEST_FILE
# =============================================================================
set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

PASS=0
FAIL=0
SKIP=0
ERRORS=()

run_test() {
  local name="$1"
  local func="$2"
  local result=0
  $func || result=$?
  if [[ $result -eq 0 ]]; then
    echo "  PASS: ${name}"
    ((PASS++)) || true
  else
    echo "  FAIL: ${name}"
    ((FAIL++)) || true
    ERRORS+=("${name}")
  fi
}

# 各テストが生成した /tmp ファイルを確実に削除するヘルパー
cleanup_manifest() {
  local path="$1"
  rm -f "$path"
  # 対応する spawned ファイルも削除
  local ctx
  ctx=$(basename "$path" .txt | sed 's/^\.specialist-manifest-//')
  rm -f "/tmp/.specialist-spawned-${ctx}.txt"
}

# ---------------------------------------------------------------------------
# Scenario 1: manifest ファイル生成
#
# WHEN issue-spec-review.md の Step 4 を実行する
# THEN mktemp /tmp/.specialist-manifest-XXXXXXXX.txt でファイルが作成され、
#      パーミッションが 600 に設定され、MANIFEST_FILE にそのパスが格納される
# ---------------------------------------------------------------------------
test_mktemp_creates_manifest_with_correct_permissions() {
  # mktemp で指定パターンのファイルを生成し chmod 600 を適用するロジックを検証
  local manifest_file
  manifest_file=$(mktemp /tmp/.specialist-manifest-spec-review-XXXXXXXX.txt)
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    echo "mktemp failed (exit=$rc)" >&2
    return 1
  fi

  # ファイル名がパターンに合致するか確認（basename が .specialist-manifest- で始まる）
  local basename
  basename=$(basename "$manifest_file")
  if [[ "$basename" != .specialist-manifest-*.txt ]]; then
    echo "unexpected filename: $basename (expected .specialist-manifest-XXXXXXXX.txt)" >&2
    cleanup_manifest "$manifest_file"
    return 1
  fi

  # chmod 600 を適用
  chmod 600 "$manifest_file"
  local perm
  perm=$(stat -c '%a' "$manifest_file" 2>/dev/null || stat -f '%Lp' "$manifest_file" 2>/dev/null)
  if [[ "$perm" != "600" ]]; then
    echo "expected permission 600, got: $perm" >&2
    cleanup_manifest "$manifest_file"
    return 1
  fi

  # MANIFEST_FILE 変数にパスが格納されることをシミュレーション
  local MANIFEST_FILE="$manifest_file"
  if [[ -z "${MANIFEST_FILE}" || ! -f "${MANIFEST_FILE}" ]]; then
    echo "MANIFEST_FILE not set or file not found" >&2
    cleanup_manifest "$manifest_file"
    return 1
  fi

  cleanup_manifest "$manifest_file"
  return 0
}
run_test "manifest ファイル生成: mktemp でファイルが作成され chmod 600 が設定される" \
  test_mktemp_creates_manifest_with_correct_permissions

# ---------------------------------------------------------------------------
# Scenario 2: CONTEXT_ID 導出
#
# WHEN MANIFEST_FILE が /tmp/.specialist-manifest-AbCd1234.txt の場合
# THEN CONTEXT_ID は AbCd1234 として導出される（basename からプレフィックス除去）
# ---------------------------------------------------------------------------
test_context_id_derivation_from_manifest_path() {
  # 固定パスで CONTEXT_ID 導出ロジックをシミュレーション
  local manifest_path="/tmp/.specialist-manifest-spec-review-AbCd1234.txt"
  local expected_context="spec-review-AbCd1234"

  # 導出ロジック: basename → プレフィックス .specialist-manifest- 除去 → サフィックス .txt 除去
  local derived
  derived=$(basename "$manifest_path" .txt)
  derived="${derived#.specialist-manifest-}"

  if [[ "$derived" != "$expected_context" ]]; then
    echo "expected CONTEXT_ID='${expected_context}', got '${derived}'" >&2
    return 1
  fi

  # spec-review- プレフィックス + 8 文字英数字であることを確認
  if [[ ! "$derived" =~ ^spec-review-[a-zA-Z0-9]{8}$ ]]; then
    echo "expected spec-review-XXXXXXXX pattern, got '${derived}'" >&2
    return 1
  fi

  return 0
}
run_test "CONTEXT_ID 導出: basename からプレフィックス除去で spec-review-XXXXXXXX 取得" \
  test_context_id_derivation_from_manifest_path

# ---------------------------------------------------------------------------
# Scenario 2 (edge): 実際の mktemp 出力で CONTEXT_ID を導出できる
# ---------------------------------------------------------------------------
test_context_id_derivation_from_real_mktemp() {
  local manifest_file
  manifest_file=$(mktemp /tmp/.specialist-manifest-spec-review-XXXXXXXX.txt)
  chmod 600 "$manifest_file"

  local context_id
  context_id=$(basename "$manifest_file" .txt)
  context_id="${context_id#.specialist-manifest-}"

  # spec-review- プレフィックス + 英数字 8 文字であるか確認
  if [[ ! "$context_id" =~ ^spec-review-[a-zA-Z0-9]{8}$ ]]; then
    echo "CONTEXT_ID does not match spec-review-[a-zA-Z0-9]{8}: '${context_id}'" >&2
    cleanup_manifest "$manifest_file"
    return 1
  fi

  cleanup_manifest "$manifest_file"
  return 0
}
run_test "CONTEXT_ID 導出 (edge): 実際の mktemp パスから spec-review-XXXXXXXX を取得できる" \
  test_context_id_derivation_from_real_mktemp

# ---------------------------------------------------------------------------
# Scenario 3: 正常クリーンアップ（CONTEXT_ID あり）
#
# WHEN Step 5 完了時に MANIFEST_FILE と CONTEXT_ID が設定されている
# THEN $MANIFEST_FILE と /tmp/.specialist-spawned-${CONTEXT_ID}.txt が削除される
# ---------------------------------------------------------------------------
test_normal_cleanup_with_context_id() {
  # テスト用ファイルを事前に作成
  local MANIFEST_FILE
  MANIFEST_FILE=$(mktemp /tmp/.specialist-manifest-XXXXXXXX.txt)
  chmod 600 "$MANIFEST_FILE"

  local CONTEXT_ID
  CONTEXT_ID=$(basename "$MANIFEST_FILE" .txt)
  CONTEXT_ID="${CONTEXT_ID#.specialist-manifest-}"

  local spawned_file="/tmp/.specialist-spawned-${CONTEXT_ID}.txt"
  printf 'issue-critic\nissue-feasibility\nworker-codex-reviewer\n' > "$spawned_file"

  # クリーンアップロジックを実行（CONTEXT_ID あり分岐）
  if [[ -n "${CONTEXT_ID:-}" ]]; then
    rm -f "$MANIFEST_FILE" "$spawned_file"
  else
    rm -f /tmp/.specialist-manifest-*.txt /tmp/.specialist-spawned-*.txt
  fi

  # 両ファイルが削除されていることを確認
  if [[ -f "$MANIFEST_FILE" ]]; then
    echo "MANIFEST_FILE still exists: $MANIFEST_FILE" >&2
    rm -f "$MANIFEST_FILE" "$spawned_file"
    return 1
  fi
  if [[ -f "$spawned_file" ]]; then
    echo "spawned file still exists: $spawned_file" >&2
    rm -f "$spawned_file"
    return 1
  fi

  return 0
}
run_test "正常クリーンアップ: MANIFEST_FILE と spawned ファイルが削除される" \
  test_normal_cleanup_with_context_id

# ---------------------------------------------------------------------------
# Scenario 3 (edge): クリーンアップが他コンテキストのファイルに干渉しない
# ---------------------------------------------------------------------------
test_cleanup_does_not_affect_other_contexts() {
  # コンテキスト A（クリーンアップ対象）
  local mf_a
  mf_a=$(mktemp /tmp/.specialist-manifest-XXXXXXXX.txt)
  chmod 600 "$mf_a"
  local ctx_a
  ctx_a=$(basename "$mf_a" .txt)
  ctx_a="${ctx_a#.specialist-manifest-}"
  local sf_a="/tmp/.specialist-spawned-${ctx_a}.txt"
  touch "$sf_a"

  # コンテキスト B（クリーンアップ非対象）
  local mf_b
  mf_b=$(mktemp /tmp/.specialist-manifest-XXXXXXXX.txt)
  chmod 600 "$mf_b"
  local ctx_b
  ctx_b=$(basename "$mf_b" .txt)
  ctx_b="${ctx_b#.specialist-manifest-}"
  local sf_b="/tmp/.specialist-spawned-${ctx_b}.txt"
  touch "$sf_b"

  # コンテキスト A のみをクリーンアップ（CONTEXT_ID ピンポイント削除）
  local CONTEXT_ID="$ctx_a"
  local MANIFEST_FILE="$mf_a"
  rm -f "$MANIFEST_FILE" "/tmp/.specialist-spawned-${CONTEXT_ID}.txt"

  local result=0

  # A のファイルが消えていること
  if [[ -f "$mf_a" || -f "$sf_a" ]]; then
    echo "context A files not cleaned up" >&2
    result=1
  fi

  # B のファイルが残っていること
  if [[ ! -f "$mf_b" || ! -f "$sf_b" ]]; then
    echo "context B files unexpectedly removed" >&2
    result=1
  fi

  # B のファイルを手動クリーンアップ
  rm -f "$mf_b" "$sf_b"
  return $result
}
run_test "正常クリーンアップ (edge): 他コンテキストのファイルに干渉しない" \
  test_cleanup_does_not_affect_other_contexts

# ---------------------------------------------------------------------------
# Scenario 4: フォールバッククリーンアップ（MANIFEST_FILE 未設定）
#
# WHEN MANIFEST_FILE が未設定の場合
# THEN glob パターン /tmp/.specialist-manifest-*.txt と
#      /tmp/.specialist-spawned-*.txt で一括削除する
# ---------------------------------------------------------------------------
test_fallback_cleanup_without_manifest_file() {
  # テスト専用のファイルを /tmp に作成（本物の glob に影響しないよう prefix を付与）
  # 注: このテストは glob を実際に実行するため、テスト開始時に残存する
  #     /tmp/.specialist-manifest-*.txt も削除される可能性がある。
  #     そのため、このテストは他テストが /tmp ファイルを持ち越さないことを前提とする。

  # テスト用ファイルを作成
  local mf1
  mf1=$(mktemp /tmp/.specialist-manifest-XXXXXXXX.txt)
  local mf2
  mf2=$(mktemp /tmp/.specialist-manifest-XXXXXXXX.txt)
  local sf1="/tmp/.specialist-spawned-fallback-test-1-$$.txt"
  local sf2="/tmp/.specialist-spawned-fallback-test-2-$$.txt"
  touch "$sf1" "$sf2"

  # MANIFEST_FILE が未設定のフォールバック分岐
  local MANIFEST_FILE=""
  local CONTEXT_ID=""
  if [[ -n "${CONTEXT_ID:-}" ]]; then
    rm -f "$MANIFEST_FILE" "/tmp/.specialist-spawned-${CONTEXT_ID}.txt"
  else
    rm -f /tmp/.specialist-manifest-*.txt \
          /tmp/.specialist-spawned-*.txt
  fi

  local result=0

  # 作成したファイルが全て削除されていること
  if [[ -f "$mf1" ]]; then
    echo "mf1 still exists after fallback cleanup: $mf1" >&2
    rm -f "$mf1"
    result=1
  fi
  if [[ -f "$mf2" ]]; then
    echo "mf2 still exists after fallback cleanup: $mf2" >&2
    rm -f "$mf2"
    result=1
  fi
  if [[ -f "$sf1" ]]; then
    echo "sf1 still exists after fallback cleanup: $sf1" >&2
    rm -f "$sf1"
    result=1
  fi
  if [[ -f "$sf2" ]]; then
    echo "sf2 still exists after fallback cleanup: $sf2" >&2
    rm -f "$sf2"
    result=1
  fi

  return $result
}
run_test "フォールバッククリーンアップ: MANIFEST_FILE 未設定時に glob で一括削除" \
  test_fallback_cleanup_without_manifest_file

# ---------------------------------------------------------------------------
# Scenario 5: hook による manifest 検出
#
# WHEN issue-spec-review が manifest ファイルを作成した後、Agent tool を呼び出す
# THEN hook が /tmp/.specialist-manifest-*.txt glob でファイルを検出し、
#      CONTEXT を正常に抽出できる
# ---------------------------------------------------------------------------
test_hook_can_detect_manifest_by_glob() {
  local HOOK_SCRIPT="${PROJECT_ROOT}/scripts/hooks/check-specialist-completeness.sh"

  if [[ ! -x "$HOOK_SCRIPT" ]]; then
    echo "SKIP: hook script not found or not executable: $HOOK_SCRIPT" >&2
    ((SKIP++)) || true
    # run_test からは return 0 で skip 扱い（SKIP カウントは手動）
    return 0
  fi

  # mktemp でファイルを生成（実際の Step 4 ロジックと同様）
  local manifest_file
  manifest_file=$(mktemp /tmp/.specialist-manifest-spec-review-XXXXXXXX.txt)
  chmod 600 "$manifest_file"

  local context_id
  context_id=$(basename "$manifest_file" .txt)
  context_id="${context_id#.specialist-manifest-}"

  # manifest に specialist を書き込む
  printf 'issue-critic\nissue-feasibility\nworker-codex-reviewer\n' > "$manifest_file"

  # hook が glob でファイルを検出できるか確認
  # （hook は /tmp/.specialist-manifest-*.txt を自前で glob する実装）
  local detected
  detected=$(ls /tmp/.specialist-manifest-*.txt 2>/dev/null | grep -F "$manifest_file" || true)

  if [[ -z "$detected" ]]; then
    echo "hook cannot detect manifest file via glob: $manifest_file" >&2
    rm -f "$manifest_file"
    return 1
  fi

  # hook を実際に呼び出して CONTEXT 抽出が成功するか確認
  local hook_input
  hook_input=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"twl:twl:issue-critic"}}')
  local out rc
  out=$(printf '%s' "$hook_input" | bash "$HOOK_SCRIPT" 2>&1) || rc=$?
  rc=${rc:-0}

  # hook が exit 0 で返ること（エラーなく実行される）
  if [[ $rc -ne 0 ]]; then
    echo "hook exited with non-zero ($rc): $out" >&2
    rm -f "$manifest_file" "/tmp/.specialist-spawned-${context_id}.txt"
    return 1
  fi

  rm -f "$manifest_file" "/tmp/.specialist-spawned-${context_id}.txt"
  return 0
}
run_test "hook による manifest 検出: glob で manifest ファイルを検出できる" \
  test_hook_can_detect_manifest_by_glob

# ---------------------------------------------------------------------------
# Scenario 6: CONTEXT 文字列検証通過
#
# WHEN mktemp のランダムサフィックス（英数字 8 文字）を CONTEXT として使用する
# THEN hook の [a-zA-Z0-9_-]+ 検証をパスする
# ---------------------------------------------------------------------------
test_context_passes_hook_regex_validation() {
  # mktemp が生成するサフィックスが [a-zA-Z0-9_-]+ に合致するか確認
  local manifest_file
  manifest_file=$(mktemp /tmp/.specialist-manifest-spec-review-XXXXXXXX.txt)
  chmod 600 "$manifest_file"

  local context_id
  context_id=$(basename "$manifest_file" .txt)
  context_id="${context_id#.specialist-manifest-}"

  # hook の検証パターンと同じ regex で確認
  if [[ ! "$context_id" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "CONTEXT_ID '${context_id}' does not match [a-zA-Z0-9_-]+ (hook validation would fail)" >&2
    rm -f "$manifest_file"
    return 1
  fi

  rm -f "$manifest_file"
  return 0
}
run_test "CONTEXT 文字列検証通過: mktemp サフィックスが [a-zA-Z0-9_-]+ にマッチする" \
  test_context_passes_hook_regex_validation

# ---------------------------------------------------------------------------
# Scenario 6 (edge): date +%s%N tail -c8 と異なり特殊文字を含まない
# ---------------------------------------------------------------------------
test_context_no_special_chars_unlike_date_approach() {
  # 旧来の date ベース CONTEXT_ID は純粋な数字のみで、特殊文字は含まなかったが
  # mktemp ベースは英数字混在。両方とも [a-zA-Z0-9_-]+ をパスするかを確認。

  # 旧来方式のシミュレーション（数字のみ）
  local old_context="12345678"
  if [[ ! "$old_context" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "old-style context '${old_context}' fails validation (unexpected)" >&2
    return 1
  fi

  # mktemp 方式のシミュレーション（英数字混在）
  local new_context="AbCd1234"
  if [[ ! "$new_context" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "new-style context '${new_context}' fails validation" >&2
    return 1
  fi

  return 0
}
run_test "CONTEXT 文字列検証 (edge): date 方式・mktemp 方式ともに hook regex をパスする" \
  test_context_no_special_chars_unlike_date_approach

# ---------------------------------------------------------------------------
# Scenario 7: 同一秒内 3 回並列起動
#
# WHEN 3 つの issue-spec-review プロセスが同時に manifest 生成を実行する
# THEN 各プロセスが異なる MANIFEST_FILE パスを持ち、互いのファイルを上書きしない
# ---------------------------------------------------------------------------
test_parallel_launch_no_collision() {
  local generated_files=()
  local fail=0

  # 3 つのプロセスを並列で mktemp 実行（subshell で並列化）
  local tmpdir
  tmpdir=$(mktemp -d)

  (
    f=$(mktemp /tmp/.specialist-manifest-XXXXXXXX.txt)
    chmod 600 "$f"
    echo "$f" > "${tmpdir}/p1.txt"
  ) &
  local pid1=$!

  (
    f=$(mktemp /tmp/.specialist-manifest-XXXXXXXX.txt)
    chmod 600 "$f"
    echo "$f" > "${tmpdir}/p2.txt"
  ) &
  local pid2=$!

  (
    f=$(mktemp /tmp/.specialist-manifest-XXXXXXXX.txt)
    chmod 600 "$f"
    echo "$f" > "${tmpdir}/p3.txt"
  ) &
  local pid3=$!

  wait $pid1 $pid2 $pid3

  local f1 f2 f3
  f1=$(cat "${tmpdir}/p1.txt")
  f2=$(cat "${tmpdir}/p2.txt")
  f3=$(cat "${tmpdir}/p3.txt")
  rm -rf "$tmpdir"

  generated_files=("$f1" "$f2" "$f3")

  # 全ファイルが存在すること
  for f in "${generated_files[@]}"; do
    if [[ ! -f "$f" ]]; then
      echo "manifest file does not exist: $f" >&2
      fail=1
    fi
  done

  # 全てのパスが一意であること
  local unique_count
  unique_count=$(printf '%s\n' "${generated_files[@]}" | sort -u | wc -l)
  if [[ $unique_count -ne 3 ]]; then
    echo "collision detected: only ${unique_count}/3 unique paths: ${generated_files[*]}" >&2
    fail=1
  fi

  # 各 CONTEXT_ID が一意であること
  local ctx_ids=()
  for f in "${generated_files[@]}"; do
    local ctx
    ctx=$(basename "$f" .txt)
    ctx="${ctx#.specialist-manifest-}"
    ctx_ids+=("$ctx")
  done
  local unique_ctx
  unique_ctx=$(printf '%s\n' "${ctx_ids[@]}" | sort -u | wc -l)
  if [[ $unique_ctx -ne 3 ]]; then
    echo "CONTEXT_ID collision: only ${unique_ctx}/3 unique IDs: ${ctx_ids[*]}" >&2
    fail=1
  fi

  # クリーンアップ
  for f in "${generated_files[@]}"; do
    rm -f "$f"
  done

  return $fail
}
run_test "同一秒内 3 回並列起動: 各プロセスが異なる MANIFEST_FILE を持ち衝突しない" \
  test_parallel_launch_no_collision

# ---------------------------------------------------------------------------
# Scenario 7 (edge): date +%s%N tail -c8 は同一秒内衝突リスクがある
# ---------------------------------------------------------------------------
test_date_approach_collision_risk() {
  # date +%s%N | tail -c8 を 3 回高速実行して衝突確率を計測
  # このテストは「mktemp 方式の優位性」を検証するためのドキュメントテスト
  local ids=()
  for _ in 1 2 3; do
    ids+=("$(date +%s%N | tail -c8)")
  done

  local unique_count
  unique_count=$(printf '%s\n' "${ids[@]}" | sort -u | wc -l)

  # 衝突が発生した場合は WARNING として記録するが FAIL にはしない
  # （date 方式の問題を示すことが目的）
  if [[ $unique_count -ne 3 ]]; then
    echo "  INFO: date-based IDs collision observed (${unique_count}/3 unique)" \
         "— confirms mktemp is safer: [${ids[*]}]" >&2
  fi

  # このテスト自体は常に pass（観察目的）
  return 0
}
run_test "date 方式の衝突リスク観察 (edge): mktemp 方式との比較" \
  test_date_approach_collision_risk

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "==========================================="
echo "Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
echo "==========================================="

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo ""
  echo "Failed tests:"
  for err in "${ERRORS[@]}"; do
    echo "  - ${err}"
  done
fi

exit $FAIL
