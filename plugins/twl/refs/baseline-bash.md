---
name: twl:baseline-bash
description: |
  Bash スクリプト品質基準。character class、変数スコープ、set -u 初期化のBAD/GOOD対比。
type: reference
disable-model-invocation: true
---

# Bash Baseline

## 1. Character Class のハイフン配置

bash の character class でハイフン `-` を中間に配置すると範囲指定と誤解され、意図しない文字が欠落するリスクがある。

### BAD: ハイフンが中間（範囲指定と誤解される）

```bash
# BAD: ハイフンが中間 — 範囲指定と誤解されるリスク
[a-z_.-Z0-9]    # .-Z が ASCII 46〜90 の範囲と解釈される可能性
[a-zA-Z0-9/_.-]  # - が . と A の間に入り . から A の ASCII 範囲を指定
```

### GOOD: ハイフンを末尾または先頭に配置

```bash
# GOOD: ハイフンを末尾に配置（ドット `.` はどこでも安全）
[[ "$branch" =~ ^[a-zA-Z0-9/_.−]+$ ]]   # 末尾に配置

# GOOD: ハイフンを末尾に配置（ブランチ名バリデーション）
[[ "$input" =~ ^[a-zA-Z0-9/_.-]+$ ]]    # ハイフンを末尾に配置

# GOOD: バックスラッシュでエスケープ
[[ "$input" =~ ^[a-zA-Z0-9/_.\-]+$ ]]   # バックスラッシュでエスケープ

# GOOD: 先頭に配置
[[ "$input" =~ ^[-a-zA-Z0-9/_.]+$ ]]    # 先頭に配置
```

## 2. for-loop 変数の local 宣言

bash では `for` ループの変数はスコープされないため、呼び出し元の同名変数を破壊するリスクがある。

> **注意**: `local` は bash の関数内でのみ有効。トップレベルスクリプトでは使用できない（`local: can only be used in a function` エラーになる）。

### BAD: local 宣言なし

```bash
# BAD: local 宣言なし — 呼び出し元の同名変数を破壊するリスク
process_items() {
  for item in "${list[@]}"; do
    echo "$item"
  done
}
```

### GOOD: local で宣言してからループ

```bash
# GOOD: local で宣言してからループ（関数内でのみ有効）
process_items() {
  local item
  for item in "${list[@]}"; do
    echo "$item"
  done
}
```

## 3. local 宣言の set -u 初期化

`set -u` 環境で `local var` だけで宣言した変数は未初期化のまま残る。`if` ブロック内でのみ代入される変数が `if` をスキップした場合に `unbound variable` エラーが発生する。

### BAD: set -u 環境で unbound variable エラーになる

```bash
# BAD: set -u 環境で unbound variable エラーになる
process() {
  local result
  if [[ "$condition" == "true" ]]; then
    result="found"
  fi
  echo "$result"  # condition が false なら unbound
}
```

### GOOD: 初期値を指定

```bash
# GOOD: 初期値を指定
process() {
  local result=""
  if [[ "$condition" == "true" ]]; then
    result="found"
  fi
  echo "$result"  # 空文字が出力される（安全）
}
```

## 4. 環境変数パースの IFS 問題

`env | grep` でキー=値を読み込む全ての Bash スクリプトに適用。

### BAD: IFS='=' による分割（値内の = が切り捨てられる）

```bash
# BAD: 値に = を含む場合に切り捨て（DEV_URL=https://host?a=b → val="https://host?a" で b が消失）
while IFS='=' read -r key val; do
    ENV_ARGS+=(--setenv="${key}=${val}")
done < <(env | grep '^DEV_')
```

### GOOD: パラメータ展開で正確にパース

```bash
# GOOD: IFS= で行全体を読み、パラメータ展開で最初の = を基準に分割
while IFS= read -r line; do
    key="${line%%=*}"   # 最初の = より前
    val="${line#*=}"    # 最初の = より後ろ全部
    ENV_ARGS+=(--setenv="${key}=${val}")
done < <(env | grep '^DEV_')
```

## 5. source スクリプトの set -e 制約

`source` で読み込まれるスクリプトに `set -e` / `set -euo pipefail` を付けると、スクリプトが現在のシェル環境で実行されるため、シェルオプションが親シェルに継承される。親シェルが非厳格モード（`set +e`）で動作している場合、`source` 先の `set -e` が親シェル全体を暗黙的に厳格化し、以降のコマンドで意図しない終了を引き起こす。

### BAD: source 想定スクリプトに set -euo pipefail を付ける

```bash
# BAD: source 呼び出し専用スクリプトに set -euo pipefail — 親シェルを暗黙的に厳格化する
set -euo pipefail

setup_env() {
  local tmpdir
  tmpdir=$(mktemp -d)
  git fetch origin
  echo "$tmpdir"
}
```

### GOOD: set -euo pipefail を省略し、個別コマンドにエラーチェックを付ける

```bash
# GOOD: set -euo pipefail を省略し、個別コマンドに明示的なエラーチェックを付ける
# （親シェルのエラーハンドリング設定を汚染しない）

setup_env() {
  local tmpdir
  tmpdir=$(mktemp -d) || return 1
  git fetch origin || return 1
  echo "$tmpdir"
}
```

### GOOD: サブシェルで厳格モードを局所化する

```bash
# GOOD: サブシェル内で set -e を使い、親シェルの設定を汚染しない
run_strict() (
  set -euo pipefail
  git fetch origin
  git merge --ff-only origin/main
)
```

> **補足**: `source` されたスクリプト内では `exit N` ではなく `return N` を使うこと。`exit N` は親シェルごと終了させるため、意図しないセッション終了を引き起こす。

## 6. 複数 regex パターンの ^ アンカー一貫性

同一 input source（tmux pane capture 出力など）に対して複数の `grep -E` / `=~` パターンを並走させる場合、各パターンの `^` 直後の character class（leading-space 許容 or strict）を統一しなければならない。形式が混在すると、あるパターンにはマッチするが別のパターンにはマッチしないという誤分類バグが生じる。

**Why** (PR #949 / Issue #946 / `e3d2f80`): `issue-lifecycle-orchestrator.sh` の F4 修正で、同一 pane 出力に対する Pattern 1 (`^[1-9]\.`) が strict 形式、Pattern 2 (`^[[:space:]]*[1-9][0-9]*[.):])`) が leading-space 許容形式になっており、インデント付き出力で Pattern 1 が不一致 → Pattern 2 が誤分類するバグが発生した。

### BAD: 同一 input への複数 pattern で ^ 直後の形式が異なる

```bash
# BAD: Pattern 1 は strict（先頭スペースを許容しない）
if [[ "$pane_output" =~ ^[1-9]\.\ (Yes,\ proceed|No,\ go\ back) ]]; then
  # → インデント付き出力では不一致

# BAD: Pattern 2 は leading-space 許容（同一 source なのに形式が違う）
elif [[ "$pane_output" =~ ^[[:space:]]*[1-9][0-9]*[.):] ]]; then
  # → スペース付きでもマッチするため、Pattern 1 を抜けたものを誤捕捉する
fi
```

### GOOD: 全パターンを `^[[:space:]]*` 形式で統一（leading-space 許容）

```bash
# GOOD: 両パターンともに leading-space を許容することで一貫性を保つ
if [[ "$pane_output" =~ ^[[:space:]]*[1-9]\.\ (Yes,\ proceed|No,\ go\ back) ]]; then
  : # 正常分岐
elif [[ "$pane_output" =~ ^[[:space:]]*[1-9][0-9]*[.):] ]]; then
  : # menu 検出分岐
fi
```

### GOOD: 全パターンを strict `^` 形式で統一（leading-space を事前除去）

```bash
# GOOD: input を trim してから strict パターンを適用する
trimmed="${pane_output#"${pane_output%%[![:space:]]*}"}"  # 先頭スペース除去
if [[ "$trimmed" =~ ^[1-9]\.\ (Yes,\ proceed|No,\ go\ back) ]]; then
  : # 正常分岐
elif [[ "$trimmed" =~ ^[1-9][0-9]*[.):] ]]; then
  : # menu 検出分岐
fi
```

**レビュー観点**: 同一 input source に対する複数 `grep -E` / `=~` パターンの `^` 直後の character class（`[[:space:]]*` の有無）を比較し、形式が混在している場合は flag する。

## 7. recursive glob (`**`) と globstar 設定

bash の `**` パターン（recursive glob）は `shopt -s globstar` を有効化していなければ通常の `*` と同等に解釈され、ディレクトリを跨いだ再帰展開が行われない。`set -euo pipefail` 環境で `**/*.py` をリテラルパスとして渡した `if grep ... "$DIR"/**/*.py 2>/dev/null; then` 構文では、grep が exit 2（ファイル不在）を返すが `2>/dev/null` でエラーが抑制され、`if` 分岐が偽となって処理がスキップされる（サイレント失敗）。

**Why** (Issue #1081 / `plugins/twl/scripts/tech-stack-detect.sh:54` / commit `6d9bffa`): `tech-stack-detect.sh` で `grep -rql ... "$PROJECT_ROOT"/**/*.py` を `shopt -s globstar` なしに使用しており、リテラルの `**/*.py` パスとして展開されて FastAPI 検出が一切 fire しないバグが顕在化した。`grep -rql --include='*.py' "$pattern" "$PROJECT_ROOT"` 形式へ修正することで再帰探索 + 拡張子フィルタを明示している。

### BAD: globstar 未設定で `**/*.ext` を使う

```bash
# BAD: shopt -s globstar なし — **/*.py がリテラルパスとして展開される
# grep が exit 2（ファイル不在）を返すが 2>/dev/null で抑制 → if 偽分岐でサイレント失敗
if grep -rql 'from fastapi' "$PROJECT_ROOT"/**/*.py 2>/dev/null; then
  LANGUAGE_HINTS["fastapi"]=1
fi
```

### GOOD: `--include` で再帰検索を明示する

```bash
# GOOD: grep -r の再帰探索 + --include で拡張子フィルタ — globstar 設定不要
if grep -rql --include='*.py' 'from fastapi' "$PROJECT_ROOT" 2>/dev/null; then
  LANGUAGE_HINTS["fastapi"]=1
fi
```

### GOOD: `find ... -name '*.ext'` で明示的に列挙する

```bash
# GOOD: find で再帰列挙してから処理する — POSIX 互換、globstar 不要
while IFS= read -r f; do
  : # process "$f"
done < <(find "$PROJECT_ROOT" -type f -name '*.py')
```

### GOOD: 必要な範囲だけ `shopt -s globstar` を局所有効化する（最終手段）

```bash
# GOOD: サブシェル内で globstar を有効化し親シェルへ波及させない
process_py_files() (
  shopt -s globstar nullglob
  for f in "$PROJECT_ROOT"/**/*.py; do
    : # process "$f"
  done
)
```

> `nullglob` の併用も推奨（マッチ 0 件で iterable が空になる挙動を保証）。

**レビュー観点**: bash スクリプトで `$VAR/**/*.ext` 形式の glob 展開を見つけた場合、同ファイル内（または source 元のスクリプト）で `shopt -s globstar` が有効化されているかを確認する。未設定であれば、`grep -rql --include='*.ext' ... "$DIR"` または `find "$DIR" -name '*.ext'` への置換を提案する。

## 8. tmux 破壊的操作のターゲット解決

`tmux kill-window` / `kill-session` 等の destructive op に window 名のみを直接 `-t` で渡すと、複数 session に同名 window が存在する場合に ambiguous target または誤 kill が発生する。

### BAD: tmux kill-window で window 名を直接 -t に渡す（ambiguous target リスク）

```bash
# BAD: 複数 session に同名 window があると誤 kill
WIN="wt-target"
tmux kill-window -t "$WIN"
```

### GOOD: session:index 形式に解決してから kill

```bash
# GOOD: list-windows -a で session:index に解決
WIN="wt-target"
RESOLVED=$(tmux list-windows -a -F '#{session_name}:#{window_index} #{window_name}' \
  | awk -v n="$WIN" '$2==n {print $1}')
if [[ -n "$RESOLVED" ]] && [[ $(echo "$RESOLVED" | wc -l) -eq 1 ]]; then
  tmux kill-window -t "$RESOLVED"
fi
```

または共通ヘルパー（Issue #1142 で `plugins/session/scripts/lib/tmux-resolve.sh::_resolve_window_target` 提供予定）を使用する。先行 ref: pitfalls-catalog `§4.11 tmux 破壊的操作のターゲット解決`（Issue #1142）、`§4.9 has-session 誤用`（Issue #948）。

**適用範囲**: `tmux kill-server` / `tmux -C` / `tmux -f` はホスト共通 CLAUDE.md（incident 2026-04-22）+ PreToolUse hook で別途ブロック済み。本パターンは destructive な window/session レベル op に focus する。

**レビュー観点**: `tmux kill-window`、`kill-session`、`respawn-window` 等の destructive op で `-t "$WIN_NAME"` や `-t "${WINDOW}"` のように window 名変数を直接渡している箇所を見つけた場合、`#{session_name}:#{window_index}` 形式への解決が行われているかを確認する。解決なしは CRITICAL（confidence ≥ 90）として報告する。

## 9. bats heredoc 内変数展開

bats テストで外部変数を参照する heredoc を書く際、シングルクォート heredoc `<<'EOF'` は **parent shell で変数展開されない**。bats 由来の環境変数（`$BATS_TEST_FILENAME` 等）を heredoc 内で直接参照すると、子 bash プロセスは bats 環境変数を持たないため未定義となり意図しない動作が発生する（例: `cd ""/../scripts` として誤動作）。

### BAD: シングルクォート heredoc 内で外部変数を参照

```bash
# BAD: <<'MOCKEOF' はシングルクォート heredoc — 親シェルで変数展開されない
# $BATS_TEST_FILENAME は子 bash プロセスに展開されないため cd が失敗する
run bash <<'MOCKEOF'
SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
source "$SCRIPT_DIR/target.sh"
MOCKEOF
```

### GOOD: ダブルクォート（非クォート）heredoc で展開を許可

```bash
# GOOD: <<EOF（クォートなし）— 親シェルで変数展開されるため外部変数が解決される
THIS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
run bash <<EOF
SCRIPT_DIR="${THIS_DIR}/../scripts"
source "\$SCRIPT_DIR/target.sh"
EOF
```

### GOOD: 外部変数を明示 export して子プロセスに渡す

```bash
# GOOD: EXT_VAR=$EXT_VAR bash <<'EOF' パターン — 外部変数を明示 export し、
# シングルクォート heredoc 内でも安全に参照できる
THIS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
THIS_DIR=$THIS_DIR run bash <<'MOCKEOF'
SCRIPT_DIR="$(cd "$THIS_DIR/../scripts" && pwd)"
source "$SCRIPT_DIR/target.sh"
MOCKEOF
```

**レビュー観点**: bats テスト内で `run bash <<'EOF'` 等のシングルクォート heredoc を見つけた場合、heredoc 内で `$BATS_TEST_FILENAME`、`$BATS_TEST_TMPDIR` 等の bats 由来の外部変数を参照していないかを確認する。参照している場合は展開されない（空文字または未定義）ため、非クォート heredoc への変換、または `VAR=$VAR bash <<'EOF'` パターンへの修正を提案する。

## 10. source 対象スクリプトの guard / function-only load mode

bats テストで `source "$SCRIPT"` によって関数のみをロードしようとする場合、対象スクリプトが `set -euo pipefail` + 引数解析 + `exit 1` の main 部を持つと、source 時点で main 実行に到達し parent shell が exit する。`set -euo pipefail` 環境では引数不足で即 exit し、対象関数定義に到達せず **set -euo pipefail で exit に巻き込まれる**。

### BAD: guard なし — source 時に main 部が実行されて exit に巻き込まれる

```bash
# BAD: source 先スクリプトに guard なし
# bats から source すると main 実行が parent shell（bats）の exit を引き起こす
#!/usr/bin/env bash
set -euo pipefail

MY_VAR="${1:?usage: script.sh <arg>}"  # source 時に exit 1

my_function() { echo "hello $MY_VAR"; }

my_function "$@"  # main 到達前に return できない
```

### GOOD: BASH_SOURCE guard で main を条件実行

```bash
# GOOD: BASH_SOURCE guard — source 時は main をスキップし関数定義のみロードされる
#!/usr/bin/env bash
set -euo pipefail

my_function() { echo "hello $1"; }

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  my_function "$@"   # 直接実行時のみ main を呼ぶ
fi
```

### GOOD: --source-only フラグで function-only load mode を実装

```bash
# GOOD: _DAEMON_LOAD_ONLY パターン — source 時は main 到達前に return する
#!/usr/bin/env bash
set -euo pipefail

my_function() { echo "hello $1"; }

# source-only モード: main をスキップして関数定義のみロードする
if [[ "${_DAEMON_LOAD_ONLY:-0}" == "1" ]] || [[ "${1:-}" == "--source-only" ]]; then
  return 0 2>/dev/null || exit 0
fi

my_function "$@"
```

**レビュー観点**: bats テストで `source "$TARGET_SCRIPT"` を生成する場合、対象スクリプトを Grep して `BASH_SOURCE` guard または `--source-only` / `_DAEMON_LOAD_ONLY` pattern が存在するかを確認する。不在の場合は `set -euo pipefail` + 引数解析で **main 到達前に exit に巻き込まれる** リスクがあるため、`impl_files` メモにフラグ追加要求を記載する。

## 11. bash スクリプトの入力検証: allowlist regex による入力バリデーション規約

bash スクリプトでパス・識別子・列挙値を受け取る場合、**allowlist regex 方式**（許可されたパターンのみを受理）を採用する。blocklist 方式（禁止パターンを列挙して除外）は採用しない。

### 規約

> **bash スクリプトの入力検証（パス・識別子・列挙値）は allowlist regex 方式を採用する。**

入力が allowlist パターンに **一致しない** 場合は即座にエラー終了する（fail-closed）。

### パターン例

#### 数値（正整数）

```bash
# GOOD: allowlist — 正整数のみ受理
if [[ ! "$ISSUE_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
  echo "Error: invalid issue number: ${ISSUE_NUMBER}" >&2; exit 1
fi
```

パターン: `^[1-9][0-9]*$`

#### 安全パス（ディレクトリ名・ファイル名）

```bash
# GOOD: allowlist — 英数字・ドット・ハイフン・アンダースコア・スラッシュのみ受理
if [[ ! "$WORK_DIR" =~ ^[A-Za-z0-9._/-]+$ ]]; then
  echo "Error: invalid path: ${WORK_DIR}" >&2; exit 1
fi
```

パターン: `^[A-Za-z0-9._/-]+$`

#### 列挙値（case 文による allowlist）

```bash
# GOOD: case 文で許可値を列挙し、それ以外を reject
case "$SEVERITY" in
  low|medium|high) ;;
  *) echo "Error: invalid severity: ${SEVERITY}" >&2; exit 1 ;;
esac
```

#### 識別子（リポジトリ名など）

```bash
# GOOD: allowlist — owner/repo 形式のみ受理
if [[ ! "$ISSUE_REPO" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then
  echo "Error: invalid repo: ${ISSUE_REPO}" >&2; exit 1
fi
```

### blocklist 方式との比較

| 観点 | allowlist | blocklist |
|---|---|---|
| 境界値網羅 | 許可パターン外はすべて拒否（fail-closed） | 禁止パターン漏れが許可になる（fail-open） |
| 新攻撃面への耐性 | 新しいインジェクション手法も自動排除 | 新手法が禁止リストに含まれるまで脆弱 |
| コードの明示性 | 許可仕様が regex 1行で表現可能 | 禁止パターンが増殖し管理困難 |

**Why fail-closed が重要か**: blocklist は「既知の危険パターン」を列挙するため、想定外の入力（例: Unicode エスケープ、新しいシェル特殊文字）が許可される。allowlist は「許可されたパターン以外すべて拒否」するため、未知の攻撃面に対しても安全性が保たれる。

### BAD: blocklist 方式（採用禁止）

```bash
# BAD: blocklist — 禁止パターンを列挙。網羅性が保証されない
if [[ "$_dir" == *..* ]]; then
  echo "Error: path traversal detected" >&2; exit 1
fi
if [[ "$_dir" =~ ^/ ]]; then
  echo "Error: absolute path not allowed" >&2; exit 1
fi
if [[ "$_dir" =~ [$\;\|\`\&\(\)\<\>] ]]; then
  echo "Error: forbidden characters" >&2; exit 1
fi
# → '$'、';'、'|'、'`' などを列挙しても新しい特殊文字が抜ける可能性がある
```

### Prior art: spawn-controller.sh の allowlist 実装

`plugins/twl/skills/su-observer/scripts/spawn-controller.sh` は allowlist 方式の実装例:

**L167: `CHAIN_ISSUE` regex バリデーション（正整数 allowlist）**

```bash
if [[ ! "$CHAIN_ISSUE" =~ ^[1-9][0-9]*$ ]]; then
  echo "Error: --issue の値は正整数である必要があります: ${CHAIN_ISSUE}" >&2
  exit 2
fi
```

**L84: `VALID_SKILLS` 配列宣言 + L113-125: バリデーションループ（列挙値 allowlist）**

```bash
VALID_SKILLS=(co-explore co-issue co-architect co-autopilot co-project co-utility co-self-improve)

SKILL_FOUND=false
for s in "${VALID_SKILLS[@]}"; do
  if [[ "$SKILL_NORMALIZED" == "$s" ]]; then
    SKILL_FOUND=true
    break
  fi
done
if [[ "$SKILL_FOUND" == "false" ]]; then
  echo "Error: invalid skill name '$SKILL'." >&2
  exit 2
fi
```

### blocklist 方式の棚卸し（2026-05-04 時点）

以下のスクリプトで blocklist 方式または mixed 方式（allowlist と blocklist の混在）が確認された。後続 Issue で allowlist 方式への置換を検討する:

| ファイル | 箇所 | 内容 |
|---|---|---|
| `plugins/twl/skills/su-observer/scripts/record-detection-gap.sh` | L61-69 | `SUPERVISOR_DIR`: `*..* ` / `^/` / 禁止文字 reject の blocklist 3段階チェック（PR #1345 導入）|
| `plugins/twl/scripts/worktree-delete.sh` | L25 | `branch`: `\.\.` / `^/` blocklist + `^[a-zA-Z0-9/_.-]+$` allowlist の混在 |
| `plugins/twl/skills/su-observer/scripts/session-init.sh` | L11 | `SUPERVISOR_DIR`: allowlist `^[a-zA-Z0-9._/=-]+$` + 追加 `*..* ` blocklist の混在 |
| `plugins/twl/skills/su-observer/scripts/step0-monitor-bootstrap.sh` | L18 | `SUPERVISOR_DIR`: allowlist `^[a-zA-Z0-9./_-]+$` + `*..* ` blocklist の混在 |

**対応方針**: `record-detection-gap.sh` の SUPERVISOR_DIR は純粋 blocklist のため優先度高。mixed 方式は allowlist で網羅できているため blocklist 部分を削除するだけで改善可能。
