#!/usr/bin/env bats
# ci-mcp-smoke-sha-pin.bats
# Requirement: Issue #1602 — mcp-restart-smoke.yml の GitHub Actions バージョンを SHA ピン留め
# Coverage: --type=unit --coverage=ac1,ac2,ac5
#
# テスト対象: .github/workflows/mcp-restart-smoke.yml
#   AC1: actions/checkout@v4 → actions/checkout@<40-char SHA> # v<semver> に置換
#   AC2: actions/setup-python@v5 → actions/setup-python@<40-char SHA> # v<semver> に置換
#   AC5: 表記が add-to-project.yml の既存パターン (@<sha> # v<semver>) と一致
#
# AC3 (PR description に SHA 確認の記載) / AC4 (CI run URL 記載) は
# プロセスレベル AC のため本テストファイルでは検証不可 — RED placeholder のみ

WORKFLOW_FILE="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../../.." && pwd)/.github/workflows/mcp-restart-smoke.yml"

# ---------------------------------------------------------------------------
# AC1: actions/checkout が SHA ピン留め形式になっている
# WHEN mcp-restart-smoke.yml を読む
# THEN `uses: actions/checkout@<40-char-sha> # v...` 形式であること
# ---------------------------------------------------------------------------

@test "ac1: actions/checkout は 40 文字 SHA ピン留め形式になっている" {
  [ -f "$WORKFLOW_FILE" ] || skip "workflow file not found: $WORKFLOW_FILE"

  # @v4 のような mutable tag が残っていれば FAIL
  if grep -qE 'uses:[[:space:]]*actions/checkout@v[0-9]' "$WORKFLOW_FILE"; then
    echo "actions/checkout は mutable tag (@v4 等) を使用している — SHA ピン留めに置換が必要" >&2
    return 1
  fi

  # 40 文字 SHA 形式 (@[a-f0-9]{40}) が存在しなければ FAIL
  grep -qE 'uses:[[:space:]]*actions/checkout@[a-f0-9]{40}' "$WORKFLOW_FILE"
}

# ---------------------------------------------------------------------------
# AC2: actions/setup-python が SHA ピン留め形式になっている
# WHEN mcp-restart-smoke.yml を読む
# THEN `uses: actions/setup-python@<40-char-sha> # v...` 形式であること
# ---------------------------------------------------------------------------

@test "ac2: actions/setup-python は 40 文字 SHA ピン留め形式になっている" {
  [ -f "$WORKFLOW_FILE" ] || skip "workflow file not found: $WORKFLOW_FILE"

  # @v5 のような mutable tag が残っていれば FAIL
  if grep -qE 'uses:[[:space:]]*actions/setup-python@v[0-9]' "$WORKFLOW_FILE"; then
    echo "actions/setup-python は mutable tag (@v5 等) を使用している — SHA ピン留めに置換が必要" >&2
    return 1
  fi

  # 40 文字 SHA 形式が存在しなければ FAIL
  grep -qE 'uses:[[:space:]]*actions/setup-python@[a-f0-9]{40}' "$WORKFLOW_FILE"
}

# ---------------------------------------------------------------------------
# AC5: uses 行すべてが `@<sha> # v<semver>` 形式に準拠している
# WHEN mcp-restart-smoke.yml の uses 行を列挙する
# THEN 各行が `actions/checkout@<sha> # v<major>.<minor>.<patch>` 形式に一致すること
# ---------------------------------------------------------------------------

@test "ac5: uses 行は @<40-char-sha> # v<semver> 形式に準拠している" {
  [ -f "$WORKFLOW_FILE" ] || skip "workflow file not found: $WORKFLOW_FILE"

  # uses 行を抽出して形式チェック
  local bad_lines
  bad_lines=$(grep -E 'uses:[[:space:]]*[^@]+@' "$WORKFLOW_FILE" | \
    grep -vE 'uses:[[:space:]]*[^@]+@[a-f0-9]{40}[[:space:]]+#[[:space:]]*v[0-9]+\.[0-9]+\.[0-9]+' || true)

  if [ -n "$bad_lines" ]; then
    echo "以下の uses 行が規約違反 (@<sha> # v<semver> 形式になっていない):"
    echo "$bad_lines"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# AC3: PR description に SHA 確認の記載 (プロセス AC — ローカルでは検証不可)
# RED placeholder: 常に fail させる
# ---------------------------------------------------------------------------

@test "ac3: PR description に SHA 手動確認の記載がある (プロセス AC — 手動検証)" {
  # AC3 は PR description の内容を検証するプロセスレベル AC。
  # ローカルテストでは自動検証不可のため RED placeholder として保持する。
  # GREEN にするには PR 作成後に PR description を手動確認すること。
  false  # RED: プロセス AC のため常に fail
}

# ---------------------------------------------------------------------------
# AC4: PR に紐づく workflow run が成功している (CI レベル AC — ローカルでは検証不可)
# RED placeholder: 常に fail させる
# ---------------------------------------------------------------------------

@test "ac4: PR の workflow run が 1 回成功し run URL が PR description に記載されている (CI AC)" {
  # AC4 は GitHub Actions の実際の CI run を検証する CI レベル AC。
  # ローカルテストでは自動検証不可のため RED placeholder として保持する。
  # GREEN にするには GitHub CI run の成功後、PR description に run URL を記載すること。
  false  # RED: CI AC のため常に fail
}
