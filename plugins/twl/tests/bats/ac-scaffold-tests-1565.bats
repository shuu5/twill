#!/usr/bin/env bats
# ac-scaffold-tests-1565.bats
#
# Issue #1565: docs(su-observer): SKILL.md #1516 ガイダンス修正
#   -- 直接 board-status-update 経路を MUST NOT に
#
# AC1: SKILL.md の直接 board-status-update 手順が削除され、
#      "/twl:co-issue refine #<N> を spawn する（唯一の正規経路）" と
#      "MUST NOT: 直接 chain-runner.sh board-status-update を実行してはならない" が追記される
# AC2: SKILL.md に emergency bypass 手順が追記される
# AC3: 副 5 箇所（spawn-controller.sh HINT, playbook L40-46, L46周辺, L251, pitfalls §19）が整合修正される
# AC4: grep で正規ルート以外の board-status-update 出現がない
# AC5: SKILL.md ↔ playbook ↔ pitfalls-catalog でキーフレーズが相互参照整合
# AC6: SKILL.md に co-issue Phase 4 外からの直接実行禁止と TWL_CALLER_AUTHZ=co-issue-phase4 記述がある
#
# RED: 全テストは実装前に fail する（現状は旧表記が残存しているため）
# GREEN: 各ファイルの修正後に PASS する

load 'helpers/common'

SKILL_MD=""
SPAWN_CONTROLLER=""
SPAWN_PLAYBOOK=""
PITFALLS_CATALOG=""
REPO_GIT_ROOT=""
SU_OBSERVER_SKILL_DIR=""

setup() {
  common_setup
  local bats_dir
  bats_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local tests_dir
  tests_dir="$(cd "${bats_dir}/.." && pwd)"
  local plugin_root
  plugin_root="$(cd "${tests_dir}/.." && pwd)"
  REPO_GIT_ROOT="$(cd "${plugin_root}" && git rev-parse --show-toplevel 2>/dev/null || echo "")"
  SU_OBSERVER_SKILL_DIR="${plugin_root}/skills/su-observer"
  SKILL_MD="${SU_OBSERVER_SKILL_DIR}/SKILL.md"
  SPAWN_CONTROLLER="${SU_OBSERVER_SKILL_DIR}/scripts/spawn-controller.sh"
  SPAWN_PLAYBOOK="${SU_OBSERVER_SKILL_DIR}/refs/su-observer-controller-spawn-playbook.md"
  PITFALLS_CATALOG="${SU_OBSERVER_SKILL_DIR}/refs/pitfalls-catalog.md"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC1: SKILL.md — 直接 board-status-update 手順の削除と正規経路の追記
#
# RED: 現状 SKILL.md L117-120 に
#      "board-status-update --status Refined を実行して" という旧表記が残存しており、
#      新キーフレーズ "唯一の正規経路" および
#      "MUST NOT.*board-status-update" が存在しないため fail する
# ===========================================================================

@test "ac1: SKILL.md に co-issue refine spawn が唯一の正規経路として明記されている" {
  # AC: Status=Todo の場合は /twl:co-issue refine #<N> を spawn する（唯一の正規経路）が明記される
  # RED: 現状は "board-status-update --status Refined を実行して" のみ記載され
  #      "唯一の正規経路" フレーズが存在しないため grep が失敗する
  [ -f "$SKILL_MD" ]
  run grep -qF "唯一の正規経路" "$SKILL_MD"
  assert_success
}

@test "ac1: SKILL.md に /twl:co-issue refine のフレーズが存在する" {
  # AC: "/twl:co-issue refine #<N> を spawn する" の表記が SKILL.md に追記される
  # RED: 現状は "co-issue refine を spawn" という括弧書き補足のみ存在し、
  #      正規 slash コマンド形式 "/twl:co-issue refine" が主文として記載されていないため fail する
  [ -f "$SKILL_MD" ]
  run grep -qF "/twl:co-issue refine" "$SKILL_MD"
  assert_success
}

@test "ac1: SKILL.md に MUST NOT: 直接 board-status-update 禁止の文言が存在する" {
  # AC: "MUST NOT: 直接 chain-runner.sh board-status-update <N> Refined を実行してはならない" が追記される
  # RED: 現状 MUST NOT 表記が存在しないため grep が失敗する
  [ -f "$SKILL_MD" ]
  run grep -qE "MUST NOT.*board-status-update" "$SKILL_MD"
  assert_success
}

@test "ac1: SKILL.md の正規経路セクションに旧表記（board-status-update --status Refined を実行して）が残存しない" {
  # AC: "board-status-update --status Refined を実行して Refined に遷移させる" という旧主文が削除される
  # RED: 現状 L117 に旧表記が残存しているため grep が match し assert_failure が fail する
  [ -f "$SKILL_MD" ]
  # MUST NOT コンテキスト外での旧主文の残存チェック
  # "を実行して Refined に遷移させる" という旧表現が残っていれば RED
  # 実際の旧テキスト（L117): "board-status-update --status Refined` を実行して Refined に遷移させる"
  run grep -qF "board-status-update --status Refined\` を実行して Refined に遷移させる" "$SKILL_MD"
  assert_failure
}

# ===========================================================================
# AC2: SKILL.md — emergency bypass 手順の追記
#
# RED: 現状 emergency bypass の記述が SKILL.md に存在しないため fail する
# ===========================================================================

@test "ac2: SKILL.md に emergency bypass 手順が記述されている" {
  # AC: Project Board 未登録 cross-repo Issue 等で refine 経路が成立しない場合の
  #     --bypass-status-gate 手順が追記される
  # RED: 現状 SKILL.md に "--bypass-status-gate" フレーズが存在しないため fail する
  [ -f "$SKILL_MD" ]
  run grep -qF "bypass-status-gate" "$SKILL_MD"
  assert_success
}

@test "ac2: SKILL.md の emergency bypass に retroactive bypass 記述がある" {
  # AC: PR description に "retroactive bypass: ADR-024 violation acknowledged, fix tracked in #<epic>"
  #     を併記する旨が記述される
  # RED: 現状該当フレーズが存在しないため fail する
  [ -f "$SKILL_MD" ]
  run grep -qF "retroactive bypass" "$SKILL_MD"
  assert_success
}

# ===========================================================================
# AC3: 副 5 箇所の整合修正
#
# 3-1: spawn-controller.sh の error HINT が refine spawn 経路に更新される
# 3-2: playbook.md L40-46 が refine 経路 MUST + 直接実行 MUST NOT に整合
# 3-3: playbook.md L46周辺の --pre-check-issue 行が refine 経路説明に整合
# 3-4: playbook.md L251 が refine 経路 MUST + 直接実行 MUST NOT に整合
# 3-5: pitfalls-catalog.md §19 が同様に整合
#
# RED: 現状各箇所に旧 chain-runner.sh board-status-update HINT/手順が残存するため fail する
# ===========================================================================

@test "ac3-1: spawn-controller.sh の HINT に /twl:co-issue refine フレーズが存在する" {
  # AC: HINT: bash chain-runner.sh board-status-update... が
  #     /twl:co-issue refine #<N> を spawn してください に置換される
  # RED: 現状 HINT に chain-runner.sh board-status-update のみが記述され
  #      co-issue refine フレーズが HINT として存在しないため fail する
  [ -f "$SPAWN_CONTROLLER" ]
  run grep -qF "co-issue refine" "$SPAWN_CONTROLLER"
  assert_success
}

@test "ac3-1: spawn-controller.sh の HINT から旧 chain-runner.sh board-status-update HINT が削除される" {
  # AC: HINT 行の "chain-runner.sh board-status-update" という表記が削除される
  # RED: 現状 L225 および L490 付近に HINT として旧表記が残存しているため grep が match し
  #      assert_failure が fail する
  [ -f "$SPAWN_CONTROLLER" ]
  # HINT: コンテキストで旧表記が残存しないことを確認
  # 実際の形式: "[spawn-controller] HINT: bash ... chain-runner.sh board-status-update ..."
  run grep -qF "chain-runner.sh\" board-status-update" "$SPAWN_CONTROLLER"
  assert_failure
}

@test "ac3-2: spawn-playbook.md の co-autopilot spawn 前 MUST セクションが refine spawn 経路を明記している" {
  # AC: playbook.md L40-46 が /twl:co-issue refine spawn MUST + 直接実行 MUST NOT に整合
  # RED: 現状 L40-46 に "board-status-update --status Refined を実行:" という旧手順が記載されているため
  #      "唯一の正規経路" フレーズが存在せず grep が失敗する
  [ -f "$SPAWN_PLAYBOOK" ]
  run grep -qF "唯一の正規経路" "$SPAWN_PLAYBOOK"
  assert_success
}

@test "ac3-2: spawn-playbook.md の co-autopilot spawn 前セクションに MUST NOT board-status-update が明記されている" {
  # AC: playbook L40-46 に MUST NOT 直接実行が追記される
  # RED: 現状 MUST NOT board-status-update の記述が存在しないため fail する
  [ -f "$SPAWN_PLAYBOOK" ]
  run grep -qE "MUST NOT.*board-status-update" "$SPAWN_PLAYBOOK"
  assert_success
}

@test "ac3-3: spawn-playbook.md の旧 board-status-update 直接実行手順（L40-46 周辺）が削除されている" {
  # AC: "board-status-update --status Refined を実行:" という旧主文手順が削除される
  # RED: 現状 L40-44 に旧手順が残存しているため grep が match し assert_failure が fail する
  [ -f "$SPAWN_PLAYBOOK" ]
  run grep -qF "Status=Todo の場合は \`board-status-update --status Refined\` を実行" "$SPAWN_PLAYBOOK"
  assert_failure
}

@test "ac3-4: spawn-playbook.md の失敗時対処テーブル L251 が refine spawn 経路に整合している" {
  # AC: L251 の "chain-runner.sh board-status-update <N> で Refined へ遷移" が
  #     /twl:co-issue refine #<N> を spawn する記述に更新される
  # RED: 現状 L251 に旧表記が残存しているため新フレーズが存在せず fail する
  [ -f "$SPAWN_PLAYBOOK" ]
  # テーブルの対処列（2列目）に co-issue refine spawn 経路が記述されることを確認
  run grep -qF "co-issue refine" "$SPAWN_PLAYBOOK"
  assert_success
}

@test "ac3-5: pitfalls-catalog.md §19 が refine spawn 経路 MUST + 直接実行 MUST NOT に整合している" {
  # AC: §19 対策セクションが /twl:co-issue refine spawn MUST + MUST NOT 直接実行に更新される
  # RED: 現状 §19 L1168-1171 に旧 chain-runner.sh board-status-update 手順が残存しており
  #      "唯一の正規経路" フレーズが存在しないため fail する
  [ -f "$PITFALLS_CATALOG" ]
  run grep -qF "唯一の正規経路" "$PITFALLS_CATALOG"
  assert_success
}

@test "ac3-5: pitfalls-catalog.md §19 の旧 board-status-update 直接実行手順が削除されている" {
  # AC: §19 の "board-status-update --status Refined を実行:" コードブロックが削除される
  # RED: 現状 §19 L1168-1171 に旧手順が残存しているため grep が match し assert_failure が fail する
  [ -f "$PITFALLS_CATALOG" ]
  run grep -qF "Status=Todo の場合は \`board-status-update --status Refined\` を実行" "$PITFALLS_CATALOG"
  assert_failure
}

# ===========================================================================
# AC4: MUST NOT コンテキスト以外で board-status-update の出現がない
#
# grep -rn "board-status-update --status Refined|chain-runner.sh board-status-update"
#   plugins/twl/skills/su-observer/
# MUST NOT コンテキストとして残るのは許容
#
# RED: 現状 SKILL.md / playbook / pitfalls-catalog / spawn-controller.sh に
#      MUST NOT コンテキスト外の旧表記が残存しているため fail する
# ===========================================================================

@test "ac4: su-observer ディレクトリ内に正規ルート以外の board-status-update --status Refined 出現がない" {
  # AC: grep -rn "board-status-update --status Refined" plugins/twl/skills/su-observer/ で
  #     MUST NOT コンテキスト以外の出現がない
  # RED: 現状 SKILL.md L117 / playbook L42 / pitfalls §19 L1170 に旧表記が残存しているため
  #      MUST NOT コンテキスト外の match が存在し fail する
  [ -d "$SU_OBSERVER_SKILL_DIR" ]

  # 全マッチを取得して MUST NOT コンテキスト行のみに限定されることを確認
  local match_count
  run bash -c "grep -rn 'board-status-update --status Refined' '$SU_OBSERVER_SKILL_DIR' | grep -v 'MUST NOT' | grep -vc '^\s*#'"
  # MUST NOT コンテキスト外の出現が 0 件であることを確認
  # (grep -v が全行除外 → grep -vc が 0 → run exit code は grep -vc が 0行で exit 1)
  # 方針: 出現行数が 0 であれば PASS
  local raw_count
  # wc -l は常に exit 0 で整数を返す（grep -cv + || echo 0 の "0\n0" バグ修正）
  raw_count="$(grep -rn 'board-status-update --status Refined' "$SU_OBSERVER_SKILL_DIR" \
    | grep -v 'MUST NOT' | wc -l)"
  [ "$raw_count" -eq 0 ]
}

@test "ac4: su-observer ディレクトリ内に正規ルート以外の chain-runner.sh board-status-update 出現がない" {
  # AC: grep -rn "chain-runner.sh board-status-update" plugins/twl/skills/su-observer/ で
  #     MUST NOT コンテキスト以外の出現がない
  # RED: 現状 spawn-controller.sh L225/L490 / playbook L42 / pitfalls §19 L1170 に残存しているため
  #      MUST NOT コンテキスト外の match が存在し fail する
  [ -d "$SU_OBSERVER_SKILL_DIR" ]

  local raw_count
  # wc -l は常に exit 0 で整数を返す（grep -cv + || echo 0 の "0\n0" バグ修正）
  raw_count="$(grep -rn 'chain-runner\.sh board-status-update' "$SU_OBSERVER_SKILL_DIR" \
    | grep -v 'MUST NOT' | wc -l)"
  [ "$raw_count" -eq 0 ]
}

# ===========================================================================
# AC5: キーフレーズの相互参照整合
#
# grep -n "co-issue refine|唯一の正規経路|MUST NOT.*board-status-update"
#   plugins/twl/skills/su-observer/{SKILL.md,refs/su-observer-controller-spawn-playbook.md,refs/pitfalls-catalog.md}
# の 3 ファイル全てでキーフレーズが出現すること
#
# RED: 現状いずれのファイルも新キーフレーズが存在しないため fail する
# ===========================================================================

@test "ac5: SKILL.md に /twl:co-issue refine 正規フォームが存在する（相互参照整合）" {
  # RED: 現状 SKILL.md には括弧内の補足 "(または `co-issue refine` を spawn)" のみ存在し、
  #      正規 slash コマンド形式 "/twl:co-issue refine" が主文として記載されていないため fail する
  [ -f "$SKILL_MD" ]
  run grep -qF "/twl:co-issue refine" "$SKILL_MD"
  assert_success
}

@test "ac5: su-observer-controller-spawn-playbook.md に co-issue refine フレーズが存在する（相互参照整合）" {
  # RED: 現状 playbook に "co-issue refine" フレーズが存在しないため fail する
  [ -f "$SPAWN_PLAYBOOK" ]
  run grep -qF "co-issue refine" "$SPAWN_PLAYBOOK"
  assert_success
}

@test "ac5: pitfalls-catalog.md に co-issue refine フレーズが存在する（相互参照整合）" {
  # RED: 現状 pitfalls-catalog に "co-issue refine" フレーズが存在しないため fail する
  [ -f "$PITFALLS_CATALOG" ]
  run grep -qF "co-issue refine" "$PITFALLS_CATALOG"
  assert_success
}

@test "ac5: 3 ファイル全てで 唯一の正規経路 キーフレーズが出現する" {
  # AC: grep -n "唯一の正規経路" が SKILL.md / playbook / pitfalls-catalog の 3 ファイルで match すること
  # RED: 現状 3 ファイルとも "唯一の正規経路" フレーズが存在しないため fail する
  [ -f "$SKILL_MD" ]
  [ -f "$SPAWN_PLAYBOOK" ]
  [ -f "$PITFALLS_CATALOG" ]
  run grep -qF "唯一の正規経路" "$SKILL_MD"
  assert_success
  run grep -qF "唯一の正規経路" "$SPAWN_PLAYBOOK"
  assert_success
  run grep -qF "唯一の正規経路" "$PITFALLS_CATALOG"
  assert_success
}

@test "ac5: 3 ファイル全てで MUST NOT.*board-status-update が出現する" {
  # AC: MUST NOT: 直接実行禁止が 3 ファイル全てで表現される
  # RED: 現状 3 ファイルとも MUST NOT board-status-update 表記が存在しないため fail する
  [ -f "$SKILL_MD" ]
  [ -f "$SPAWN_PLAYBOOK" ]
  [ -f "$PITFALLS_CATALOG" ]
  run grep -qE "MUST NOT.*board-status-update" "$SKILL_MD"
  assert_success
  run grep -qE "MUST NOT.*board-status-update" "$SPAWN_PLAYBOOK"
  assert_success
  run grep -qE "MUST NOT.*board-status-update" "$PITFALLS_CATALOG"
  assert_success
}

# ===========================================================================
# AC6: SKILL.md に co-issue Phase 4 外からの直接実行禁止と
#      TWL_CALLER_AUTHZ=co-issue-phase4 env marker の意味が一致する記述がある
#
# RED: 現状 TWL_CALLER_AUTHZ=co-issue-phase4 フレーズが SKILL.md に存在しないため fail する
# ===========================================================================

@test "ac6: SKILL.md に TWL_CALLER_AUTHZ=co-issue-phase4 env marker が記述されている" {
  # AC: TWL_CALLER_AUTHZ=co-issue-phase4 という env marker の意味が SKILL.md に記述される
  # RED: 現状 SKILL.md に該当フレーズが存在しないため fail する
  [ -f "$SKILL_MD" ]
  run grep -qF "TWL_CALLER_AUTHZ=co-issue-phase4" "$SKILL_MD"
  assert_success
}

@test "ac6: SKILL.md に co-issue Phase 4 外から直接実行禁止の文言がある" {
  # AC: "co-issue Phase 4 外から直接実行禁止" または同等の文言が SKILL.md に記述される
  # RED: 現状 SKILL.md に該当表現が存在しないため fail する
  [ -f "$SKILL_MD" ]
  run grep -qE "co-issue.*(Phase 4|phase4).*禁止|Phase 4.*直接実行禁止" "$SKILL_MD"
  assert_success
}
