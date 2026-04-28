#!/usr/bin/env bats
# issue-lifecycle-orchestrator-debounce.bats - debounce 延長 & thinking indicator 認識の RED テスト (#1087)
#
# Scenarios covered:
#   AC1: DEBOUNCE_TRANSIENT_SEC default 120s への延長
#   AC2: 環境変数 override (DEBOUNCE_TRANSIENT_SEC=N) が維持されること
#   AC3: thinking indicator 検出時に .debounce_ts をクリアすること
#   AC4(a): thinking indicator 中の debounce reset (Marinating… → .debounce_ts クリア)
#   AC4(b): 実 idle (thinking indicator なし) での 120s 経過 kill
#   AC4(c): DEBOUNCE_TRANSIENT_SEC=10 override で 10s で kill
#   AC4(d): past tense filter — Sautéed for 1m 30s は IDLE 扱いで kill される
#   AC5: 関連ドキュメント更新確認

load '../helpers/common'

SCRIPT_SRC=""
SESS_SCRIPTS_DIR_OBS=""
REPO_ROOT_OBS=""

setup() {
  common_setup
  SCRIPT_SRC="$REPO_ROOT/scripts/issue-lifecycle-orchestrator.sh"
  REPO_ROOT_OBS="$(cd "$REPO_ROOT/.." && pwd)"
  SESS_SCRIPTS_DIR_OBS="${REPO_ROOT_OBS}/session/scripts"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC1: DEBOUNCE_TRANSIENT_SEC default 120s に延長
# RED: 現在の実装では default=30 のため fail する
# ===========================================================================

# ---------------------------------------------------------------------------
# AC1: DEBOUNCE_TRANSIENT_SEC のデフォルト値が 120 であること
# WHEN issue-lifecycle-orchestrator.sh を grep する
# THEN DEBOUNCE_TRANSIENT_SEC:-120 が存在し、フォールバック値も 120 であること
# RED: 現在は DEBOUNCE_TRANSIENT_SEC:-30 のため fail する
# ---------------------------------------------------------------------------

@test "debounce #1087-AC1: DEBOUNCE_TRANSIENT_SEC default が 120 に延長されている" {
  # AC1: DEBOUNCE_TRANSIENT_SEC のデフォルト値が 120s であることを確認
  # 現在は DEBOUNCE_TRANSIENT_SEC:-30 のため RED fail する
  grep -qE 'DEBOUNCE_TRANSIENT_SEC:-120' "$SCRIPT_SRC" \
    || fail "#1087 AC1 RED: DEBOUNCE_TRANSIENT_SEC のデフォルト値が 120 になっていない。" \
            "現在は :-30 のまま。line 43 を :-120 に変更する必要がある。"
}

@test "debounce #1087-AC1: DEBOUNCE_TRANSIENT_SEC フォールバック代入値が 120 であること" {
  # AC1: 不正値フォールバック側の代入も 120 に変更されていること
  # grep: 'DEBOUNCE_TRANSIENT_SEC=120' の形式で存在するか確認
  # 現在は DEBOUNCE_TRANSIENT_SEC=30 のため RED fail する
  grep -qE 'DEBOUNCE_TRANSIENT_SEC=120$' "$SCRIPT_SRC" \
    || fail "#1087 AC1 RED: フォールバック代入 DEBOUNCE_TRANSIENT_SEC=120 が存在しない。" \
            "line 45 の DEBOUNCE_TRANSIENT_SEC=30 を 120 に変更する必要がある。"
}

@test "debounce #1087-AC1: AC0 ヘッダーコメントが Sonnet thinking time (120s) を反映している" {
  # AC1: line 42 の AC0 コメントが 120s 相当の説明に更新されていること
  # 現在は '30s' を参照する旧コメントのため RED fail する
  if grep -qE 'AC0.*120|120.*Sonnet.*thinking|thinking.*120' "$SCRIPT_SRC"; then
    true  # 120s 対応コメントが存在する → GREEN
  else
    fail "#1087 AC1 RED: AC0 コメント (line 42 付近) が 120s / Sonnet thinking time を反映していない。" \
         "コメントを '120s + margin' または Sonnet thinking time に言及する内容に更新する必要がある。"
  fi
}

# ===========================================================================
# AC2: 環境変数 override が維持されること
# GREEN condition: 既存実装を改変しないこと（現在の実装パターンが保たれていること）
# ===========================================================================

# ---------------------------------------------------------------------------
# AC2: 環境変数 DEBOUNCE_TRANSIENT_SEC override 形式が維持されている
# WHEN issue-lifecycle-orchestrator.sh を grep する
# THEN ${DEBOUNCE_TRANSIENT_SEC:-N} 形式の env override 宣言が存在する
# ---------------------------------------------------------------------------

@test "debounce #1087-AC2: DEBOUNCE_TRANSIENT_SEC は環境変数 override 形式で宣言されている" {
  # AC2: 既存の env override パターン ${DEBOUNCE_TRANSIENT_SEC:-N} が維持されていること
  # 実装が改変されず override 機能が保たれていることを確認
  grep -qE '\$\{DEBOUNCE_TRANSIENT_SEC:-[0-9]+\}' "$SCRIPT_SRC" \
    || fail "#1087 AC2: DEBOUNCE_TRANSIENT_SEC が環境変数 override 形式で宣言されていない。" \
            "既存の \${DEBOUNCE_TRANSIENT_SEC:-N} パターンが失われた可能性がある。"
}

@test "debounce #1087-AC2: 不正値チェック後のフォールバック代入が正規表現で確認できる" {
  # AC2: '! [[ ... =~ ^[0-9]+$ ]]' パターンで DEBOUNCE_TRANSIENT_SEC の不正値チェックが存在する
  grep -qE 'DEBOUNCE_TRANSIENT_SEC.*\^.*\[0-9\]|\[0-9\].*DEBOUNCE_TRANSIENT_SEC' "$SCRIPT_SRC" \
    || fail "#1087 AC2: DEBOUNCE_TRANSIENT_SEC の数値バリデーションが存在しない。" \
            "既存の regex バリデーション (=~ ^[0-9]+$) が維持されていることを確認する。"
}

# ===========================================================================
# AC3: thinking indicator 認識を debounce reset として追加
# RED: cld-observe-any の detect_thinking() / LLM_INDICATORS が orchestrator で未利用のため fail
# ===========================================================================

# ---------------------------------------------------------------------------
# AC3: cld-observe-any の LLM_INDICATORS が orchestrator で SSOT 参照されていること
# WHEN issue-lifecycle-orchestrator.sh を grep する
# THEN cld-observe-any を source / 参照するコードが存在する
# RED: 現在は cld-observe-any 参照が存在しないため fail する
# ---------------------------------------------------------------------------

@test "debounce #1087-AC3: orchestrator が cld-observe-any を source して LLM_INDICATORS を共有する" {
  # AC3: SSOT 共有 — cld-observe-any を source または LLM_INDICATORS を直接参照するコードが存在する
  # 現在は orchestrator に cld-observe-any 参照がないため RED fail する
  if grep -qE 'source.*cld-observe-any|cld-observe-any|LLM_INDICATORS' "$SCRIPT_SRC"; then
    true  # SSOT 参照が存在する → GREEN
  else
    fail "#1087 AC3 RED: orchestrator が cld-observe-any を source/参照していない。" \
         "LLM_INDICATORS は cld-observe-any が SSOT — source または直接参照を追加する必要がある。"
  fi
}

@test "debounce #1087-AC3: orchestrator の debounce ループで detect_thinking() が呼ばれる" {
  # AC3: pane capture 後に detect_thinking() を呼んで thinking indicator を検出するコードが存在する
  # 現在は orchestrator に detect_thinking 呼び出しがないため RED fail する
  grep -qE 'detect_thinking' "$SCRIPT_SRC" \
    || fail "#1087 AC3 RED: detect_thinking() 呼び出しが orchestrator に存在しない。" \
            "cld-observe-any の detect_thinking() 関数を再利用し、" \
            "thinking indicator 検出時に .debounce_ts を削除するロジックを追加する必要がある。"
}

@test "debounce #1087-AC3: thinking indicator 検出時に .debounce_ts を削除するコードが存在する" {
  # AC3: thinking indicator が見つかった場合に debounce_ts ファイルを削除する分岐が存在する
  # detect_thinking の結果を使って debounce_ts_file を rm -f するコードを期待する
  # 現在は存在しないため RED fail する
  if grep -qE 'detect_thinking.*debounce|debounce.*thinking|rm.*debounce_ts.*thinking|thinking.*rm.*debounce' "$SCRIPT_SRC"; then
    true
  else
    # より広い検索: thinking 変数が空でない場合に debounce を reset するパターン
    grep -qE '\$\{?_thinking[^}]*\}.*debounce|debounce.*\$\{?_thinking' "$SCRIPT_SRC" \
      || fail "#1087 AC3 RED: thinking indicator 検出時の .debounce_ts 削除コードが存在しない。" \
              "detect_thinking の結果が非空の場合、rm -f debounce_ts_file を実行するロジックが必要。"
  fi
}

# ===========================================================================
# AC4(a): thinking indicator 中の debounce reset
# Marinating… を pane fixture に入れて .debounce_ts がクリアされることを確認
# RED: AC3 未実装のため fail する
# ===========================================================================

@test "debounce #1087-AC4a: LLM_INDICATORS が 'Marinating...' を検出できる (SSOT 確認)" {
  # AC4(a) 前提: cld-observe-any の LLM_INDICATORS が 'Marinating…' を検出できること
  # 明示的 "Marinating" または catch-all regex '[A-Z][a-z]+(in'|ing|ed)...' でカバーされていること
  local obs_path=""
  obs_path="$(find "$REPO_ROOT_OBS" -maxdepth 4 -name "cld-observe-any" 2>/dev/null | head -1)"

  [[ -n "$obs_path" ]] || fail "AC4(a): cld-observe-any が見つからない。SSOT 確認不可。"
  # 'Marinating' が明示的に含まれるか、catch-all regex '[A-Z][a-z]+(in'|ing|ed)' でカバーされるか確認
  if grep -qiE 'Marinating|Marinated' "$obs_path"; then
    true  # 明示的に含まれる
  elif grep -qE '\[A-Z\]\[a-z\]\+' "$obs_path"; then
    true  # catch-all regex '[A-Z][a-z]+...' が存在し 'Marinating' をカバーする
  else
    fail "#1087 AC4(a): cld-observe-any の LLM_INDICATORS に 'Marinating' が含まれず、" \
         "かつ catch-all regex '[A-Z][a-z]+...' も存在しない。SSOT 確認不可。"
  fi
}

@test "debounce #1087-AC4a: thinking indicator 検出時に .debounce_ts をリセットするブランチが存在する" {
  # AC4(a): Marinating… 等の thinking indicator が pane に存在する場合、
  #         detect_thinking の結果が非空であることを条件として .debounce_ts を rm -f するコードが必要
  # 単純な rm -f debounce_ts は inject 時にも存在するため、「thinking 変数を条件とした」削除を確認する
  # 現在は detect_thinking 未実装のため RED fail する
  if grep -qE '(_thinking|thinking_word|_th_result).*debounce|debounce.*(_thinking|thinking_word|_th_result)' "$SCRIPT_SRC"; then
    true  # thinking 変数を使ったブランチが存在する
  else
    # より広い検索: -n "$_thinking" と debounce_ts が同一ブロックにある
    grep -qE 'detect_thinking.*-n.*debounce|-n.*detect_thinking.*debounce' "$SCRIPT_SRC" \
      || fail "#1087 AC4(a) RED: thinking indicator を条件とした .debounce_ts リセットブランチが存在しない。" \
              "detect_thinking の戻り値が非空のとき rm -f debounce_ts_file を実行するロジックが必要。"
  fi
}

# ===========================================================================
# AC4(b): 実 idle (thinking indicator なし) での 120s 経過 kill
# RED: DEBOUNCE_TRANSIENT_SEC が 120 に変更されていないため fail する
# ===========================================================================

@test "debounce #1087-AC4b: 実 idle 120s 経過 kill — DEBOUNCE_TRANSIENT_SEC が debounce 比較に使用されている" {
  # AC4(b): DEBOUNCE_TRANSIENT_SEC が debounce 閾値比較に使用されていること
  # 現在の実装では $DEBOUNCE_TRANSIENT_SEC が比較式に使われているが、値が 30 のため 120s 要件を満たさない
  grep -qE '\$\{?DEBOUNCE_TRANSIENT_SEC[^}]*\}.*-lt|\-lt.*\$\{?DEBOUNCE_TRANSIENT_SEC' "$SCRIPT_SRC" \
    || fail "#1087 AC4(b): DEBOUNCE_TRANSIENT_SEC が debounce 比較 (-lt) に使用されていない。"
}

@test "debounce #1087-AC4b: 実 idle の kill は DEBOUNCE_TRANSIENT_SEC=120 を前提とする (default check)" {
  # AC4(b): 実 idle kill の閾値が default 120s であること
  # DEBOUNCE_TRANSIENT_SEC default が 30 のままでは 120s kill 要件を満たさない
  # この検査は AC1 が GREEN になれば自動的に GREEN になる
  grep -qE 'DEBOUNCE_TRANSIENT_SEC:-120' "$SCRIPT_SRC" \
    || fail "#1087 AC4(b) RED: 実 idle kill の閾値が 120s になっていない (default 30s のまま)。" \
            "AC1 の DEBOUNCE_TRANSIENT_SEC:-120 を実装することで解決する。"
}

# ===========================================================================
# AC4(c): 環境変数 DEBOUNCE_TRANSIENT_SEC=10 override で 10s で kill されること
# ===========================================================================

@test "debounce #1087-AC4c: DEBOUNCE_TRANSIENT_SEC=10 override が機能する構造を確認" {
  # AC4(c): 環境変数 override DEBOUNCE_TRANSIENT_SEC=10 が debounce 比較に反映される構造であること
  # ${DEBOUNCE_TRANSIENT_SEC:-N} 形式で宣言されていれば export により override 可能
  grep -qE '\$\{DEBOUNCE_TRANSIENT_SEC:-[0-9]+\}' "$SCRIPT_SRC" \
    || fail "#1087 AC4(c): DEBOUNCE_TRANSIENT_SEC が環境変数 override 対応形式で宣言されていない。"

  # 比較式でも同変数が使用されていること
  grep -qE '\$\{?DEBOUNCE_TRANSIENT_SEC' "$SCRIPT_SRC" \
    || fail "#1087 AC4(c): DEBOUNCE_TRANSIENT_SEC が debounce 比較ロジックに組み込まれていない。"
}

# ===========================================================================
# AC4(d): past tense filter — Sautéed for 1m 30s は IDLE 扱いで kill される
# RED: past tense filter が未実装のため fail する
# ===========================================================================

@test "debounce #1087-AC4d: past tense filter が orchestrator に存在する" {
  # AC4(d): 'Sautéed for 1m 30s' などの past tense 完了形を thinking としてカウントしない filter が必要
  # cld-observe-any の detect_thinking() は LLM_INDICATORS に 'Sautéed' パターンが含まれるため
  # past tense 完了形 (for Ns/Nm Ns) を除外するロジックを orchestrator 側で実装する必要がある
  # 現在は past tense filter が存在しないため RED fail する
  if grep -qE 'past.tense|for [0-9]+[ms].*[0-9]+[ms]|for [0-9]m [0-9]+s|Saut.*ed.*for' "$SCRIPT_SRC"; then
    true  # past tense filter が存在する → GREEN
  else
    fail "#1087 AC4(d) RED: past tense filter が orchestrator に存在しない。" \
         "'Sautéed for 1m 30s' のような完了形（for N+s 付き）を thinking indicator として扱わないロジックが必要。" \
         "detect_thinking() の呼び出し前後で 'for [0-9]+[ms]' パターンを除外すること。"
  fi
}

@test "debounce #1087-AC4d: cld-observe-any の LLM_INDICATORS で Saut.*ed が現在進行形として扱われている" {
  # AC4(d) 前提確認: cld-observe-any に 'Saut.*ed' が LLM_INDICATORS に含まれること
  # これは現在進行形の indicator だが、'Sautéed for 1m 30s' は完了形なので除外が必要
  local obs_path=""
  obs_path="$(find "$REPO_ROOT_OBS" -maxdepth 4 -name "cld-observe-any" 2>/dev/null | head -1)"
  [[ -n "$obs_path" ]] || fail "AC4(d): cld-observe-any が見つからない。"

  grep -qE 'Saut' "$obs_path" \
    || fail "#1087 AC4(d): cld-observe-any に Saut* indicator が含まれない。SSOT 確認が必要。"
}

# ===========================================================================
# AC5: 関連ドキュメント更新確認
# RED: 各ドキュメントが未更新のため fail する
# ===========================================================================

# ---------------------------------------------------------------------------
# AC5: autopilot.md が debounce 延長 (120s) を反映している
# ---------------------------------------------------------------------------

@test "debounce #1087-AC5: autopilot.md が DEBOUNCE_TRANSIENT_SEC 120s を反映している" {
  local autopilot_doc="$REPO_ROOT/architecture/domain/contexts/autopilot.md"
  [[ -f "$autopilot_doc" ]] || fail "#1087 AC5: autopilot.md が存在しない: $autopilot_doc"

  grep -qE 'DEBOUNCE_TRANSIENT_SEC.*120|120.*DEBOUNCE_TRANSIENT_SEC|120[s秒].*debounce|debounce.*120[s秒]' "$autopilot_doc" \
    || fail "#1087 AC5 RED: autopilot.md に DEBOUNCE_TRANSIENT_SEC=120s の記載がない。" \
            "plugins/twl/architecture/contexts/autopilot.md を 120s 延長内容で更新する必要がある。"
}

# ---------------------------------------------------------------------------
# AC5: pitfalls-catalog.md §A2 が Sonnet thinking time / debounce 延長を記述している
# ---------------------------------------------------------------------------

@test "debounce #1087-AC5: pitfalls-catalog.md §A2 が debounce 延長を記述している" {
  local pitfalls_doc="$REPO_ROOT/skills/su-observer/refs/pitfalls-catalog.md"
  [[ -f "$pitfalls_doc" ]] || fail "#1087 AC5: pitfalls-catalog.md が存在しない: $pitfalls_doc"

  grep -qE '120|thinking.*time|debounce.*延長|延長.*debounce|Sonnet.*thinking' "$pitfalls_doc" \
    || fail "#1087 AC5 RED: pitfalls-catalog.md §A2 に debounce 延長 (120s) / Sonnet thinking time の記述がない。" \
            "plugins/twl/skills/su-observer/refs/pitfalls-catalog.md の §A2 を更新する必要がある。"
}

# ---------------------------------------------------------------------------
# AC5: issue-lifecycle-orchestrator.sh ヘッダーコメントが 120s を反映している
# ---------------------------------------------------------------------------

@test "debounce #1087-AC5: orchestrator.sh ヘッダーコメントが 120s debounce を記述している" {
  # AC5: スクリプト冒頭のコメント (Usage: / Environment: セクション) に
  #      DEBOUNCE_TRANSIENT_SEC と 120s の記述が追加されていること
  # 現在は DEBOUNCE_TRANSIENT_SEC がヘッダーコメントに存在しないため RED fail する
  grep -qE 'DEBOUNCE_TRANSIENT_SEC' <(head -30 "$SCRIPT_SRC") \
    || fail "#1087 AC5 RED: orchestrator.sh ヘッダーコメント (先頭 30 行) に DEBOUNCE_TRANSIENT_SEC の説明がない。" \
            "ヘッダー Environment セクションに DEBOUNCE_TRANSIENT_SEC の説明を追加する必要がある。"
}
