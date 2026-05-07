#!/usr/bin/env bats
# chain-runner-step-ac-verify-cwd.bats — Issue #1490
#
# Spec: chain-runner.sh の step_ac_verify で ac-test-mapping lookup が
#       相対パスで CWD 依存になっている問題を修正する
#
# Coverage:
#   AC1: step_ac_verify の for _candidate in ブロック内のパスが
#        ${REPO_ROOT}/ プレフィックスを使って絶対パスに変換されている（静的 grep）
#   AC2: 非リポジトリルートの CWD から ac-verify を呼び出した場合でも
#        mapping ファイルが正しく検出される（動作検証）
#
# §9 heredoc チェック: このファイルでは heredoc 内で外部変数を参照しない。
# §10 source guard チェック: chain-runner.sh は source guard を持たない。
#      テストでは chain-runner.sh を bash で呼び出す（直接 source 禁止）。

load '../helpers/common'

CHAIN_RUNNER_SH=""

setup() {
  common_setup

  # REPO_ROOT は common.bash で定義される（plugins/twl/ を指す）
  CHAIN_RUNNER_SH="${REPO_ROOT}/scripts/chain-runner.sh"

  stub_command "git" '
    case "$*" in
      *"branch --show-current"*)
        echo "feat/1490-tech-debt-chain-runnersh-stepacverify" ;;
      *"rev-parse --show-toplevel"*)
        echo "$SANDBOX" ;;
      *"rev-parse --git-dir"*)
        echo "$SANDBOX/.git" ;;
      *"diff --name-only"*)
        echo "" ;;
      *"status --porcelain"*)
        echo "" ;;
      *)
        exit 0 ;;
    esac
  '
  stub_command "gh" 'exit 0'

  mkdir -p "$SANDBOX/scripts/lib"
  cat > "$SANDBOX/scripts/lib/resolve-project.sh" <<'RESOLVE_PROJECT'
#!/usr/bin/env bash
resolve_project() {
  echo "3 PVT_project_id shuu5 twill shuu5/twill"
}
RESOLVE_PROJECT
  chmod +x "$SANDBOX/scripts/lib/resolve-project.sh"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# AC1: 静的 grep — for _candidate in ブロックのパスが REPO_ROOT 絶対パスを使う
# ---------------------------------------------------------------------------
# RED: 現在は相対パス（"plugins/twl/tests/bats/..." 等）のため FAIL する

@test "ac1: step_ac_verify の候補パスが REPO_ROOT プレフィックスを使って絶対パスに変換されている" {
  # AC: chain-runner.sh の for _candidate in ループ内の候補パス（
  #     plugins/twl/tests/bats/ 以下や cli/twl/ 以下）が
  #     ${REPO_ROOT}/ または $REPO_ROOT/ プレフィックスを持つ絶対パスになっていること
  # RED: 現在は相対パスのため FAIL する

  # for _candidate in ブロックの内容を抽出し、絶対パス形式になっているか確認
  local candidate_block
  candidate_block="$(awk '/for _candidate in/,/^  done/' "$CHAIN_RUNNER_SH" | head -20)"

  # 候補パスに ${REPO_ROOT}/ または $REPO_ROOT/ が含まれていることを確認
  echo "$candidate_block" | grep -qE '\$\{?REPO_ROOT\}?/' || {
    echo "FAIL: step_ac_verify の候補パスに REPO_ROOT プレフィックスが見つかりません"
    echo "--- current candidate block ---"
    echo "$candidate_block"
    return 1
  }
}

# ---------------------------------------------------------------------------
# AC2: 動作検証 — 非リポジトリルート CWD からでも mapping ファイルが検出される
# ---------------------------------------------------------------------------
# RED: 現在は相対パスのため、CWD がリポジトリルートでない場合に検出失敗する

@test "ac2: 非リポジトリルート CWD から ac-verify を呼び出しても mapping ファイルが検出される" {
  # AC: REPO_ROOT を取得して絶対パスを使うため、
  #     任意の CWD（例: /tmp）から呼び出しても mapping が見つかること
  # RED: 現在は相対パスのため /tmp から呼び出すと lookup が失敗し、
  #      coverage check ログ "ac-impl-coverage-check: mapping=..." が出ない
  #
  # git stub は branch --show-current に "feat/1490-..." を返すため
  # issue_num=1490 として解決される。mapping も 1490 で配置する。

  # SANDBOX が REPO_ROOT として使われる（git stub が rev-parse --show-toplevel に対して $SANDBOX を返す）
  # 候補パス "${REPO_ROOT}/plugins/twl/tests/bats/scripts/" に mapping を配置する
  local issue_num="1490"
  local mapping_dir="${SANDBOX}/plugins/twl/tests/bats/scripts"
  mkdir -p "$mapping_dir"
  cat > "${mapping_dir}/ac-test-mapping-${issue_num}.yaml" <<'DUMMY_MAPPING'
mappings:
  - ac_index: 1
    ac_text: "dummy ac for cwd test"
    test_file: ""
    test_name: "dummy_test"
    impl_files: []
DUMMY_MAPPING

  # /tmp のような非リポジトリルート CWD から chain-runner.sh を呼び出す
  # AUTOPILOT_DIR=$SANDBOX/.autopilot を環境変数として渡して issue JSON を解決可能にする
  # 修正後のコードは REPO_ROOT=${SANDBOX} を取得し
  # ${SANDBOX}/plugins/twl/tests/bats/scripts/ac-test-mapping-1490.yaml を検出できるはず
  local result
  result="$(cd /tmp && AUTOPILOT_DIR="$SANDBOX/.autopilot" bash "$SANDBOX/scripts/chain-runner.sh" ac-verify 2>&1)"

  # coverage check が実行されたことを確認:
  # chain-runner.sh の step_ac_verify は mapping 検出時に
  # "[chain-runner] ac-impl-coverage-check: mapping=<path>" をログ出力する
  # 相対パス実装（現状）では /tmp から呼び出すと mapping が見つからずログが出ない → RED
  # 絶対パス実装（修正後）では REPO_ROOT 経由で mapping が見つかりログが出る → GREEN
  echo "$result" | grep -qF "ac-impl-coverage-check: mapping=" || {
    echo "FAIL: mapping ファイルが検出されませんでした（REPO_ROOT 絶対パスが未実装）"
    echo "--- output ---"
    echo "$result"
    return 1
  }
}
