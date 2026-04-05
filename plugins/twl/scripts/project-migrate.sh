#!/bin/bash
# project-migrate.sh
# 既存プロジェクトを最新テンプレートに移行

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# パス設定
TEMPLATES_BASE="$HOME/.claude/templates"

# deltaspec init 後のプロジェクトローカル opsx クリーンアップ
cleanup_openspec_local() {
    local project_dir="$1"
    if [ -d "$project_dir/.claude/commands/opsx" ]; then
        rm -rf "$project_dir/.claude/commands/opsx"
        echo "   ✓ プロジェクトローカル opsx コマンドを削除（グローバルに委譲）"
    fi
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

# 引数解析
PROJECT_TYPE=""
DRY_RUN=false

show_help() {
    echo "使用方法: /twl:project-migrate [--type <type>] [--dry-run]"
    echo ""
    echo "オプション:"
    echo "  --type <type>  プロジェクトタイプ: rnaseq, webapp-llm, webapp-hono"
    echo "  --dry-run      変更をシミュレーションのみ"
    echo ""
    echo "例:"
    echo "  /twl:project-migrate --dry-run     # 変更内容を確認"
    echo "  /twl:project-migrate --type rnaseq # rnaseqタイプとして移行"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --type)
            PROJECT_TYPE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

# 現在のディレクトリをプロジェクトルートとして使用
PROJECT_DIR="$(pwd)"

# worktree形式の検出
IS_WORKTREE=false
if [ -d ".git" ] && [ -d ".git/worktrees" ]; then
    if [ -d "main" ] && [ -f "main/.git" ]; then
        echo "エラー: worktree形式のプロジェクトです。main/で実行してください:"
        echo "  cd main && /twl:project-migrate"
        exit 1
    fi
elif [ -f ".git" ]; then
    IS_WORKTREE=true
fi

# プロジェクトルートの検証
if [ ! -e ".git" ] && [ ! -f "CLAUDE.md" ]; then
    echo "エラー: プロジェクトルートで実行してください（.gitまたはCLAUDE.mdが必要）"
    exit 1
fi

# プロジェクト名の決定
if [ "$IS_WORKTREE" = true ]; then
    PROJECT_NAME=$(basename "$(dirname "$PROJECT_DIR")")
else
    PROJECT_NAME=$(basename "$PROJECT_DIR")
fi

echo "=== プロジェクト移行分析: $PROJECT_NAME ==="
echo ""

# 1. 現状分析
echo "1. 現状分析..."

# OpenSpec構造の検出
OPENSPEC_VERSION="none"
if [ -f "openspec/config.yaml" ]; then
    OPENSPEC_VERSION="v1.x"
    echo "   OpenSpec: v1.x (config.yaml)"
elif [ -f "openspec/project.md" ]; then
    OPENSPEC_VERSION="v0.x"
    echo "   OpenSpec: v0.x (project.md) → 移行が必要"
elif [ -d "openspec" ]; then
    OPENSPEC_VERSION="partial"
    echo "   OpenSpec: 部分的 → 再初期化が必要"
else
    OPENSPEC_VERSION="none"
    echo "   OpenSpec: なし → 新規初期化"
fi

# タイプ自動検出
if [ -z "$PROJECT_TYPE" ]; then
    if [ -f "renv.lock" ] || [ -d "R" ]; then
        PROJECT_TYPE="rnaseq"
        echo "   タイプ検出: rnaseq (renv/Rディレクトリ)"
    elif grep -q '"hono"' package.json 2>/dev/null || grep -q '"@hono/zod-openapi"' apps/backend/package.json 2>/dev/null || [ -d "packages/schema" ]; then
        PROJECT_TYPE="webapp-hono"
        echo "   タイプ検出: webapp-hono (Hono/Zod monorepo構造)"
    elif [ -f "package.json" ] || [ -d "src/app" ] || [ -f "frontend/package.json" ] || [ -d "frontend/src/app" ] || [ -d "backend" ]; then
        PROJECT_TYPE="webapp-llm"
        echo "   タイプ検出: webapp-llm (Next.js/FastAPI構造)"
    else
        echo "   タイプ検出: 不明"
        echo ""
        echo "エラー: プロジェクトタイプを自動検出できません"
        echo "--type オプションで指定してください: --type rnaseq, --type webapp-llm, または --type webapp-hono"
        exit 1
    fi
else
    echo "   タイプ指定: $PROJECT_TYPE"
fi

# CLAUDE.md存在確認
if [ -f "CLAUDE.md" ]; then
    echo "   CLAUDE.md: 存在"
else
    echo "   CLAUDE.md: なし → 作成が必要"
fi

echo ""

# 2. 移行プラン生成
echo "2. 移行プラン..."
echo ""

CHANGES=()

# OpenSpec移行
if [ "$OPENSPEC_VERSION" = "v0.x" ]; then
    CHANGES+=("OpenSpec v0.x → v1.x 移行（project.md削除、config.yaml生成）")
elif [ "$OPENSPEC_VERSION" = "partial" ] || [ "$OPENSPEC_VERSION" = "none" ]; then
    CHANGES+=("OpenSpec 初期化（config.yaml生成）")
fi

# CLAUDE.md
if [ -f "CLAUDE.md" ]; then
    CHANGES+=("CLAUDE.md 更新（テンプレートとマージ）")
else
    CHANGES+=("CLAUDE.md 作成（テンプレートからコピー）")
fi

# 変更リスト表示
if [ ${#CHANGES[@]} -eq 0 ]; then
    echo "   変更なし: プロジェクトは最新です"
    exit 0
fi

echo "   予定される変更:"
for i in "${!CHANGES[@]}"; do
    echo "   [$((i+1))] ${CHANGES[$i]}"
done

echo ""

# dry-run の場合はここで終了
if [ "$DRY_RUN" = true ]; then
    echo "=== dry-run 完了 ==="
    echo "実際に適用するには --dry-run を外して実行してください"
    exit 0
fi

# 3. ユーザー確認
echo "3. 確認..."
echo ""
echo "上記の変更を適用しますか？"
echo "  [A] 全て適用"
echo "  [C] キャンセル"
echo ""
read -p "選択 (A/C): " choice

case "$choice" in
    [Aa])
        echo ""
        echo "4. 変更を適用..."
        ;;
    *)
        echo "キャンセルしました"
        exit 0
        ;;
esac

# 4. 変更適用

# DeltaSpec処理
if [ "$OPENSPEC_VERSION" = "v1.x" ]; then
    echo "   DeltaSpec: 最新バージョン（スキップ）"
elif [ "$OPENSPEC_VERSION" = "v0.x" ] || [ "$OPENSPEC_VERSION" = "partial" ] || [ "$OPENSPEC_VERSION" = "none" ]; then
    echo "   DeltaSpec 初期化..."
    if command -v deltaspec &> /dev/null; then
        echo "      deltaspec ディレクトリ構造を作成中..."
        mkdir -p "$PROJECT_DIR/openspec/specs" "$PROJECT_DIR/openspec/changes"
        echo "      DeltaSpec 初期化完了"
        cleanup_openspec_local "$PROJECT_DIR"
    else
        echo "      警告: deltaspec CLIが見つかりません"
    fi
fi

# CLAUDE.md処理
TEMPLATE_CLAUDE="$TEMPLATES_BASE/$PROJECT_TYPE/CLAUDE.md"
if [ -f "$TEMPLATE_CLAUDE" ]; then
    if [ -f "CLAUDE.md" ]; then
        echo "   CLAUDE.md マージ..."
        cp "CLAUDE.md" "CLAUDE.md.backup"
        echo "      既存ファイルを CLAUDE.md.backup に保存"

        PROJECT_SPECIFIC=""
        if grep -q "## プロジェクト固有" "CLAUDE.md.backup"; then
            PROJECT_SPECIFIC=$(sed -n '/## プロジェクト固有/,$p' "CLAUDE.md.backup")
        fi

        sed "s/<project>/$PROJECT_NAME/g" "$TEMPLATE_CLAUDE" > "CLAUDE.md"

        if [ -n "$PROJECT_SPECIFIC" ]; then
            echo "" >> "CLAUDE.md"
            echo "$PROJECT_SPECIFIC" >> "CLAUDE.md"
        fi

        echo "      CLAUDE.md 更新完了"
    else
        echo "   CLAUDE.md 作成..."
        sed "s/<project>/$PROJECT_NAME/g" "$TEMPLATE_CLAUDE" > "CLAUDE.md"
        echo "      CLAUDE.md 作成完了"
    fi
else
    echo "   警告: テンプレート $TEMPLATE_CLAUDE が見つかりません"
fi

# archive内のspecsを確認
if [ -d "openspec/archive" ]; then
    echo ""
    echo "   archive内のspecsを確認中..."
    ARCHIVED_SPECS=()
    while IFS= read -r -d '' spec_file; do
        ARCHIVED_SPECS+=("$spec_file")
    done < <(find "openspec/archive" -name "spec.md" -print0 2>/dev/null)

    if [ ${#ARCHIVED_SPECS[@]} -gt 0 ]; then
        echo "      ${#ARCHIVED_SPECS[@]}個のアーカイブ済みspecを検出"
        echo "      注: アーカイブされたspecsは完了済み機能のため移行しません。"
    fi
fi

# DeltaSpec: specs ディレクトリの存在確認（sync は不要）
if [ -d "openspec/specs" ] && [ "$(find openspec/specs -name '*.md' 2>/dev/null | head -1)" ]; then
    echo ""
    echo "   DeltaSpec: specs ディレクトリ確認済み"
fi

echo ""
echo "=== 移行完了 ==="
echo ""
echo "次のステップ:"
echo "  git add -A && git commit -m 'chore: migrate to latest template'"
echo "  /twl:controller-setup  # 開発開始"
