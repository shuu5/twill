import argparse
import sys

from twl.core.types import print_rules, sync_check, sync_docs
from twl.core.plugin import get_plugin_root, load_deps, get_plugin_name, build_graph
from twl.chain.generate import handle_chain_subcommand
from twl.viz.graphviz import update_readme
from twl.refactor.rename import rename_component
from twl.refactor.promote import promote_component
from twl.refactor.refine import handle_refine
from twl.cli_dispatch import (
    handle_complexity,
    handle_tokens,
    handle_check,
    handle_validate,
    handle_orphans,
    handle_deep_validate,
    handle_audit,
    handle_list,
    handle_target,
    handle_reverse,
    handle_viz,
    handle_explore_link,
)


def _load_plugin_context():
    plugin_root = get_plugin_root()
    deps = load_deps(plugin_root)
    graph = build_graph(deps, plugin_root)
    plugin_name = get_plugin_name(deps, plugin_root)
    return plugin_root, deps, graph, plugin_name


def main():
    # hello サブコマンド
    if len(sys.argv) >= 2 and sys.argv[1] == 'hello':
        print("Hello from TWiLL")
        sys.exit(0)

    # audit サブコマンド（autopilot 実行履歴の永続化）
    if len(sys.argv) >= 2 and sys.argv[1] == 'audit':
        from twl.autopilot.audit import main as audit_main
        sys.exit(audit_main(sys.argv[2:]))

    # audit-history サブコマンドの前処理（Phase 3 / Layer 1 経験的監査）
    if len(sys.argv) >= 2 and sys.argv[1] == 'audit-history':
        from twl.autopilot.audit_history import main as audit_history_main
        sys.exit(audit_history_main(sys.argv[2:]))

    # config サブコマンド（project-links.yaml ローダー）
    if len(sys.argv) >= 2 and sys.argv[1] == 'config':
        from twl.config import main as config_main
        sys.exit(config_main(sys.argv[2:]))

    # explore-link サブコマンド
    if len(sys.argv) >= 2 and sys.argv[1] == 'explore-link':
        sys.exit(handle_explore_link(sys.argv[2:]))

    # check サブコマンドの前処理
    if len(sys.argv) >= 2 and sys.argv[1] == 'check':
        sub_parser = argparse.ArgumentParser(description='Check file existence and chain validation')
        sub_parser.add_argument('--format', choices=['json'], help='Output format')
        sub_parser.add_argument('--deps-integrity', action='store_true',
                                help='Hash-verify chain.py ↔ deps.yaml ↔ chain-steps.sh (blocks on drift)')
        sub_args = sub_parser.parse_args(sys.argv[2:])
        plugin_root, deps, graph, plugin_name = _load_plugin_context()
        sys.exit(handle_check(sub_args, graph, deps, plugin_root, plugin_name))

    # refine サブコマンド
    if len(sys.argv) >= 2 and sys.argv[1] == 'refine':
        sys.exit(handle_refine(sys.argv[2:]))

    # chain サブコマンドの前処理（sys.argv を先に検査）
    if len(sys.argv) >= 2 and sys.argv[1] == 'chain':
        if len(sys.argv) >= 3 and sys.argv[2] == 'generate':
            handle_chain_subcommand(sys.argv[3:])
            sys.exit(0)
        elif len(sys.argv) >= 3 and sys.argv[2] == 'viz':
            from twl.chain.viz import handle_chain_viz_subcommand
            handle_chain_viz_subcommand(sys.argv[3:])
            sys.exit(0)
        elif len(sys.argv) >= 3 and sys.argv[2] == 'export':
            from twl.chain.export import handle_chain_export_subcommand
            sys.exit(handle_chain_export_subcommand(sys.argv[3:]))
        elif len(sys.argv) >= 3 and sys.argv[2] == 'validate':
            from twl.chain.validate import handle_chain_validate_subcommand
            sys.exit(handle_chain_validate_subcommand(sys.argv[3:]))
        else:
            print(f"Error: unknown chain subcommand '{sys.argv[2] if len(sys.argv) >= 3 else ''}'", file=sys.stderr)
            print("Usage: twl chain generate <chain-name> [--write]", file=sys.stderr)
            print("       twl chain viz <chain-name>", file=sys.stderr)
            print("       twl chain viz --all [--update-readme]", file=sys.stderr)
            print("       twl chain viz --update-arch", file=sys.stderr)
            print("       twl chain export --yaml [--write]", file=sys.stderr)
            print("       twl chain export --shell [--write]", file=sys.stderr)
            print("       twl chain validate [--integrity] [--format json]", file=sys.stderr)
            sys.exit(1)

    parser = argparse.ArgumentParser(description='Analyze plugin dependencies')
    parser.add_argument('--tree', action='store_true', help='ASCII tree output')
    parser.add_argument('--rich', action='store_true', help='Rich tree output (requires rich)')
    parser.add_argument('--mermaid', action='store_true', help='Mermaid graph output')
    parser.add_argument('--graphviz', action='store_true', help='Graphviz DOT output (default)')
    parser.add_argument('--target', help='Show dependencies for target')
    parser.add_argument('--reverse', help='Show reverse dependencies for target')
    parser.add_argument('--check', action='store_true', help='Check file existence')
    parser.add_argument('--validate', action='store_true', help='Validate type rules (can_spawn/spawnable_by)')
    parser.add_argument('--list', action='store_true', help='List all nodes')
    parser.add_argument('--update-readme', action='store_true', help='Update README.md with SVG graph and Entry Points table')
    parser.add_argument('--check-readme', action='store_true', help='Check if README.md is up to date (exit 1 if drift detected)')
    parser.add_argument('--orphans', action='store_true', help='Find orphan nodes (unused/isolated)')
    parser.add_argument('--tokens', action='store_true', help='Show token counts for all nodes')
    parser.add_argument('--no-tokens', action='store_true', help='Hide token counts in graph output')
    parser.add_argument('--deep-validate', action='store_true', help='Deep validation (controller bloat, ref placement, tools consistency)')
    parser.add_argument('--audit', action='store_true', help='TWiLL compliance audit (10-section markdown report)')
    parser.add_argument('--section', type=int, metavar='N', help='Filter --audit output to a single section number (1-10)')
    parser.add_argument('--complexity', action='store_true', help='Complexity metrics report')
    parser.add_argument('--rename', nargs=2, metavar=('OLD', 'NEW'), help='Rename a component (updates deps.yaml, frontmatter, body refs)')
    parser.add_argument('--promote', nargs=2, metavar=('NAME', 'NEW_TYPE'), help='Change component type (promote/demote with section move, file move, can_spawn/spawnable_by adjustment)')
    parser.add_argument('--dry-run', action='store_true', help='Preview changes without applying (use with --rename or --promote)')
    parser.add_argument('--rules', action='store_true', help='Print type rules table from types.yaml')
    parser.add_argument('--sync-check', metavar='REF_PATH', help='Compare types.yaml with a reference Markdown document')
    parser.add_argument('--sync-docs', metavar='TARGET_DIR', help='Sync docs/ref-*.md to target directory with frontmatter from deps.yaml')
    parser.add_argument('--format', choices=['json'], help='Output format (default: text)')

    args = parser.parse_args()

    if args.rules:
        print_rules()
        sys.exit(0)

    if args.sync_check:
        sync_check(args.sync_check)
        sys.exit(0)

    if args.sync_docs:
        sync_docs(args.sync_docs, check_only=args.check)
        sys.exit(0)

    plugin_root, deps, graph, plugin_name = _load_plugin_context()

    if args.rename:
        old_name, new_name = args.rename
        sys.exit(0 if rename_component(plugin_root, deps, old_name, new_name, args.dry_run) else 1)

    if args.promote:
        comp_name, new_type = args.promote
        sys.exit(0 if promote_component(plugin_root, deps, comp_name, new_type, args.dry_run) else 1)

    if not any([args.tree, args.rich, args.mermaid, args.graphviz, args.target, args.reverse, args.check, args.validate, args.list, args.update_readme, args.check_readme, args.orphans, args.tokens, args.deep_validate, args.audit, args.complexity]):
        args.graphviz = True

    show_tokens = not args.no_tokens

    if args.complexity:
        handle_complexity(args, graph, deps, plugin_root, plugin_name)

    if args.tokens:
        handle_tokens(args, graph)

    if args.update_readme:
        success = update_readme(plugin_root, graph, deps, plugin_name, show_tokens)
        if not success:
            sys.exit(1)

    if args.check_readme:
        success = update_readme(plugin_root, graph, deps, plugin_name, show_tokens, check_only=True)
        sys.exit(0 if success else 1)

    if args.check:
        sys.exit(handle_check(args, graph, deps, plugin_root, plugin_name))

    if args.validate:
        handle_validate(args, deps, graph, plugin_root, plugin_name)

    if args.orphans:
        handle_orphans(args, graph, deps)

    if args.deep_validate:
        handle_deep_validate(args, deps, graph, plugin_root, plugin_name)
    elif args.audit:
        handle_audit(args, deps, plugin_root, plugin_name)
    elif args.list:
        handle_list(args, graph)
    elif args.target:
        handle_target(args, graph)
    elif args.reverse:
        handle_reverse(args, graph)
    elif args.tree or args.rich or args.mermaid or args.graphviz:
        handle_viz(args, graph, deps, plugin_root, plugin_name, show_tokens)
