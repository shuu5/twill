import argparse
import sys
from pathlib import Path

from twl.core.types import print_rules, sync_check, sync_docs
from twl.core.plugin import get_plugin_root, load_deps, get_plugin_name, build_graph
from twl.core.plugin import get_deps_version
from twl.core.graph import find_node, get_reverse_dependencies, print_tree
from twl.core.output import build_envelope, output_json, violations_to_items, check_results_to_items, deep_validate_to_items
from twl.validation.check import check_files, find_orphans
from twl.validation.validate import validate_types, validate_body_refs, validate_v3_schema
from twl.validation.deep import deep_validate
from twl.validation.audit import audit_collect, audit_report
from twl.validation.complexity import complexity_collect, complexity_report
from twl.chain.validate import chain_validate
from twl.chain.generate import handle_chain_subcommand
from twl.viz.graphviz import print_graphviz, update_readme
from twl.viz.mermaid import print_mermaid
from twl.viz.tree import print_rich_tree
from twl.refactor.rename import rename_component
from twl.refactor.promote import promote_component


def handle_complexity(args, graph, deps, plugin_root, plugin_name):
    if args.format == 'json':
        items = complexity_collect(graph, deps, plugin_root)
        exit_code = 0
        envelope = build_envelope("complexity", get_deps_version(deps), plugin_name, items, exit_code)
        output_json(envelope)
        sys.exit(exit_code)
    complexity_report(graph, deps, plugin_root)


def handle_tokens(args, graph):
    print("=== Token Counts ===")
    print()

    total_tokens = 0
    sections = [
        ('Skills', 'skill'),
        ('Commands', 'command'),
        ('Agents', 'agent'),
        ('Scripts', 'script'),
    ]

    for section_name, node_type in sections:
        print(f"## {section_name}")
        section_total = 0
        items = []
        for node_id, node_data in sorted(graph.items()):
            if node_data['type'] == node_type:
                tokens = node_data.get('tokens', 0)
                items.append((node_data['name'], tokens))
                section_total += tokens

        items.sort(key=lambda x: x[1], reverse=True)
        for name, tokens in items:
            print(f"  {name}: {tokens:,} tokens")

        print(f"  --- subtotal: {section_total:,} tokens")
        print()
        total_tokens += section_total

    print(f"=== Total: {total_tokens:,} tokens ===")


def handle_check(args, graph, deps, plugin_root, plugin_name):
    results, check_xref_warnings = check_files(graph, plugin_root)

    ok_count = sum(1 for r in results if r[0] == 'ok')
    missing_count = sum(1 for r in results if r[0] == 'missing')
    no_path_count = sum(1 for r in results if r[0] == 'no_path')
    external_count = sum(1 for r in results if r[0] == 'external')

    chain_items = []
    cv_criticals_check = []
    cv_warnings_check = []
    if get_deps_version(deps).startswith('3'):
        cv_criticals_check, cv_warnings_check, cv_infos_check = chain_validate(deps, plugin_root)
        chain_items = deep_validate_to_items(cv_criticals_check, cv_warnings_check, cv_infos_check)

    exit_code = 1 if (missing_count > 0 or cv_criticals_check) else 0

    if args.format == 'json':
        items = check_results_to_items(results)
        items.extend(violations_to_items(check_xref_warnings, "warning"))
        items.extend(chain_items)
        envelope = build_envelope("check", get_deps_version(deps), plugin_name, items, exit_code)
        output_json(envelope)
        sys.exit(exit_code)

    print(f"=== File Check Results ===")
    print(f"OK: {ok_count}, Missing: {missing_count}, No path: {no_path_count}, External: {external_count}")
    print()

    if check_xref_warnings:
        print("Warnings:")
        for w in check_xref_warnings:
            print(f"  - {w}")
        print()

    if missing_count > 0:
        print("Missing files:")
        for status, node_id, path in results:
            if status == 'missing':
                print(f"  - {node_id}: {path}")
        sys.exit(1)
    else:
        print("All files exist.")

    if chain_items and (cv_criticals_check or cv_warnings_check):
        print()
        print("=== Chain Validation Results ===")
        if cv_criticals_check:
            print("Critical:")
            for c in cv_criticals_check:
                print(f"  - {c}")
        if cv_warnings_check:
            print("Warning:")
            for w in cv_warnings_check:
                print(f"  - {w}")
        if cv_criticals_check:
            sys.exit(1)


def handle_validate(args, deps, graph, plugin_root, plugin_name):
    ok_count, violations, xref_warnings = validate_types(deps, graph, plugin_root)
    body_ok, body_violations = validate_body_refs(deps, plugin_root)
    ok_count += body_ok
    violations.extend(body_violations)
    v3_ok, v3_violations = validate_v3_schema(deps)
    ok_count += v3_ok
    violations.extend(v3_violations)
    cv_criticals, cv_warnings, _cv_infos = chain_validate(deps, plugin_root)
    violations.extend(cv_criticals)
    violations.extend(cv_warnings)

    exit_code = 1 if violations else 0

    if args.format == 'json':
        items = violations_to_items(violations)
        items.extend(violations_to_items(xref_warnings, "warning"))
        envelope = build_envelope("validate", get_deps_version(deps), plugin_name, items, exit_code)
        output_json(envelope)
        sys.exit(exit_code)

    print(f"=== Type Validation Results ===")
    print(f"OK: {ok_count}, Violations: {len(violations)}")
    print()

    if xref_warnings:
        print("Warnings:")
        for w in xref_warnings:
            print(f"  - {w}")
        print()

    if violations:
        print("Violations:")
        for v in violations:
            print(f"  - {v}")
        sys.exit(1)
    else:
        print("All type constraints satisfied.")


def handle_orphans(args, graph, deps):
    orphans = find_orphans(graph, deps)

    print("=== Orphan Analysis ===")
    print()

    if orphans['isolated']:
        print("## Isolated (no callers, no deps):")
        for node_id in orphans['isolated']:
            node = graph.get(node_id)
            desc = node['description'][:40] if node['description'] else ''
            print(f"  - {node_id}: {desc}...")
        print()

    if orphans['unused']:
        print("## Unused (no callers):")
        for node_id in orphans['unused']:
            if node_id not in orphans['isolated']:
                node = graph.get(node_id)
                desc = node['description'][:40] if node['description'] else ''
                print(f"  - {node_id}: {desc}...")
        print()

    leaf_commands = [n for n in orphans['no_deps'] if graph[n]['type'] == 'command']
    if leaf_commands:
        print("## Leaf commands (no outgoing deps):")
        for node_id in leaf_commands:
            print(f"  - {node_id}")
        print()

    total_orphans = len(orphans['unused'])
    if total_orphans == 0:
        print("No orphan nodes found.")
    else:
        print(f"Total unused: {total_orphans}")


def handle_deep_validate(args, deps, graph, plugin_root, plugin_name):
    ok_count, violations, xref_warnings = validate_types(deps, graph, plugin_root)
    body_ok, body_violations = validate_body_refs(deps, plugin_root)
    ok_count += body_ok
    violations.extend(body_violations)
    v3_ok, v3_violations = validate_v3_schema(deps)
    ok_count += v3_ok
    violations.extend(v3_violations)

    criticals, dv_warnings, dv_infos = deep_validate(deps, plugin_root)
    dv_warnings.extend(xref_warnings)
    cv_criticals, cv_warnings, cv_infos = chain_validate(deps, plugin_root)
    criticals.extend(cv_criticals)
    dv_warnings.extend(cv_warnings)
    dv_infos.extend(cv_infos)

    exit_code = 1 if (violations or criticals) else 0

    if args.format == 'json':
        items = violations_to_items(violations)
        items.extend(deep_validate_to_items(criticals, dv_warnings, dv_infos))
        envelope = build_envelope("deep-validate", get_deps_version(deps), plugin_name, items, exit_code)
        output_json(envelope)
        sys.exit(exit_code)

    print("=== Deep Validation Results ===")
    print()

    print(f"## Type Validation: OK={ok_count}, Violations={len(violations)}")
    if violations:
        for v in violations:
            print(f"  - {v}")
    print()

    has_issues = False
    if criticals:
        has_issues = True
        print("## Critical:")
        for c in criticals:
            print(f"  - {c}")
        print()
    if dv_warnings:
        has_issues = True
        print("## Warning:")
        for w in dv_warnings:
            print(f"  - {w}")
        print()
    if dv_infos:
        print("## Info:")
        for i in dv_infos:
            print(f"  - {i}")
        print()

    if not has_issues and not violations:
        print("All deep validation checks passed.")
    elif violations or criticals:
        sys.exit(1)


def handle_audit(args, deps, plugin_root, plugin_name):
    section_filter = getattr(args, 'section', None)
    section_name_map = {
        1: 'controller_size',
        2: 'inline_implementation',
        3: 'step0_routing',
        4: 'tools_accuracy',
        5: 'self_contained',
        6: 'token_bloat',
        7: 'prompt_compliance',  # audit_collect uses Section 7 = prompt_compliance (Model is report-only)
        8: 'prompt_compliance',
        9: 'chain_integrity',
    }

    if args.format == 'json':
        items = audit_collect(deps, plugin_root)
        if section_filter is not None:
            target_section = section_name_map.get(section_filter)
            if target_section:
                items = [i for i in items if i['section'] == target_section]
        exit_code = 1 if any(i['severity'] == 'critical' for i in items) else 0
        envelope = build_envelope("audit", get_deps_version(deps), plugin_name, items, exit_code)
        output_json(envelope)
        sys.exit(exit_code)

    if section_filter == 9:
        from twl.validation.audit import audit_chain_integrity
        print("=== TWiLL Compliance Audit (Section 9 only) ===")
        print()
        print("## 9. Chain Integrity")
        print()
        print("| Workflow → Target | Issue | Severity |")
        print("|-------------------|-------|----------|")
        chain_items = audit_chain_integrity(deps, plugin_root)
        criticals = 0
        warnings = 0
        oks = 0
        for item in chain_items:
            sev = item['severity']
            if sev == 'critical':
                criticals += 1
                print(f"| {item['component']} | {item['message']} | CRITICAL |")
            elif sev == 'warning':
                warnings += 1
                print(f"| {item['component']} | {item['message']} | WARNING |")
            else:
                oks += 1
        if not (criticals or warnings):
            print(f"| (all {oks} entries) | OK | OK |")
        print()
        print(f"## Summary")
        print(f"| Severity | Count |")
        print(f"|----------|-------|")
        print(f"| CRITICAL | {criticals} |")
        print(f"| WARNING  | {warnings} |")
        print(f"| OK       | {oks} |")
        if criticals > 0:
            sys.exit(1)
        return

    print("=== TWiLL Compliance Audit ===")
    print()
    audit_criticals, audit_warnings, audit_oks = audit_report(deps, plugin_root)
    if audit_criticals > 0:
        sys.exit(1)


def handle_list(args, graph):
    print("=== All Nodes ===")
    for section in ['skills', 'commands', 'agents']:
        print(f"\n## {section.upper()}")
        for node_id in sorted(graph):
            if graph[node_id]['type'] == section.rstrip('s'):
                node = graph[node_id]
                skill_type = f" [{node.get('skill_type')}]" if node.get('skill_type') else ""
                desc = node['description'][:50] if node['description'] else ''
                print(f"  {node['name']}{skill_type}: {desc}...")

    print("\n## SCRIPTS")
    for node_id in sorted(graph):
        if graph[node_id]['type'] == 'script':
            node = graph[node_id]
            desc = node['description'][:50] if node['description'] else ''
            print(f"  {node['name']}: {desc}...")

    print("\n## EXTERNAL")
    for node_id in sorted(graph):
        if graph[node_id]['type'] == 'external':
            print(f"  {graph[node_id]['name']}")


def handle_target(args, graph):
    node_id = find_node(graph, args.target)
    if not node_id:
        print(f"Error: '{args.target}' not found", file=sys.stderr)
        sys.exit(1)

    if args.rich:
        print_rich_tree(graph, node_id)
    else:
        print(f"=== Dependencies of {args.target} ===")
        print()
        print_tree(graph, node_id)


def handle_reverse(args, graph):
    node_id = find_node(graph, args.reverse)
    if not node_id:
        print(f"Error: '{args.reverse}' not found", file=sys.stderr)
        sys.exit(1)

    reverse = get_reverse_dependencies(graph, node_id)
    print(f"=== What uses {args.reverse} ===")
    print()
    if reverse:
        for (nid, rel) in reverse:
            node = graph.get(nid)
            if node:
                print(f"  {node['type']}:{node['name']}")
    else:
        print("  (nothing)")


def handle_viz(args, graph, deps, plugin_root, plugin_name, show_tokens):
    if args.tree:
        entry_points = deps.get('entry_points', [])
        if entry_points:
            skill_name = Path(entry_points[0]).parent.name
        else:
            skill_name = 'entry-workflow'
            for sname, sdata in deps.get('skills', {}).items():
                if sdata.get('type') == 'controller':
                    skill_name = sname
                    break
        node_id = f"skill:{skill_name}"
        print(f"=== Dependency Tree from {skill_name} ===")
        print()
        print_tree(graph, node_id)
    elif args.rich:
        entry_points = deps.get('entry_points', [])
        if entry_points:
            skill_name = Path(entry_points[0]).parent.name
        else:
            skill_name = 'entry-workflow'
            for sname, sdata in deps.get('skills', {}).items():
                if sdata.get('type') == 'controller':
                    skill_name = sname
                    break
        node_id = f"skill:{skill_name}"
        print_rich_tree(graph, node_id)
    elif args.mermaid:
        print_mermaid(graph, deps, plugin_name)
    else:
        print_graphviz(graph, deps, plugin_name, show_tokens)


def main():
    # audit-history サブコマンドの前処理（Phase 3 / Layer 1 経験的監査）
    if len(sys.argv) >= 2 and sys.argv[1] == 'audit-history':
        from twl.autopilot.audit_history import main as audit_history_main
        sys.exit(audit_history_main(sys.argv[2:]))

    # chain サブコマンドの前処理（sys.argv を先に検査）
    if len(sys.argv) >= 2 and sys.argv[1] == 'chain':
        if len(sys.argv) >= 3 and sys.argv[2] == 'generate':
            handle_chain_subcommand(sys.argv[3:])
            sys.exit(0)
        else:
            print(f"Error: unknown chain subcommand '{sys.argv[2] if len(sys.argv) >= 3 else ''}'", file=sys.stderr)
            print("Usage: twl chain generate <chain-name> [--write]", file=sys.stderr)
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
    parser.add_argument('--update-readme', action='store_true', help='Update README.md with SVG graph')
    parser.add_argument('--orphans', action='store_true', help='Find orphan nodes (unused/isolated)')
    parser.add_argument('--tokens', action='store_true', help='Show token counts for all nodes')
    parser.add_argument('--no-tokens', action='store_true', help='Hide token counts in graph output')
    parser.add_argument('--deep-validate', action='store_true', help='Deep validation (controller bloat, ref placement, tools consistency)')
    parser.add_argument('--audit', action='store_true', help='TWiLL compliance audit (9-section markdown report)')
    parser.add_argument('--section', type=int, metavar='N', help='Filter --audit output to a single section number (1-9)')
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

    plugin_root = get_plugin_root()
    deps = load_deps(plugin_root)
    graph = build_graph(deps, plugin_root)
    plugin_name = get_plugin_name(deps, plugin_root)

    if args.rename:
        old_name, new_name = args.rename
        sys.exit(0 if rename_component(plugin_root, deps, old_name, new_name, args.dry_run) else 1)

    if args.promote:
        comp_name, new_type = args.promote
        sys.exit(0 if promote_component(plugin_root, deps, comp_name, new_type, args.dry_run) else 1)

    if not any([args.tree, args.rich, args.mermaid, args.graphviz, args.target, args.reverse, args.check, args.validate, args.list, args.update_readme, args.orphans, args.tokens, args.deep_validate, args.audit, args.complexity]):
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

    if args.check:
        handle_check(args, graph, deps, plugin_root, plugin_name)

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
