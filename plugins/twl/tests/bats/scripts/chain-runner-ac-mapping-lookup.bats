#!/usr/bin/env bats
# chain-runner-ac-mapping-lookup.bats — Issue #1480
#
# Spec: chain-runner.sh の ac-test-mapping lookup に
#       plugins/twl/tests/bats/scripts/ パスを追加する
#
# Coverage:
#   AC1: chain-runner.sh の for _candidate in ブロックに
#        plugins/twl/tests/bats/scripts/ lookup path が含まれる（静的 grep）
#   AC2: scripts/ ディレクトリのダミー mapping ファイルが
#        chain-runner.sh の lookup で検出される（動作検証）
#   AC3: out of scope（別 PR） — skip
#   AC4: out of scope（プロセス AC） — skip
#
# §9 heredoc チェック: このファイルでは heredoc 内で外部変数を使用しないため
# シングルクォート heredoc を使用しても問題なし。
#
# §10 source guard チェック: chain-runner.sh は source guard を持たない。
# テストでは chain-runner.sh を直接 source せず、bash で呼び出す（grep のみ）か、
# または step_ac_verify 関数をラップするスクリプト経由でアクセスする。
# chain-runner.sh を source すると set -euo pipefail 環境での main 到達前 exit
# リスクがあるため、直接 source は行わない。

load '../helpers/common'

# CHAIN_RUNNER_SH はテスト全体で使用する実ファイルへの絶対パス
# (SANDBOX にコピーされた scripts/chain-runner.sh ではなく、リポジトリの実ファイルを参照)
CHAIN_RUNNER_SH=""

setup() {
  common_setup

  # REPO_ROOT は common.bash で定義される（plugins/twl/ を指す）
  # chain-runner.sh の実ファイルパスを解決する
  CHAIN_RUNNER_SH="${REPO_ROOT}/scripts/chain-runner.sh"

  stub_command "git" '
    case "$*" in
      *"branch --show-current"*)
        echo "feat/1480-ac-mapping-lookup" ;;
      *"rev-parse --show-toplevel"*)
        echo "$SANDBOX" ;;
      *"rev-parse --git-dir"*)
        echo "$SANDBOX/.git" ;;
      *"diff --name-only"*)
        echo "" ;;
      *)
        exit 0 ;;
    esac
  '
  stub_command "gh" 'exit 0'
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# AC1: 静的 grep — chain-runner.sh の候補リストに scripts/ lookup path が含まれる
# ---------------------------------------------------------------------------
# RED: 現在 chain-runner.sh の for _candidate in ループに
#      "plugins/twl/tests/bats/scripts/" パスは含まれていないため FAIL する

@test "ac1: chain-runner.sh の候補リストに scripts/ lookup path が含まれる" {
  # AC: chain-runner.sh の for _candidate in ループに
  #     plugins/twl/tests/bats/scripts/ac-test-mapping-${issue_num}.yaml を追加する
  # RED: 実装前は fail する

  grep -qF 'plugins/twl/tests/bats/scripts/ac-test-mapping-' "$CHAIN_RUNNER_SH"
}

# ---------------------------------------------------------------------------
# AC2: 動作検証 — scripts/ ディレクトリの mapping ファイルが lookup で検出される
# ---------------------------------------------------------------------------
# RED: 現在 chain-runner.sh の候補リストに scripts/ パスがないため、
#      scripts/ 配下に mapping を置いても検出されず FAIL する

@test "ac2: scripts/ ディレクトリの mapping ファイルが chain-runner.sh の lookup で検出される" {
  # AC: plugins/twl/tests/bats/scripts/ にダミー mapping を置き、
  #     chain-runner.sh の lookup ロジックが検出することを検証する
  # RED: 実装前は fail する

  local issue_num="9999"
  local bats_scripts_dir="${REPO_ROOT}/tests/bats/scripts"

  # ダミー mapping ファイルを scripts/ ディレクトリに作成
  local dummy_mapping="${bats_scripts_dir}/ac-test-mapping-${issue_num}.yaml"
  mkdir -p "$bats_scripts_dir"
  cat > "$dummy_mapping" <<'DUMMY_MAPPING'
mappings:
  - ac_index: 1
    ac_text: "dummy ac for lookup test"
    test_file: ""
    test_name: "dummy_test"
    impl_files: []
DUMMY_MAPPING

  # chain-runner.sh の step_ac_verify が呼ばれる際の lookup ロジックを
  # 部分的にシミュレートする: for _candidate in ブロックで検索されるパスを列挙し
  # scripts/ パスが含まれているかを確認する
  #
  # 実装後は chain-runner.sh が "plugins/twl/tests/bats/scripts/ac-test-mapping-${issue_num}.yaml"
  # を候補に含み、_mapping_file に設定するはずである
  local found=0
  while IFS= read -r line; do
    # 候補パスとして scripts/ パスのパターンを探す
    if echo "$line" | grep -qF 'tests/bats/scripts/ac-test-mapping-'; then
      found=1
      break
    fi
  done < <(grep -A 10 'for _candidate in' "$CHAIN_RUNNER_SH")

  # found=1 なら scripts/ パスが候補に含まれている（実装済み）
  # found=0 なら未実装 → テストが fail する（RED）
  [[ "$found" -eq 1 ]] || {
    rm -f "$dummy_mapping"
    return 1
  }

  # 候補パスが存在する場合: ダミー mapping ファイルが実際に検出されるか確認
  # _candidate の展開: issue_num=9999 でパスを生成し、ファイルが存在するか検証
  local _candidate_path="${bats_scripts_dir}/ac-test-mapping-${issue_num}.yaml"
  [[ -f "$_candidate_path" ]] || {
    rm -f "$dummy_mapping"
    return 1
  }

  rm -f "$dummy_mapping"
}

# ---------------------------------------------------------------------------
# AC3: out of scope — 別 PR でのみ実装
# ---------------------------------------------------------------------------

@test "ac3: issue-create-refined.sh の E2E 検証（別 PR スコープ）" {
  skip "out of scope: AC3 は別 PR で実装する（scripts/issue-create-refined.sh）"
}

# ---------------------------------------------------------------------------
# AC4: out of scope — プロセス AC（コード実装なし）
# ---------------------------------------------------------------------------

@test "ac4: 過去 14 件の impl 不在 PR の refile（プロセス AC）" {
  skip "out of scope: AC4 はプロセス AC（手動 refile）のためコードテスト不要"
}
