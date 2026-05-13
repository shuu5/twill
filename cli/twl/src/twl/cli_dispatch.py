import sys
from pathlib import Path

from twl.core.output import build_envelope, output_json, violations_to_items, check_results_to_items, deep_validate_to_items
from twl.core.plugin import get_deps_version
from twl.core.graph import find_node, get_reverse_dependencies, print_tree
from twl.validation.check import check_files, find_orphans
from twl.validation.validate import validate_types, validate_body_refs, validate_v3_schema
from twl.validation.deep import deep_validate
from twl.validation.audit import audit_collect, audit_report
from twl.validation.complexity import complexity_collect, complexity_report
from twl.chain.validate import chain_validate
from twl.viz.graphviz import print_graphviz, update_readme
from twl.viz.mermaid import print_mermaid
from twl.viz.tree import print_rich_tree


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


def handle_check(*, format=None, deps_integrity=False, graph, deps, plugin_root, plugin_name):
    from twl.chain.integrity import check_deps_integrity

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

    # deps-integrity: always run; blocking only when deps_integrity=True is specified
    di_errors, di_warnings = check_deps_integrity(plugin_root)
    integrity_blocks = deps_integrity and bool(di_errors)

    exit_code = 1 if (missing_count > 0 or cv_criticals_check or integrity_blocks) else 0

    if format == 'json':
        items = check_results_to_items(results)
        items.extend(violations_to_items(check_xref_warnings, "warning"))
        items.extend(chain_items)
        severity = "critical" if integrity_blocks else "warning"
        for e in di_errors:
            items.append({"type": "deps-integrity", "severity": severity, "message": e})
        for w in di_warnings:
            items.append({"type": "deps-integrity", "severity": "warning", "message": w})
        envelope = build_envelope("check", get_deps_version(deps), plugin_name, items, exit_code)
        output_json(envelope)
        return exit_code

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
        return 1
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

    if di_errors or di_warnings:
        print()
        print("=== Deps Integrity Results ===")
        if di_errors:
            label = "Error" if deps_integrity else "Warning"
            for e in di_errors:
                print(f"  [{label}] {e}")
        for w in di_warnings:
            print(f"  [Info] {w}")

    return exit_code


def handle_validate(*, format=None, deps, graph, plugin_root, plugin_name):
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

    if format == 'json':
        items = violations_to_items(violations)
        items.extend(violations_to_items(xref_warnings, "warning"))
        envelope = build_envelope("validate", get_deps_version(deps), plugin_name, items, exit_code)
        output_json(envelope)
        return exit_code

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
        return 1
    else:
        print("All type constraints satisfied.")
    return 0


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


def handle_audit(*, format=None, section=None, scan_spec=False, deps, plugin_root, plugin_name):
    section_filter = section
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
        10: 'cross_layer_consistency',
        11: 'vocabulary_check',
        12: 'registry_integrity',
    }

    if format == 'json':
        items = audit_collect(deps, plugin_root, scan_spec=scan_spec)
        if section_filter is not None:
            target_section = section_name_map.get(section_filter)
            if target_section:
                items = [i for i in items if i['section'] == target_section]
        exit_code = 1 if any(i['severity'] == 'critical' for i in items) else 0
        envelope = build_envelope("audit", get_deps_version(deps), plugin_name, items, exit_code)
        output_json(envelope)
        return exit_code

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
        return 1 if criticals > 0 else 0

    if section_filter == 10:
        from twl.validation.audit import audit_cross_layer_consistency, _detect_monorepo_root
        monorepo_root = _detect_monorepo_root(plugin_root)
        print("=== TWiLL Compliance Audit (Section 10 only) ===")
        print()
        print("## 10. Cross-Layer Consistency")
        print()
        print("| Layer Pair | Issue | Severity |")
        print("|------------|-------|----------|")
        if monorepo_root is None:
            print("| (monorepo_root not detected) | git リポジトリ外または architecture/vision.md 不在 | INFO |")
            print()
            print("## Summary")
            print("| Severity | Count |")
            print("|----------|-------|")
            print("| CRITICAL | 0 |")
            print("| WARNING  | 0 |")
            print("| OK       | 0 |")
            return
        cross_items = audit_cross_layer_consistency(monorepo_root)
        criticals = 0
        warnings = 0
        oks = 0
        for item in cross_items:
            sev = item['severity']
            if sev == 'critical':
                criticals += 1
                print(f"| {item['component']} | {item['message']} | CRITICAL |")
            elif sev == 'warning':
                warnings += 1
                print(f"| {item['component']} | {item['message']} | WARNING |")
            elif sev == 'info':
                print(f"| {item['component']} | {item['message']} | INFO |")
            else:
                oks += 1
        if not (criticals or warnings):
            ok_pairs = sum(1 for i in cross_items if i['severity'] == 'ok')
            print(f"| (all {ok_pairs} pairs) | OK | OK |")
        print()
        print(f"## Summary")
        print(f"| Severity | Count |")
        print(f"|----------|-------|")
        print(f"| CRITICAL | {criticals} |")
        print(f"| WARNING  | {warnings} |")
        print(f"| OK       | {oks} |")
        return 1 if criticals > 0 else 0

    if section_filter == 11:
        from twl.validation.audit import audit_vocabulary
        registry_path = plugin_root / "registry.yaml"
        print("=== TWiLL Compliance Audit (Section 11 only) ===")
        print()
        print("## 11. Vocabulary Check")
        print()
        print("| Entity | Forbidden / Rule | Files | Severity |")
        print("|--------|------------------|-------|----------|")
        if not registry_path.exists():
            print("| (registry.yaml not found) | Section 11 skipped | - | INFO |")
            print()
            print("## Summary")
            print("| Severity | Count |")
            print("|----------|-------|")
            print("| WARNING  | 0 |")
            print("| INFO     | 1 |")
            return 0
        try:
            import yaml as _yaml
            registry = _yaml.safe_load(registry_path.read_text(encoding='utf-8')) or {}
        except Exception as e:
            print(f"| (registry.yaml parse error) | {e} | - | WARNING |")
            print()
            print("## Summary")
            print("| Severity | Count |")
            print("|----------|-------|")
            print("| WARNING  | 1 |")
            return 0
        if not isinstance(registry, dict):
            print("| (registry.yaml empty or invalid root) | - | - | WARNING |")
            return 0
        # _detect_monorepo_root を再利用 (audit_collect と同じ pattern、git rev-parse の二重実行を防ぐ)
        from twl.validation.audit import _detect_monorepo_root
        _mr = _detect_monorepo_root(plugin_root) if scan_spec else None
        vocab_items = audit_vocabulary(registry, plugin_root, monorepo_root=_mr, scan_spec=scan_spec)
        warnings = 0
        infos = 0
        for item in vocab_items:
            sev = item['severity']
            entity = item['component'].split(':', 1)[-1] if ':' in item['component'] else item['component']
            if sev == 'warning':
                warnings += 1
                print(f"| {entity} | {item['message']} | {item['value']} | WARNING |")
            elif sev == 'info':
                infos += 1
                print(f"| {entity} | {item['message']} | - | INFO |")
        if warnings == 0:
            print(f"| (no forbidden word violations) | - | - | OK |")
        print()
        print("## Summary")
        print("| Severity | Count |")
        print("|----------|-------|")
        print(f"| WARNING  | {warnings} |")
        print(f"| INFO     | {infos} |")
        return 0  # Section 11 は warning のみ、exit 1 しない

    if section_filter == 12:
        from twl.validation.audit import audit_registry
        registry_path = plugin_root / "registry.yaml"
        print("=== TWiLL Compliance Audit (Section 12 only) ===")
        print()
        print("## 12. Registry Integrity")
        print()
        print("| Component / Rule | Issue | Severity |")
        print("|------------------|-------|----------|")
        if not registry_path.exists():
            print("| (registry.yaml not found) | Section 12 skipped | INFO |")
            print()
            print("## Summary")
            print("| Severity | Count |")
            print("|----------|-------|")
            print("| CRITICAL | 0 |")
            print("| WARNING  | 0 |")
            print("| INFO     | 1 |")
            return 0
        try:
            import yaml as _yaml
            registry = _yaml.safe_load(registry_path.read_text(encoding='utf-8')) or {}
        except Exception as e:
            print(f"| (registry.yaml parse error) | {e} | WARNING |")
            print()
            print("## Summary")
            print("| Severity | Count |")
            print("|----------|-------|")
            print("| CRITICAL | 0 |")
            print("| WARNING  | 1 |")
            return 0
        if not isinstance(registry, dict):
            print("| (registry.yaml empty or invalid root) | - | WARNING |")
            print()
            print("## Summary")
            print("| Severity | Count |")
            print("|----------|-------|")
            print("| CRITICAL | 0 |")
            print("| WARNING  | 1 |")
            return 0
        reg_items = audit_registry(registry, plugin_root)
        criticals = 0
        warnings = 0
        oks = 0
        infos = 0
        for item in reg_items:
            sev = item['severity']
            if sev == 'critical':
                criticals += 1
                print(f"| {item['component']} | {item['message']} | CRITICAL |")
            elif sev == 'warning':
                warnings += 1
                print(f"| {item['component']} | {item['message']} | WARNING |")
            elif sev == 'info':
                infos += 1
                print(f"| {item['component']} | {item['message']} | INFO |")
            else:
                oks += 1
        if criticals == 0 and warnings == 0:
            print(f"| (all {oks} checks) | OK | OK |")
        print()
        print("## Summary")
        print("| Severity | Count |")
        print("|----------|-------|")
        print(f"| CRITICAL | {criticals} |")
        print(f"| WARNING  | {warnings} |")
        print(f"| INFO     | {infos} |")
        print(f"| OK       | {oks} |")
        return 1 if criticals > 0 else 0

    print("=== TWiLL Compliance Audit ===")
    print()
    audit_criticals, audit_warnings, audit_oks = audit_report(deps, plugin_root, scan_spec=scan_spec)
    return 1 if audit_criticals > 0 else 0


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


def handle_explore_link(argv):
    """explore-link subcommand: check/set/read explore-summary for an issue."""
    import shutil
    import subprocess

    if len(argv) < 2:
        print("Usage: twl explore-link {check|set|read} <N> [<path>]", file=sys.stderr)
        return 1

    action = argv[0]
    try:
        issue_number = int(argv[1])
    except ValueError:
        print(f"Error: '{argv[1]}' is not a valid issue number", file=sys.stderr)
        return 1

    explore_dir = Path(f".explore/{issue_number}")
    summary_path = explore_dir / "summary.md"

    if action == "check":
        if summary_path.exists():
            print(f".explore/{issue_number}/summary.md exists")
            return 0
        else:
            print(f".explore/{issue_number}/summary.md not found", file=sys.stderr)
            return 1

    elif action == "read":
        if not summary_path.exists():
            print(f"Error: .explore/{issue_number}/summary.md not found", file=sys.stderr)
            return 1
        print(summary_path.read_text(), end="")
        return 0

    elif action == "set":
        if len(argv) < 3:
            print("Usage: twl explore-link set <N> <path>", file=sys.stderr)
            return 1
        source_path = Path(argv[2])
        if not source_path.exists():
            print(f"Error: '{source_path}' not found", file=sys.stderr)
            return 1
        explore_dir.mkdir(parents=True, exist_ok=True)
        if source_path.resolve() != summary_path.resolve():
            shutil.copy2(str(source_path), str(summary_path))
            print(f"Copied {source_path} -> {summary_path}")
        else:
            print(f"Source and destination are the same file, skipping copy: {source_path}")

        # gh issue comment
        try:
            subprocess.run(
                ["gh", "issue", "comment", str(issue_number),
                 "--body", f"explore-summary linked: `{summary_path}`"],
                check=True, capture_output=True, text=True,
            )
            print(f"Commented on Issue #{issue_number}")
        except (subprocess.CalledProcessError, FileNotFoundError) as e:
            print(f"Warning: failed to comment on Issue #{issue_number}: {e}", file=sys.stderr)
        return 0

    else:
        print(f"Error: unknown action '{action}'. Use check/set/read.", file=sys.stderr)
        return 1
