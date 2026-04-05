"""twl CLI エントリポイント。argparse サブコマンドを定義し engine.main() に委譲する。"""
import argparse
import sys


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="twl",
        description="TWiLL framework CLI",
    )
    sub = parser.add_subparsers(dest="command", metavar="command")

    sub.add_parser("check", help="ファイル存在チェック")
    sub.add_parser("validate", help="型ルール検証 (can_spawn/spawnable_by)")
    sub.add_parser("deep-validate", help="深層検証（controller bloat, ref配置, tools整合性）")
    sub.add_parser("audit", help="TWiLL 準拠度の機械的チェック（5セクションレポート）")
    sub.add_parser("tree", help="ASCII ツリー出力")
    sub.add_parser("graph", help="Graphviz DOT 出力（デフォルト）")
    sub.add_parser("mermaid", help="Mermaid フローチャート出力")
    sub.add_parser("list", help="全ノード一覧")
    sub.add_parser("tokens", help="トークン数を表示")
    sub.add_parser("orphans", help="未使用/孤立ノード検出")
    sub.add_parser("complexity", help="7メトリクス複雑さレポート")
    sub.add_parser("update-readme", help="SVG グラフ生成 + README.md 更新")
    sub.add_parser("rules", help="型ルールテーブルを表示 (types.yaml)")
    sub.add_parser("update-svgs", help="全 plugin の SVG を一括再生成")

    rename_p = sub.add_parser("rename", help="コンポーネント名を一括変更")
    rename_p.add_argument("old", help="旧名")
    rename_p.add_argument("new", help="新名")
    rename_p.add_argument("--dry-run", action="store_true", help="変更内容のプレビュー")

    promote_p = sub.add_parser("promote", help="コンポーネントの型変更（昇格/降格）")
    promote_p.add_argument("name", help="コンポーネント名")
    promote_p.add_argument("new_type", metavar="new-type", help="新しい型")
    promote_p.add_argument("--dry-run", action="store_true", help="変更内容のプレビュー")

    reverse_p = sub.add_parser("reverse", help="逆依存関係を表示")
    reverse_p.add_argument("name", help="コンポーネント名")

    target_p = sub.add_parser("target", help="依存関係を表示")
    target_p.add_argument("name", help="コンポーネント名")

    sync_check_p = sub.add_parser("sync-check", help="types.yaml と参照ドキュメントの差分を検出")
    sync_check_p.add_argument("--ref", required=True, metavar="PATH", help="参照 Markdown ファイル")

    sync_docs_p = sub.add_parser("sync-docs", help="docs/ref-*.md をターゲットディレクトリに同期")
    sync_docs_p.add_argument("target_dir", metavar="target-dir", help="同期先ディレクトリ")
    sync_docs_p.add_argument("--check", action="store_true", help="差分確認のみ（変更なし）")

    chain_p = sub.add_parser("chain", help="chain 定義から成果物を生成")
    chain_sub = chain_p.add_subparsers(dest="chain_command", metavar="subcommand")
    chain_gen = chain_sub.add_parser("generate", help="chain 定義から成果物を生成")
    chain_gen.add_argument("name", nargs="?", help="chain 名")
    chain_gen.add_argument("--write", action="store_true", help="ファイルに書き込む")
    chain_gen.add_argument("--check", action="store_true", help="乖離検出")
    chain_gen.add_argument("--all", action="store_true", help="全 chain を対象")

    return parser


def main() -> None:
    # chain サブコマンドは engine 側の独自処理に委譲（sys.argv そのまま）
    if len(sys.argv) >= 2 and sys.argv[1] == "chain":
        from twl import engine
        engine.main()
        return

    if len(sys.argv) == 1:
        _build_parser().print_help()
        sys.exit(0)

    cmd = sys.argv[1]
    rest = sys.argv[2:]

    # --flag スタイルへの変換マップ
    _simple_flag_map = {
        "check": "--check",
        "validate": "--validate",
        "deep-validate": "--deep-validate",
        "audit": "--audit",
        "tree": "--tree",
        "graph": "--graphviz",
        "mermaid": "--mermaid",
        "list": "--list",
        "tokens": "--tokens",
        "orphans": "--orphans",
        "complexity": "--complexity",
        "update-readme": "--update-readme",
        "rules": "--rules",
    }

    if cmd in _simple_flag_map:
        sys.argv = [sys.argv[0], _simple_flag_map[cmd]] + rest
    elif cmd == "rename":
        if len(rest) < 2:
            print("Error: rename requires <old-name> <new-name>", file=sys.stderr)
            print("Usage: twl rename <old-name> <new-name> [--dry-run]", file=sys.stderr)
            sys.exit(1)
        old, new = rest[0], rest[1]
        flags = rest[2:]
        sys.argv = [sys.argv[0], "--rename", old, new] + flags
    elif cmd == "promote":
        if len(rest) < 2:
            print("Error: promote requires <name> <new-type>", file=sys.stderr)
            print("Usage: twl promote <name> <new-type> [--dry-run]", file=sys.stderr)
            sys.exit(1)
        name, new_type = rest[0], rest[1]
        flags = rest[2:]
        sys.argv = [sys.argv[0], "--promote", name, new_type] + flags
    elif cmd == "reverse":
        if not rest:
            print("Error: reverse requires a target name", file=sys.stderr)
            sys.exit(1)
        sys.argv = [sys.argv[0], "--reverse"] + rest
    elif cmd == "target":
        if not rest:
            print("Error: target requires a name", file=sys.stderr)
            sys.exit(1)
        sys.argv = [sys.argv[0], "--target"] + rest
    elif cmd == "sync-check":
        if "--ref" not in rest:
            print("Error: sync-check requires --ref <path>", file=sys.stderr)
            print("Usage: twl sync-check --ref <path>", file=sys.stderr)
            sys.exit(1)
        idx = rest.index("--ref")
        if idx + 1 >= len(rest):
            print("Error: --ref requires a file path", file=sys.stderr)
            sys.exit(1)
        ref_path = rest[idx + 1]
        sys.argv = [sys.argv[0], "--sync-check", ref_path]
    elif cmd == "sync-docs":
        if not rest:
            print("Error: sync-docs requires <target-dir>", file=sys.stderr)
            print("Usage: twl sync-docs <target-dir> [--check]", file=sys.stderr)
            sys.exit(1)
        target_dir = rest[0]
        extra = rest[1:]
        check_flag = ["--check"] if "--check" in extra else []
        sys.argv = [sys.argv[0], "--sync-docs", target_dir] + check_flag
    elif cmd == "update-svgs":
        _run_update_svgs()
        return
    elif cmd in ("help", "--help", "-h"):
        _build_parser().print_help()
        sys.exit(0)
    else:
        print(f"Error: unknown command '{cmd}'", file=sys.stderr)
        print("Run 'twl help' for usage", file=sys.stderr)
        sys.exit(1)

    from twl import engine
    engine.main()


def _run_update_svgs() -> None:
    """全 plugin の SVG を一括再生成する。"""
    import subprocess
    from pathlib import Path

    plugins_dir = Path.home() / ".claude" / "plugins"
    if not plugins_dir.is_dir():
        print(f"Error: plugins directory not found at {plugins_dir}", file=sys.stderr)
        sys.exit(1)

    engine_path = Path(__file__).resolve().parent / "engine.py"
    success = 0
    fail = 0
    skip_names = {"_shared", "cache", "marketplaces"}

    for plugin_dir in sorted(plugins_dir.iterdir()):
        if not plugin_dir.is_dir():
            continue
        if plugin_dir.name in skip_names:
            continue
        if not (plugin_dir / "deps.yaml").exists():
            continue

        print(f"--- {plugin_dir.name} ---")
        result = subprocess.run(
            [sys.executable, str(engine_path), "--update-readme"],
            cwd=str(plugin_dir),
        )
        if result.returncode == 0:
            success += 1
        else:
            print(f"  FAILED: {plugin_dir.name}", file=sys.stderr)
            fail += 1

    print(f"\n=== update-svgs complete: {success} success, {fail} failed ===")
    if fail > 0:
        sys.exit(1)
