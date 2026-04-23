#!/usr/bin/env bash
# issue-lifecycle-orchestrator.sh — co-issue v2 Worker 側バッチ orchestrator
#
# per-issue dir 配下の各 subdir に対して /twl:workflow-issue-lifecycle を
# tmux cld セッションで並列起動する。
#
# spec-review-orchestrator.sh のコードパターンを流用:
#   - tmux new-window + cld セッション並列起動
#   - MAX_PARALLEL バッチ制御
#   - ポーリング完了検知（OUT/report.json の存在確認）
#   - flock による window 名衝突回避
#   - || continue による失敗局所化
#   - Resume 対応（done スキップ / failed リセット）
#
# Usage:
#   bash issue-lifecycle-orchestrator.sh --per-issue-dir <abs-path>
#
# Environment:
#   MAX_PARALLEL   バッチあたり最大並列セッション数（デフォルト: 3）
#   POLL_INTERVAL  ポーリング間隔（秒、デフォルト: 10）
#   MAX_POLL       最大ポーリング回数（デフォルト: 360）

set -euo pipefail

SCRIPTS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# lockfile クリーンアップ（spawn_session 内で作成した /tmp/.coi-window-*.lock）
trap 'rm -f /tmp/.coi-window-*.lock 2>/dev/null || true' EXIT

MAX_PARALLEL="${MAX_PARALLEL:-3}"
if ! [[ "$MAX_PARALLEL" =~ ^[1-9][0-9]*$ ]]; then
  MAX_PARALLEL=3
fi
POLL_INTERVAL="${POLL_INTERVAL:-10}"
if ! [[ "$POLL_INTERVAL" =~ ^[1-9][0-9]*$ ]]; then
  POLL_INTERVAL=10
fi
MAX_POLL="${MAX_POLL:-360}"
if ! [[ "$MAX_POLL" =~ ^[1-9][0-9]*$ ]]; then
  MAX_POLL=360
fi

# --- 使い方 ---
usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

  --per-issue-dir DIR  per-issue ディレクトリの絶対パス（必須）
                       .controller-issue/<sid>/per-issue/ に相当
  --model MODEL        Worker セッションに使用するモデル（デフォルト: sonnet）
  --resume             Resume モード（done 済みをスキップ、failed をリセット）
                       ※ resume 動作は spawn_session 内で常時有効なため実質 no-op
  -h, --help           このヘルプを表示

Environment:
  MAX_PARALLEL   バッチあたり最大並列セッション数（デフォルト: 3）
  POLL_INTERVAL  ポーリング間隔（秒、デフォルト: 10）
  MAX_POLL       最大ポーリング回数（デフォルト: 360）
EOF
}

# report.json フォールバック生成 (#647)
# specialist が report.json を書かずに完了した場合に、
# findings.yaml / aggregate.yaml から report.json を構築する
_generate_fallback_report() {
  local subdir="$1" reason="$2"
  local report_file="${subdir}/OUT/report.json"

  # findings.yaml / aggregate.yaml がある場合はそこから構築
  local aggregate_file="${subdir}/OUT/aggregate.yaml"
  local findings_file="${subdir}/OUT/findings.yaml"

  if [[ -f "$aggregate_file" ]]; then
    # aggregate.yaml → report.json 変換（環境変数経由でパスを渡す — CWE-78 対策）
    _FB_INPUT="$aggregate_file" _FB_OUTPUT="$report_file" _FB_REASON="$reason" _FB_KEY="aggregate" \
      python3 -c '
import yaml, json, os, sys
with open(os.environ["_FB_INPUT"]) as f:
    data = yaml.safe_load(f) or {}
report = {"status": "done", "fallback": True, "reason": os.environ["_FB_REASON"],
          "findings_count": len(data.get("findings", [])), os.environ["_FB_KEY"]: data}
with open(os.environ["_FB_OUTPUT"], "w") as f:
    json.dump(report, f, ensure_ascii=False, indent=2)
' 2>/dev/null && return 0
  fi

  if [[ -f "$findings_file" ]]; then
    _FB_INPUT="$findings_file" _FB_OUTPUT="$report_file" _FB_REASON="$reason" _FB_KEY="findings" \
      python3 -c '
import yaml, json, os, sys
with open(os.environ["_FB_INPUT"]) as f:
    data = yaml.safe_load(f) or {}
report = {"status": "done", "fallback": True, "reason": os.environ["_FB_REASON"],
          os.environ["_FB_KEY"]: data}
with open(os.environ["_FB_OUTPUT"], "w") as f:
    json.dump(report, f, ensure_ascii=False, indent=2)
' 2>/dev/null && return 0
  fi

  # 中間ファイルもない場合は最小限のフォールバック
  _FB_OUTPUT="$report_file" _FB_REASON="$reason" python3 -c '
import json, os
report = {"status": "done", "fallback": True, "reason": os.environ["_FB_REASON"],
          "error": "no_intermediate_files"}
with open(os.environ["_FB_OUTPUT"], "w") as f:
    json.dump(report, f, ensure_ascii=False, indent=2)
'
}

# source 経由でのテスト用に、直接実行時のみメインロジックを実行する
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then return 0; fi

# --- 引数パーサー ---
PER_ISSUE_DIR=""
WORKER_MODEL="sonnet"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --per-issue-dir) PER_ISSUE_DIR="$2"; shift 2 ;;
    --model)         WORKER_MODEL="$2"; shift 2 ;;
    --resume)        shift ;;  # spawn_session 内で常時 resume 動作 — フラグは受け取るが追加処理不要
    -h|--help)       usage; exit 0 ;;
    *) echo "Error: 不明なオプション: $1" >&2; exit 1 ;;
  esac
done

# --- バリデーション ---
if [[ -z "$WORKER_MODEL" ]]; then
  echo "Error: --model の値は空にできません" >&2
  exit 1
fi

if [[ -z "$PER_ISSUE_DIR" ]]; then
  echo "Error: --per-issue-dir は必須です" >&2
  usage
  exit 1
fi

if [[ "$PER_ISSUE_DIR" != /* ]]; then
  echo "Error: --per-issue-dir は絶対パスで指定してください: $PER_ISSUE_DIR" >&2
  exit 1
fi

if [[ "$PER_ISSUE_DIR" =~ /\.\./ || "$PER_ISSUE_DIR" =~ /\.\.$ ]]; then
  echo "Error: --per-issue-dir にパストラバーサルは使用できません: $PER_ISSUE_DIR" >&2
  exit 1
fi

if [[ ! -d "$PER_ISSUE_DIR" ]]; then
  echo "Error: --per-issue-dir が存在しません: $PER_ISSUE_DIR" >&2
  exit 1
fi

# --- cld 存在確認 ---
CLD_PATH=$(command -v cld 2>/dev/null || true)
if [[ -z "$CLD_PATH" ]]; then
  echo "Error: cld が見つかりません" >&2
  exit 1
fi

# --- per-issue subdir 収集（IN/draft.md が存在するディレクトリ） ---
# symlink も追跡するため -L オプション付き find を使用
mapfile -t SUBDIRS < <(
  find -L "$PER_ISSUE_DIR" -mindepth 1 -maxdepth 1 -type d | sort | while read -r d; do
    if [[ -f "$d/IN/draft.md" ]]; then
      echo "$d"
    fi
  done
)
TOTAL="${#SUBDIRS[@]}"

# サブディレクトリに見つからない場合、渡されたディレクトリ自体が Issue dir かチェック
if [[ "$TOTAL" -eq 0 ]] && [[ -f "${PER_ISSUE_DIR}/IN/draft.md" ]]; then
  SUBDIRS=("$PER_ISSUE_DIR")
  TOTAL=1
fi

if [[ "$TOTAL" -eq 0 ]]; then
  echo "Error: --per-issue-dir に IN/draft.md を含むサブディレクトリが見つかりません: $PER_ISSUE_DIR" >&2
  exit 1
fi

echo "[issue-lifecycle-orchestrator] サブディレクトリ数: ${TOTAL}, MAX_PARALLEL: ${MAX_PARALLEL}"

# ADR-017 IM-7: N=1 不変量は各 Worker（workflow-issue-lifecycle）が個別に
# spec-review-session-init.sh 1 を呼び出すことで保証する。
# orchestrator はセッション初期化を行わない（state file 競合防止）。

# =============================================================================
# sid 抽出ユーティリティ
# =============================================================================

# per-issue-dir のパスから sid8（先頭8文字）を抽出
extract_sid8() {
  local dir="$1"
  # .controller-issue/<sid>/per-issue パターンから抽出を試みる
  local sid
  sid="$(basename "$(dirname "$dir")" 2>/dev/null || echo "")"
  if [[ -z "$sid" || "$sid" == "." ]]; then
    # フォールバック: パス全体のハッシュ
    sid="$(printf '%s' "$dir" | md5sum | cut -c1-8)"
  fi
  # tmux 特殊文字（:, %, ., !）を除去してウィンドウ名を安全にする
  local clean_sid="${sid:0:8}"
  clean_sid="${clean_sid//[^a-zA-Z0-9_-]/x}"
  printf '%s' "$clean_sid"
}

# サブディレクトリからインデックスを取得
index_of_subdir() {
  local target="$1"
  local i=0
  for d in "${SUBDIRS[@]}"; do
    if [[ "$d" == "$target" ]]; then
      echo "$i"
      return
    fi
    i=$((i + 1))
  done
  echo "0"
}

SID8="$(extract_sid8 "$PER_ISSUE_DIR")"

# =============================================================================
# window 名生成
# =============================================================================

window_name_for_subdir() {
  local subdir="$1"
  local idx
  idx="$(index_of_subdir "$subdir")"
  echo "coi-${SID8}-${idx}"
}

# =============================================================================
# セッション spawn ヘルパー
# =============================================================================

# subdir の IN/policies.json から主要フィールドを抽出する
# 引数: subdir ref_max_rounds ref_specialists ref_depth ref_policy_qflag ref_target_repo
# ref_* は nameref で書き込む変数名
_extract_policies_fields() {
  local subdir="$1"
  local -n _pf_max_rounds="$2"
  local -n _pf_specialists="$3"
  local -n _pf_depth="$4"
  local -n _pf_policy_qflag="$5"
  local -n _pf_target_repo="$6"
  _pf_max_rounds="" ; _pf_specialists="" ; _pf_depth="" ; _pf_policy_qflag="" ; _pf_target_repo=""
  if [[ -f "${subdir}/IN/policies.json" ]] && command -v jq >/dev/null 2>&1; then
    _pf_max_rounds="$(jq -r '.max_rounds // empty' "${subdir}/IN/policies.json" 2>/dev/null || true)"
    _pf_specialists="$(jq -r '(.specialists // []) | join(",")' "${subdir}/IN/policies.json" 2>/dev/null || true)"
    _pf_depth="$(jq -r '.depth // empty' "${subdir}/IN/policies.json" 2>/dev/null || true)"
    _pf_policy_qflag="$(jq -r '.quick_flag // empty' "${subdir}/IN/policies.json" 2>/dev/null || true)"
    _pf_target_repo="$(jq -r '.target_repo // empty' "${subdir}/IN/policies.json" 2>/dev/null || true)"
  fi
}

# プロンプトテンポラリファイルを生成して ref_prompt_file に書き込む
# 引数: subdir max_rounds specialists depth policy_qflag target_repo ref_prompt_file
_build_worker_prompt() {
  local subdir="$1" max_rounds="$2" specialists="$3" depth="$4" policy_qflag="$5" target_repo="$6"
  local -n _bwp_prompt_file="$7"
  local workflow_skill="workflow-issue-lifecycle"
  if [[ -f "${subdir}/IN/existing-issue.json" ]]; then
    workflow_skill="workflow-issue-refine"
  fi
  _bwp_prompt_file="$(mktemp /tmp/.coi-prompt-XXXXXX.txt)"
  # inject プロンプト生成（printf 方式: heredoc 終端子汚染リスクを回避）
  printf '%s\n' \
    "/twl:${workflow_skill} $(printf '%q' "$subdir")" \
    "" \
    "【自律実行指示】" \
    "- 全 Step を中断なく自律的に完了すること" \
    "- 途中で AskUserQuestion を使用しないこと" \
    "- エラー発生時は OUT/report.json に status: failed を書き込んで exit すること" \
    "- policies.json の設定に従い specialist review を実行すること" \
    "" \
    "【policies.json 主要フィールド】" \
    "- max_rounds: ${max_rounds}" \
    "- specialists: ${specialists}" \
    "- depth: ${depth}" \
    "- policy_qflag: ${policy_qflag}" \
    "- target_repo: ${target_repo}" \
    > "$_bwp_prompt_file"
}

# cld-spawn でウィンドウを起動し inject-file でプロンプトを送達する
# 引数: subdir window_name prompt_file
_spawn_tmux_window_with_prompt() {
  local subdir="$1" window_name="$2" prompt_file="$3"
  local SESSION_SCRIPTS="${SCRIPTS_ROOT}/../../session/scripts"
  echo "[issue-lifecycle-orchestrator] ${subdir##*/}: spawn (window=${window_name})" >&2
  # TWL_AUDIT / TWL_AUDIT_DIR を export して cld-spawn 子プロセスに継承させる (Wave 23)
  # cld-spawn は CLD_ENV_FILE を自動 source するが、TWL_AUDIT は ~/.cld-env に含まれないため明示的に export
  # export はシェルグローバルに波及するが、orchestrator プロセス内で一貫して有効にする意図
  if [[ "${TWL_AUDIT:-}" == "1" ]]; then
    export TWL_AUDIT
    [[ -n "${TWL_AUDIT_DIR:-}" ]] && export TWL_AUDIT_DIR
  fi
  # cld-spawn: 対話モードで起動（one-shot モード stdout 問題を回避 — #541）
  # env-file は CLD_ENV_FILE 環境変数のフォールバックに委譲（cld-spawn が自動検出）
  "${SESSION_SCRIPTS}/cld-spawn" --cd "$(pwd)" --window-name "${window_name}" --model "${WORKER_MODEL}" || {
    rm -f "$prompt_file" 2>/dev/null || true
    echo "[issue-lifecycle-orchestrator] ${subdir##*/}: cld-spawn 失敗" >&2
    return 1
  }
  tmux set-option -t "$window_name" remain-on-exit on 2>/dev/null || true
  # inject-file: プロンプトをセッションに安全に送達（wait-ready 後）
  "${SESSION_SCRIPTS}/session-comm.sh" inject-file "${window_name}" "${prompt_file}" --wait 60 || {
    rm -f "$prompt_file" 2>/dev/null || true
    tmux kill-window -t "${window_name}" 2>/dev/null || true
    echo "[issue-lifecycle-orchestrator] ${subdir##*/}: inject-file 失敗" >&2
    return 1
  }
  rm -f "$prompt_file" 2>/dev/null || true
}

# =============================================================================
# セッション spawn
# =============================================================================

spawn_session() {
  local subdir="$1"
  local window_name
  window_name="$(window_name_for_subdir "$subdir")"
  local report_file="${subdir}/OUT/report.json"
  local state_file="${subdir}/STATE"

  # Resume: OUT/report.json が存在する（done 済み）→ スキップ
  if [[ -f "$report_file" ]]; then
    echo "[issue-lifecycle-orchestrator] ${subdir##*/}: report.json 既存 — スキップ" >&2
    return 0
  fi

  # Resume: STATE が "failed" → リセット
  if [[ -f "$state_file" ]] && grep -qF "failed" "$state_file" 2>/dev/null; then
    echo "[issue-lifecycle-orchestrator] ${subdir##*/}: STATE=failed — リセットして再実行" >&2
    printf 'running\n' > "$state_file"
  fi

  # flock で window 名衝突回避
  local lockfile="/tmp/.coi-window-${window_name}.lock"
  exec {lockfd}>"$lockfile"
  if ! flock -n "$lockfd"; then
    echo "[issue-lifecycle-orchestrator] ${subdir##*/}: window ロック取得失敗 — スキップ" >&2
    exec {lockfd}>&-
    return 0
  fi

  tmux kill-window -t "$window_name" 2>/dev/null || true
  mkdir -p "${subdir}/OUT"

  local max_rounds="" specialists="" depth="" policy_qflag="" target_repo=""
  _extract_policies_fields "$subdir" max_rounds specialists depth policy_qflag target_repo

  local prompt_file=""
  _build_worker_prompt "$subdir" "$max_rounds" "$specialists" "$depth" "$policy_qflag" "$target_repo" prompt_file

  # flock 解放（cld-spawn 前）
  exec {lockfd}>&-

  _spawn_tmux_window_with_prompt "$subdir" "$window_name" "$prompt_file"
}

# =============================================================================
# ポーリング（バッチ完了待ち）
# =============================================================================

wait_for_batch() {
  local -a batch_subdirs=("$@")
  local poll_count=0

  while true; do
    local all_done=true
    local current_ts
    current_ts=$(date +%s)

    for subdir in "${batch_subdirs[@]}"; do
      local report_file="${subdir}/OUT/report.json"

      if [[ ! -f "$report_file" ]]; then
        local window_name
        window_name="$(window_name_for_subdir "$subdir")"
        if ! tmux list-windows -F '#{window_name}' 2>/dev/null | grep -qxF "$window_name"; then
          # Window 消失 → fallback report.json 生成 (#647)
          echo "[issue-lifecycle-orchestrator] ${subdir##*/}: ウィンドウ消失・report.json なし — フォールバック生成" >&2
          mkdir -p "${subdir}/OUT"
          _generate_fallback_report "$subdir" "window_lost"
        else
          local inject_count_file="${subdir}/.inject_count"
          local inject_count=0
          [[ -f "$inject_count_file" ]] && inject_count=$(cat "$inject_count_file" 2>/dev/null | tr -d '[:space:]')
          [[ "$inject_count" =~ ^[0-9]+$ ]] || inject_count=0

          # inject 後の progressive delay をタイムスタンプで非ブロッキング skip (#717)
          local last_inject_ts_file="${subdir}/.last_inject_ts"
          if [[ -f "$last_inject_ts_file" ]]; then
            local last_inject_ts
            last_inject_ts=$(cat "$last_inject_ts_file" 2>/dev/null | tr -d '[:space:]')
            local inject_delay=$((5 * inject_count))
            if [[ "$last_inject_ts" =~ ^[0-9]+$ ]] && \
               [[ $((current_ts - last_inject_ts)) -lt $inject_delay ]]; then
              all_done=false
              continue
            fi
          fi

          # 非ブロッキング状態チェック — 旧: serial な wait --timeout 10 を置換 (#717)
          local pane_state
          pane_state=$("${SCRIPTS_ROOT}/../../session/scripts/session-state.sh" state "$window_name" 2>/dev/null)
          local debounce_ts_file="${subdir}/.debounce_ts"

          if [[ "$pane_state" == "input-waiting" ]]; then
            # タイムスタンプ debounce — transient false positive 排除 (#722, #717)
            local debounce_ts=""
            [[ -f "$debounce_ts_file" ]] && debounce_ts=$(cat "$debounce_ts_file" 2>/dev/null | tr -d '[:space:]')
            if ! [[ "$debounce_ts" =~ ^[0-9]+$ ]]; then
              echo "$current_ts" > "$debounce_ts_file"
              all_done=false
              continue
            fi
            if [[ $((current_ts - debounce_ts)) -lt 10 ]]; then
              all_done=false
              continue
            fi
            # debounce 通過: STATE ファイルを確認して判断 (#672)
            local state_file="${subdir}/STATE"
            local current_state=""
            [[ -f "$state_file" ]] && current_state=$(cat "$state_file" 2>/dev/null | tr -d '[:space:]')

            if [[ "$current_state" == "done" || "$current_state" == "failed" || "$current_state" == "circuit_broken" ]]; then
              # terminal state → fallback 生成 + kill (#697)
              local reason="input_waiting_terminal_${current_state}"
              echo "[issue-lifecycle-orchestrator] ${subdir##*/}: input-waiting (STATE=$current_state terminal) — フォールバック生成" >&2
              mkdir -p "${subdir}/OUT"
              _generate_fallback_report "$subdir" "$reason"
              tmux kill-window -t "$window_name" 2>/dev/null || true
            elif [[ "$inject_count" -lt 5 ]]; then
              # inject 直前再確認 — 状態が変化していれば inject をスキップ (#709)
              local _pre_inject_state
              _pre_inject_state=$("${SCRIPTS_ROOT}/../../session/scripts/session-state.sh" state "$window_name" 2>/dev/null)
              if [[ "$_pre_inject_state" != "input-waiting" ]]; then
                all_done=false
                continue
              fi
              # non-terminal + input-waiting → auto-inject で継続を促す (#672, #697, #709)
              inject_count=$((inject_count + 1))
              echo "$inject_count" > "$inject_count_file"
              echo "$current_ts" > "$last_inject_ts_file"
              rm -f "$debounce_ts_file"
              local inject_msg="処理を続行してください。"
              echo "[issue-lifecycle-orchestrator] ${subdir##*/}: STATE=$current_state + input-waiting — auto-inject ($inject_count/5)" >&2
              "${SCRIPTS_ROOT}/../../session/scripts/session-comm.sh" inject "$window_name" \
                "$inject_msg" \
                2>/dev/null || true
              all_done=false
            else
              # inject 5 回失敗 → fallback (#647, #709)
              local reason="inject_exhausted_${inject_count}"
              echo "[issue-lifecycle-orchestrator] ${subdir##*/}: inject exhausted (STATE=$current_state, inject=$inject_count) — フォールバック生成" >&2
              mkdir -p "${subdir}/OUT"
              _generate_fallback_report "$subdir" "$reason"
              tmux kill-window -t "$window_name" 2>/dev/null || true
            fi
          else
            rm -f "$debounce_ts_file"
            all_done=false
          fi
        fi
      fi
    done

    if [[ "$all_done" == "true" ]]; then
      break
    fi

    poll_count=$((poll_count + 1))
    if [[ "$poll_count" -ge "$MAX_POLL" ]]; then
      echo "[issue-lifecycle-orchestrator] バッチタイムアウト（${MAX_POLL}回×${POLL_INTERVAL}秒）" >&2
      for subdir in "${batch_subdirs[@]}"; do
        local report_file="${subdir}/OUT/report.json"
        if [[ ! -f "$report_file" ]]; then
          mkdir -p "${subdir}/OUT"
          printf '{"status":"timeout","error":"poll_limit_reached"}\n' > "$report_file"
          local window_name
          window_name="$(window_name_for_subdir "$subdir")"
          tmux kill-window -t "$window_name" 2>/dev/null || true
        fi
      done
      break
    fi

    sleep "$POLL_INTERVAL"
  done
}

# =============================================================================
# バッチ実行ループ
# =============================================================================

echo "[issue-lifecycle-orchestrator] 開始: ${TOTAL} subdirs を MAX_PARALLEL=${MAX_PARALLEL} でバッチ処理"

COMPLETED=0
BATCH_START=0
OVERALL_FAILED=0

while [[ "$BATCH_START" -lt "$TOTAL" ]]; do
  local_batch=()
  for (( i=BATCH_START; i<TOTAL && i<BATCH_START+MAX_PARALLEL; i++ )); do
    local_batch+=("${SUBDIRS[$i]}")
  done

  echo "[issue-lifecycle-orchestrator] バッチ開始: インデックス ${BATCH_START}~$((BATCH_START+${#local_batch[@]}-1)) (${#local_batch[@]} subdirs)"

  for subdir in "${local_batch[@]}"; do
    spawn_session "$subdir" || continue
  done

  wait_for_batch "${local_batch[@]}"

  COMPLETED=$((COMPLETED + ${#local_batch[@]}))
  BATCH_START=$((BATCH_START + MAX_PARALLEL))

  for subdir in "${local_batch[@]}"; do
    window_name="$(window_name_for_subdir "$subdir")"
    tmux kill-window -t "$window_name" 2>/dev/null || true
  done

  # audit_snapshot fallback: Worker が snapshot を書かなかった場合に orchestrator 側で保全
  for subdir in "${local_batch[@]}"; do
    if [[ "${TWL_AUDIT:-}" == "1" ]]; then
      _snap_label="co-issue/$(basename "$subdir")"
      python3 -m twl.autopilot.audit snapshot \
        --source-dir "$subdir" --label "$_snap_label" 2>/dev/null || true
    fi
  done

  echo "[issue-lifecycle-orchestrator] バッチ完了: ${COMPLETED}/${TOTAL} subdirs 処理済み"
done

# =============================================================================
# 結果サマリー
# =============================================================================

echo ""
echo "✓ issue-lifecycle-orchestrator 完了: ${TOTAL} subdirs"
echo "  per-issue-dir: ${PER_ISSUE_DIR}"

SUCCESS=0
FAILED=0

for subdir in "${SUBDIRS[@]}"; do
  report_file="${subdir}/OUT/report.json"
  subdir_name="${subdir##*/}"
  if [[ -f "$report_file" ]]; then
    status="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('status','unknown'))" "$report_file" 2>/dev/null || echo "parse_error")"
    if [[ "$status" == "done" ]]; then
      SUCCESS=$((SUCCESS + 1))
      echo "  ✓  ${subdir_name}: done"
    else
      FAILED=$((FAILED + 1))
      OVERALL_FAILED=$((OVERALL_FAILED + 1))
      echo "  ⚠️  ${subdir_name}: ${status}"
    fi
  else
    FAILED=$((FAILED + 1))
    OVERALL_FAILED=$((OVERALL_FAILED + 1))
    echo "  ✗  ${subdir_name}: report.json なし"
  fi
done

echo ""
echo "  成功: ${SUCCESS}/${TOTAL}, 失敗: ${FAILED}/${TOTAL}"

if [[ "$OVERALL_FAILED" -gt 0 ]]; then
  exit 1
fi
exit 0
