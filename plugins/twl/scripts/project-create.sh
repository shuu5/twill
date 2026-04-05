#!/bin/bash
# project-create.sh
# プロジェクトを新規作成（タイプ別テンプレート対応）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# パス設定
TEMPLATES_BASE="$HOME/.claude/templates"
SCRIPTS_DIR="$HOME/.claude/scripts"

# deltaspec init 後のプロジェクトローカル opsx クリーンアップ
cleanup_openspec_local() {
    local project_dir="$1"
    # プロジェクトローカル opsx コマンドを削除（グローバルに委譲）
    if [ -d "$project_dir/.claude/commands/opsx" ]; then
        rm -rf "$project_dir/.claude/commands/opsx"
        echo "   ✓ プロジェクトローカル opsx コマンドを削除（グローバルに委譲）"
    fi
    # プロジェクトローカル openspec スキルを削除（deltaspec移行済み）
    local found=false
    for dir in "$project_dir"/.claude/skills/openspec-*/; do
        if [ -d "$dir" ]; then
            rm -rf "$dir"
            found=true
        fi
    done
    if [ "$found" = true ]; then
        echo "   ✓ プロジェクトローカル openspec スキルを削除（deltaspec移行済み）（グローバルに委譲）"
    fi
}

# Project Board フィールド作成ヘルパー
create_board_field() {
    local project_id="$1" field_name="$2"
    gh api graphql -f query='
        mutation($projectId: ID!, $name: String!) {
            createProjectV2Field(input: {projectId: $projectId, dataType: SINGLE_SELECT, name: $name}) {
                projectV2Field { ... on ProjectV2SingleSelectField { id name } }
            }
        }
    ' -f projectId="$project_id" -f name="$field_name" >/dev/null 2>&1 \
        && echo "   フィールド作成: $field_name (SingleSelect)" \
        || echo "   警告: $field_name フィールド作成に失敗しました" >&2
}

# Project Board 初期設定（set -e 安全: 全 API 呼び出しを || true でガード）
setup_project_board() {
    local github_user="$1" project_name="$2"

    # project スコープ確認
    if ! gh project list --owner @me --limit 1 >/dev/null 2>&1; then
        echo "   ⚠️ gh トークンに project スコープがありません" >&2
        echo "   以下を実行してスコープを追加してください:" >&2
        echo "     gh auth refresh -s project" >&2
        return 0
    fi

    # リポジトリ node ID 取得
    local repo_node_id
    repo_node_id=$(gh api graphql -f query='
        query($owner: String!, $name: String!) {
            repository(owner: $owner, name: $name) { id }
        }
    ' -f owner="$github_user" -f name="$project_name" \
        --jq '.data.repository.id' 2>/dev/null) || true
    if [ -z "$repo_node_id" ]; then
        echo "   警告: リポジトリ情報の取得に失敗しました" >&2
        return 0
    fi

    # オーナー node ID 取得
    local owner_id
    owner_id=$(gh api graphql -f query='
        query($login: String!) {
            user(login: $login) { id }
        }
    ' -f login="$github_user" \
        --jq '.data.user.id' 2>/dev/null) || true
    if [ -z "$owner_id" ]; then
        echo "   警告: GitHub ユーザー情報の取得に失敗しました" >&2
        return 0
    fi

    # Project V2 Board 作成
    local project_data board_project_id
    project_data=$(gh api graphql -f query='
        mutation($ownerId: ID!, $title: String!) {
            createProjectV2(input: {ownerId: $ownerId, title: $title}) {
                projectV2 { id number url }
            }
        }
    ' -f ownerId="$owner_id" -f title="$project_name" 2>/dev/null) || true

    if ! command -v jq &>/dev/null; then
        echo "   警告: jq が見つかりません。Board フィールド設定をスキップします" >&2
        return 0
    fi

    board_project_id=$(echo "$project_data" | jq -r '.data.createProjectV2.projectV2.id // empty')
    BOARD_URL=$(echo "$project_data" | jq -r '.data.createProjectV2.projectV2.url // empty')

    if [ -z "$board_project_id" ]; then
        echo "   警告: Project Board の作成に失敗しました" >&2
        return 0
    fi

    echo "   Board作成: $BOARD_URL"

    # リポジトリリンク
    gh api graphql -f query='
        mutation($projectId: ID!, $repositoryId: ID!) {
            linkProjectV2ToRepository(input: {projectId: $projectId, repositoryId: $repositoryId}) {
                repository { id }
            }
        }
    ' -f projectId="$board_project_id" -f repositoryId="$repo_node_id" >/dev/null 2>&1 \
        && echo "   リポジトリリンク: 完了" \
        || echo "   警告: リポジトリリンクに失敗しました" >&2

    # クロスリポジトリ: ADDITIONAL_REPOS が設定されている場合、追加リポジトリもリンク
    # ADDITIONAL_REPOS は "owner/name" のスペース区切りリスト
    for add_repo in ${ADDITIONAL_REPOS:-}; do
        # owner/repo フォーマット検証（インジェクション防止）
        if [[ ! "$add_repo" =~ ^[a-zA-Z0-9_-]+/[a-zA-Z0-9_.-]+$ ]]; then
            echo "   警告: 不正なリポジトリ形式をスキップ: $add_repo" >&2
            continue
        fi
        local add_owner="${add_repo%%/*}"
        local add_name="${add_repo#*/}"
        local add_repo_id
        add_repo_id=$(gh api graphql -f query='
            query($owner: String!, $name: String!) {
                repository(owner: $owner, name: $name) { id }
            }
        ' -f owner="$add_owner" -f name="$add_name" \
            --jq '.data.repository.id' 2>/dev/null) || true
        if [ -n "$add_repo_id" ]; then
            gh api graphql -f query='
                mutation($projectId: ID!, $repositoryId: ID!) {
                    linkProjectV2ToRepository(input: {projectId: $projectId, repositoryId: $repositoryId}) {
                        repository { id }
                    }
                }
            ' -f projectId="$board_project_id" -f repositoryId="$add_repo_id" >/dev/null 2>&1 \
                && echo "   追加リポジトリリンク: ${add_repo} 完了" \
                || echo "   警告: ${add_repo} リンクに失敗しました" >&2
        else
            echo "   警告: リポジトリ ${add_repo} の情報取得に失敗しました" >&2
        fi
    done

    # カスタムフィールド作成
    create_board_field "$board_project_id" "Context"
    create_board_field "$board_project_id" "Phase"
}

# プロジェクトルート解決
resolve_project_root() {
    local type="$1"
    local explicit_root="$2"
    if [ -n "$explicit_root" ]; then echo "$explicit_root"; return; fi
    case "$type" in
        webapp-llm|webapp-hono) echo "${WEBAPP_PROJECTS_ROOT:-$HOME/projects}" ;;
        rnaseq)                 echo "${OMICS_PROJECTS_ROOT:-$HOME/projects}" ;;
        *)                      echo "${PROJECTS_ROOT:-$HOME/projects}" ;;
    esac
}

# 継承関係マップ
# 3タイプ設計: rnaseq（学術解析）、webapp-llm（LLMアプリ/FastAPI）、webapp-hono（LLMアプリ/Hono）
declare -A TYPE_INHERITANCE=(
    ["rnaseq"]=""
    ["webapp-llm"]=""
    ["webapp-hono"]=""
)

# 利用可能なタイプ
AVAILABLE_TYPES="rnaseq, webapp-llm, webapp-hono"

# 引数解析
PROJECT_NAME=""
PROJECT_TYPE=""
PROJECT_ROOT=""
NO_GITHUB=false
BOARD_URL=""

show_help() {
    echo "使用方法: /twl:project-create <project-name> [--type <type>] [--root <path>] [--no-github]"
    echo ""
    echo "オプション:"
    echo "  --type <type>  プロジェクトタイプ: $AVAILABLE_TYPES"
    echo "  --root <path>  プロジェクトルートパス（デフォルト: タイプ別）"
    echo "  --no-github    GitHubリポジトリを作成しない"
    echo ""
    echo "タイプの継承関係:"
    echo "  # 学術プロジェクト系"
    echo "  rnaseq → （R/Python環境 + RNA-seq固有）"
    echo ""
    echo "  # Webアプリ系"
    echo "  webapp-llm  → （LLM統合 + FastAPI + Supabase）"
    echo "  webapp-hono → （LLM統合 + Hono/Bun + Zod SSoT + Supabase）★推奨"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --type)
            PROJECT_TYPE="$2"
            shift 2
            ;;
        --root)
            PROJECT_ROOT="$2"
            shift 2
            ;;
        --no-github)
            NO_GITHUB=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            if [ -z "$PROJECT_NAME" ]; then
                PROJECT_NAME="$1"
            fi
            shift
            ;;
    esac
done

# 入力検証
if [ -z "$PROJECT_NAME" ]; then
    echo "エラー: プロジェクト名を指定してください"
    show_help
    exit 1
fi

# プロジェクト名の検証（英数字とハイフンのみ）
if ! echo "$PROJECT_NAME" | grep -qE '^[a-z0-9][a-z0-9-]*[a-z0-9]$|^[a-z0-9]$'; then
    echo "エラー: プロジェクト名は英小文字、数字、ハイフンのみ使用可能です"
    exit 1
fi

# タイプ検証
if [ -n "$PROJECT_TYPE" ]; then
    if [ ! -d "$TEMPLATES_BASE/$PROJECT_TYPE" ]; then
        echo "エラー: 不明なプロジェクトタイプ: $PROJECT_TYPE"
        echo "利用可能なタイプ: $AVAILABLE_TYPES"
        exit 1
    fi
fi

# プロジェクトルート解決
PROJECTS_DIR=$(resolve_project_root "$PROJECT_TYPE" "$PROJECT_ROOT")
PROJECT_DIR="$PROJECTS_DIR/$PROJECT_NAME"
MAIN_DIR="$PROJECT_DIR/main"

# ルートディレクトリ存在確認
if [ ! -d "$PROJECTS_DIR" ]; then
    echo "プロジェクトルートを作成: $PROJECTS_DIR"
    mkdir -p "$PROJECTS_DIR"
fi

# 既存チェック
if [ -d "$PROJECT_DIR" ]; then
    echo "エラー: プロジェクト '$PROJECT_NAME' は既に存在します: $PROJECT_DIR"
    exit 1
fi

echo "=== プロジェクト作成開始: $PROJECT_NAME ==="
[ -n "$PROJECT_TYPE" ] && echo "タイプ: $PROJECT_TYPE"
echo "ルート: $PROJECTS_DIR"

# 1. プロジェクトディレクトリ作成
echo "1. プロジェクトディレクトリを作成..."
mkdir -p "$PROJECT_DIR"

# 2. bare gitリポジトリ初期化（.bare + .git ポインタファイル方式）
echo "2. Gitリポジトリを初期化..."
git init --bare "$PROJECT_DIR/.bare"
echo "gitdir: .bare" > "$PROJECT_DIR/.git"

# 3. main worktree作成
echo "3. main worktreeを作成..."
git -C "$PROJECT_DIR/.bare" worktree add "$MAIN_DIR" -b main --orphan

# 4. .claudeディレクトリ構造作成
echo "4. .claudeディレクトリを作成..."
mkdir -p "$MAIN_DIR/.claude"

# 5. テンプレートコピー（階層的マージ）
echo "5. テンプレートファイルをコピー..."

# CLAUDE.mdの内容を連結するための一時ファイル
CLAUDE_MD_CONTENT=""

# コピー関数（ディレクトリの内容をマージ）
copy_template_layer() {
    local layer_dir="$1"
    local dest_dir="$2"

    if [ ! -d "$layer_dir" ]; then
        return
    fi

    echo "   レイヤー: $layer_dir"

    # CLAUDE.md以外のファイル/ディレクトリをコピー
    for item in "$layer_dir"/*; do
        [ ! -e "$item" ] && continue
        local basename=$(basename "$item")

        if [ "$basename" = "CLAUDE.md" ]; then
            # CLAUDE.mdは連結
            if [ -f "$item" ]; then
                CLAUDE_MD_CONTENT+="$(cat "$item")"$'\n\n'
            fi
        elif [ -d "$item" ]; then
            # ディレクトリはコピー（agents/commands/rulesは除外：ユーザースコープで管理）
            if [ "$basename" != "agents" ] && [ "$basename" != "commands" ] && [ "$basename" != "rules" ]; then
                cp -r "$item" "$dest_dir/" 2>/dev/null || true
            fi
        else
            # ファイルはコピー（上書き）
            cp "$item" "$dest_dir/" 2>/dev/null || true
        fi
    done

    # 隠しファイルもコピー（CLAUDE.md除く）
    for item in "$layer_dir"/.[!.]*; do
        [ ! -e "$item" ] && continue
        local basename=$(basename "$item")
        if [ "$basename" != ".claude" ]; then
            cp -r "$item" "$dest_dir/" 2>/dev/null || true
        fi
    done
}

# 継承チェーンを構築
build_inheritance_chain() {
    local type="$1"
    local chain=()

    if [ -n "$type" ]; then
        # 親タイプを探す
        local parent="${TYPE_INHERITANCE[$type]:-}"
        if [ -n "$parent" ]; then
            chain+=("$parent")
        fi
        # 指定されたタイプ
        chain+=("$type")
    fi

    echo "${chain[@]}"
}

# 継承チェーンに従ってコピー
INHERITANCE_CHAIN=($(build_inheritance_chain "$PROJECT_TYPE"))
echo "   継承チェーン: ${INHERITANCE_CHAIN[*]}"

for layer in "${INHERITANCE_CHAIN[@]}"; do
    copy_template_layer "$TEMPLATES_BASE/$layer" "$MAIN_DIR"
done

# 連結したCLAUDE.mdを書き込み（ルートに配置、OpenSpec標準に合わせる）
if [ -n "$CLAUDE_MD_CONTENT" ]; then
    # プレースホルダー置換
    echo "$CLAUDE_MD_CONTENT" | sed "s/{{PROJECT_NAME}}/$PROJECT_NAME/g" > "$MAIN_DIR/CLAUDE.md"
fi

# 5.5. テンプレートファイル処理（.template 拡張子のプレースホルダ置換）
echo "5.5. テンプレートファイルを処理..."

if [ -f "$TEMPLATES_BASE/$PROJECT_TYPE/manifest.yaml" ]; then
    echo "   manifest.yaml 検出: リッチテンプレートモード"
fi

# 全 .template ファイルを処理（{{PROJECT_NAME}} を置換）
find "$MAIN_DIR" -name "*.template" -type f 2>/dev/null | while read -r tmpl; do
    output="${tmpl%.template}"
    echo "   処理: $(basename "$tmpl") → $(basename "$output")"
    sed "s/{{PROJECT_NAME}}/$PROJECT_NAME/g" "$tmpl" > "$output"
    rm "$tmpl"
done

# 6. タイプ別の追加処理
if [ "$PROJECT_TYPE" = "rnaseq" ]; then
    echo "6. renv + uv環境を初期化..."
    mkdir -p "$MAIN_DIR/analysis"
    mkdir -p "$MAIN_DIR/data/raw"
    mkdir -p "$MAIN_DIR/data/processed"
    mkdir -p "$MAIN_DIR/results"
    mkdir -p "$MAIN_DIR/R/functions"
    mkdir -p "$MAIN_DIR/tests"

    if [ -f "$SCRIPTS_DIR/init-renv-uv.sh" ]; then
        bash "$SCRIPTS_DIR/init-renv-uv.sh" "$MAIN_DIR"
    fi
else
    echo "6. 基本ディレクトリを作成..."
    mkdir -p "$MAIN_DIR/src"
    mkdir -p "$MAIN_DIR/tests"
fi

# 7. DeltaSpec初期化
echo "7. DeltaSpecを初期化..."
if command -v deltaspec &> /dev/null; then
    cd "$MAIN_DIR"
    # deltaspec はディレクトリ構造のみ作成（init コマンドなし）
    mkdir -p "$MAIN_DIR/openspec/specs" "$MAIN_DIR/openspec/changes"
    echo "   DeltaSpec initialized"
    cleanup_openspec_local "$MAIN_DIR"
else
    echo "   警告: deltaspec CLIが見つかりません"
fi

# 7.5. bare repo rootに.claude symlinkを作成
echo "7.5. bare repo rootに.claude symlinkを作成..."
ln -s main/.claude "$PROJECT_DIR/.claude"
echo "   symlink: $PROJECT_DIR/.claude -> main/.claude"

# 8. 初回コミット
echo "8. 初回コミットを作成..."
cd "$MAIN_DIR"
git add -A
git commit -m "$(cat <<EOF
feat: Initial project setup

- Type: ${PROJECT_TYPE:-generic}
- Template inheritance: ${INHERITANCE_CHAIN[*]}
- Project-specific CLAUDE.md

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"

# 9. GitHub リポジトリ作成
if [ "$NO_GITHUB" = false ]; then
    echo "9. GitHubリポジトリを作成..."
    if command -v gh &> /dev/null && gh auth status &> /dev/null; then
        if gh repo create "$PROJECT_NAME" --private 2>/dev/null; then
            GITHUB_USER=$(gh api user -q .login 2>/dev/null || echo "unknown")
            REPO_URL="https://github.com/$GITHUB_USER/$PROJECT_NAME.git"

            cd "$MAIN_DIR"
            if git remote add origin "$REPO_URL" 2>/dev/null; then
                if git push -u origin main 2>/dev/null; then
                    echo "   リポジトリ作成完了: https://github.com/$GITHUB_USER/$PROJECT_NAME"

                    # main ブランチ force push 禁止 (GitHub Rulesets)
                    if [ "$GITHUB_USER" = "unknown" ]; then
                        echo "   警告: GitHub ユーザー名を取得できないため Ruleset 適用をスキップ" >&2
                    else
                        RULESET_ERR=$(gh api "repos/$GITHUB_USER/$PROJECT_NAME/rulesets" --method POST --input - <<'RULESET_EOF' 2>&1 >/dev/null
{"name":"protect-main","target":"branch","enforcement":"active","conditions":{"ref_name":{"include":["refs/heads/main"],"exclude":[]}},"rules":[{"type":"non_fast_forward"}]}
RULESET_EOF
                        ) && echo "   Ruleset適用: main force push 禁止" \
                          || echo "   警告: Ruleset作成に失敗しました: ${RULESET_ERR:-不明なエラー}（後で手動適用可）" >&2
                    fi

                    # 9.5 Project Board 初期設定
                    echo "9.5. Project Boardを初期設定..."
                    setup_project_board "$GITHUB_USER" "$PROJECT_NAME"
                else
                    echo "   警告: pushに失敗しました。後で手動で実行してください:" >&2
                    echo "   cd $MAIN_DIR && git push -u origin main" >&2
                fi
            else
                echo "   警告: remoteの追加に失敗しました（既に存在する可能性）" >&2
            fi
        else
            echo "   警告: GitHubリポジトリの作成に失敗しました（同名リポジトリが存在する可能性）" >&2
        fi
    else
        echo "   警告: gh CLIが認証されていません。手動でリモートを設定してください" >&2
    fi
else
    echo "9. GitHubリポジトリ作成をスキップ（--no-github指定）"
fi

echo ""
echo "=== プロジェクト作成完了 ==="
echo "パス: $MAIN_DIR"
echo "タイプ: ${PROJECT_TYPE:-generic}"
echo "ルート: $PROJECTS_DIR"
if [ -n "${BOARD_URL:-}" ]; then
    echo "Board: $BOARD_URL"
fi
echo ""
echo "次のステップ:"
echo "  cd $MAIN_DIR"
echo "  /twl:controller-issue  # Issue作成"
echo "  /twl:controller-setup  # 直接開発開始"
if [ "$PROJECT_TYPE" = "rnaseq" ]; then
    echo ""
    echo "環境セットアップ:"
    echo "  # R環境: renv::restore()"
    echo "  # Python環境: uv sync"
fi
