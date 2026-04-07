#!/usr/bin/env python3
"""Tests for audit_chain_integrity (Section 9: Chain Integrity).

Coverage:
- Normal case (dispatched + step) -> no findings
- F1 orphan_call: step なし + LLM 駆動宣言なし + SKILL.md 言及なし -> WARNING
- F2 dispatch_gap: step あり + chain-runner.sh dispatch なし + LLM 駆動宣言なし + SKILL.md 言及なし -> CRITICAL
- LLM 駆動例外: dispatch_mode=llm -> finding 抑制
- SKILL.md 言及あり例外 -> finding 抑制
- Section 1-8 後方互換 PASS
- Section 9 が --audit に表示される
- --audit --section 9 で Section 9 のみ実行可能
"""

import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml


def _write_deps(plugin_dir: Path, deps: dict) -> None:
    (plugin_dir / "deps.yaml").write_text(
        yaml.dump(deps, default_flow_style=False, allow_unicode=True, sort_keys=False),
        encoding="utf-8",
    )


def _create_md(plugin_dir: Path, rel_path: str, name: str, body: str = "") -> None:
    fp = plugin_dir / rel_path
    fp.parent.mkdir(parents=True, exist_ok=True)
    fp.write_text(
        f"---\nname: {name}\ndescription: Test\n---\n\n{body or 'Body for ' + name}\n",
        encoding="utf-8",
    )


def _write_chain_runner(plugin_dir: Path, dispatched_steps: list[str]) -> None:
    """シンプルな chain-runner.sh を生成する"""
    runner_dir = plugin_dir / "scripts"
    runner_dir.mkdir(parents=True, exist_ok=True)
    case_lines = []
    for step in dispatched_steps:
        func = step.replace('-', '_')
        case_lines.append(f'    {step})           step_{func} "$@" ;;')
    case_block = "\n".join(case_lines) if case_lines else '    noop)            step_noop "$@" ;;'
    content = f"""#!/usr/bin/env bash
set -euo pipefail
main() {{
  local step="${{1:-}}"
  shift || true
  case "$step" in
{case_block}
    *) echo "unknown: $step" >&2; exit 1 ;;
  esac
}}
main "$@"
"""
    (runner_dir / "chain-runner.sh").write_text(content, encoding="utf-8")


def _make_plugin(tmpdir: Path, *, workflow_calls, dispatched, components=None, skill_body=""):
    """fixture プラグインを生成

    workflow_calls: list of dict (deps.yaml 形式の calls エントリ)
    dispatched: list of step name (chain-runner.sh に登録する step)
    components: dict {name: {'section': str, 'type': str, 'dispatch_mode': Optional[str]}}
    skill_body: SKILL.md body text
    """
    plugin_dir = tmpdir / "test-plugin-chain"
    plugin_dir.mkdir()

    deps = {
        "version": "3.0",
        "plugin": "test-chain",
        "chains": {},
        "skills": {
            "wf-target": {
                "type": "workflow",
                "path": "skills/wf-target/SKILL.md",
                "description": "Test workflow",
                "calls": workflow_calls,
            },
        },
        "commands": {},
        "agents": {},
        "scripts": {},
    }

    if components:
        for name, cfg in components.items():
            section = cfg.get('section', 'commands')
            entry: dict = {
                "type": cfg.get('type', 'atomic'),
                "path": cfg.get('path', f"{section}/{name}.md"),
                "description": f"Component {name}",
            }
            if 'dispatch_mode' in cfg:
                entry['dispatch_mode'] = cfg['dispatch_mode']
            deps[section][name] = entry
            _create_md(plugin_dir, entry['path'], name)

    _write_deps(plugin_dir, deps)
    _create_md(plugin_dir, "skills/wf-target/SKILL.md", "wf-target", body=skill_body)
    _write_chain_runner(plugin_dir, dispatched)

    return plugin_dir


def _run(plugin_dir: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, "-m", "twl"] + list(args),
        cwd=str(plugin_dir),
        capture_output=True,
        text=True,
    )


def _audit_json(plugin_dir: Path, *extra) -> list[dict]:
    proc = _run(plugin_dir, "--audit", "--format", "json", *extra)
    payload = json.loads(proc.stdout)
    return payload.get("data", payload).get("items", [])


def _chain_items(items: list[dict]) -> list[dict]:
    return [i for i in items if i['section'] == 'chain_integrity']


# ===========================================================================
# F1: orphan_call (step なし + LLM/trigger 宣言なし + SKILL.md 言及なし)
# ===========================================================================

class TestOrphanCall:
    def setup_method(self):
        self.tmp = Path(tempfile.mkdtemp())

    def teardown_method(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_orphan_call_emits_warning(self):
        plugin = _make_plugin(
            self.tmp,
            workflow_calls=[{"atomic": "orphan-step"}],
            dispatched=["other-step"],
            components={"orphan-step": {"section": "commands", "type": "atomic"}},
            skill_body="このワークフローは何もしない",
        )
        items = _chain_items(_audit_json(plugin))
        assert any(
            i['severity'] == 'warning' and 'orphan_call' in i['message']
            for i in items
        ), f"Expected orphan_call warning, got {items}"


# ===========================================================================
# F2: dispatch_gap (step あり + dispatch なし + LLM 宣言なし + SKILL.md 言及なし)
# ===========================================================================

class TestDispatchGap:
    def setup_method(self):
        self.tmp = Path(tempfile.mkdtemp())

    def teardown_method(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_dispatch_gap_emits_critical(self):
        plugin = _make_plugin(
            self.tmp,
            workflow_calls=[{"atomic": "ghost-step", "step": "1"}],
            dispatched=["other-step"],
            components={"ghost-step": {"section": "commands", "type": "atomic"}},
            skill_body="このワークフローは何もしない",
        )
        items = _chain_items(_audit_json(plugin))
        assert any(
            i['severity'] == 'critical' and 'dispatch_gap' in i['message']
            for i in items
        ), f"Expected dispatch_gap critical, got {items}"


# ===========================================================================
# Normal case: dispatched + step あり -> finding なし
# ===========================================================================

class TestNormalCase:
    def setup_method(self):
        self.tmp = Path(tempfile.mkdtemp())

    def teardown_method(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_dispatched_step_no_finding(self):
        plugin = _make_plugin(
            self.tmp,
            workflow_calls=[{"atomic": "live-step", "step": "1"}],
            dispatched=["live-step"],
            components={"live-step": {"section": "commands", "type": "atomic"}},
            skill_body="step 1: live-step を実行",
        )
        items = _chain_items(_audit_json(plugin))
        assert all(i['severity'] == 'ok' for i in items), \
            f"Expected only ok findings, got {items}"


# ===========================================================================
# LLM 駆動例外: dispatch_mode=llm -> finding 抑制
# ===========================================================================

class TestLlmExemption:
    def setup_method(self):
        self.tmp = Path(tempfile.mkdtemp())

    def teardown_method(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_llm_driven_exempts_dispatch_gap(self):
        plugin = _make_plugin(
            self.tmp,
            workflow_calls=[{"composite": "llm-step", "step": "2"}],
            dispatched=[],
            components={
                "llm-step": {
                    "section": "commands",
                    "type": "composite",
                    "dispatch_mode": "llm",
                }
            },
            skill_body="何も書かない",
        )
        items = _chain_items(_audit_json(plugin))
        assert not any(
            i['severity'] in ('warning', 'critical') for i in items
        ), f"Expected no warnings/criticals, got {items}"

    def test_llm_driven_exempts_orphan_call(self):
        plugin = _make_plugin(
            self.tmp,
            workflow_calls=[{"composite": "llm-step"}],
            dispatched=[],
            components={
                "llm-step": {
                    "section": "commands",
                    "type": "composite",
                    "dispatch_mode": "llm",
                }
            },
            skill_body="何も書かない",
        )
        items = _chain_items(_audit_json(plugin))
        assert not any(
            i['severity'] in ('warning', 'critical') for i in items
        ), f"Expected no warnings/criticals (LLM exemption), got {items}"


# ===========================================================================
# SKILL.md 言及あり例外: target が SKILL.md に出現 -> finding 抑制
# ===========================================================================

class TestSkillMentionExemption:
    def setup_method(self):
        self.tmp = Path(tempfile.mkdtemp())

    def teardown_method(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_skill_mention_exempts_dispatch_gap(self):
        plugin = _make_plugin(
            self.tmp,
            workflow_calls=[{"atomic": "manual-step", "step": "1"}],
            dispatched=[],
            components={"manual-step": {"section": "commands", "type": "atomic"}},
            skill_body="Step 1: commands/manual-step.md を Read してください。",
        )
        items = _chain_items(_audit_json(plugin))
        assert not any(
            i['severity'] in ('warning', 'critical') for i in items
        ), f"Expected no warnings/criticals (skill mention), got {items}"


# ===========================================================================
# 後方互換: 既存 Section 1-8 が PASS する
# ===========================================================================

class TestBackwardCompatibility:
    def setup_method(self):
        self.tmp = Path(tempfile.mkdtemp())

    def teardown_method(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_section_1_through_8_still_present(self):
        plugin = _make_plugin(
            self.tmp,
            workflow_calls=[{"atomic": "live-step", "step": "1"}],
            dispatched=["live-step"],
            components={"live-step": {"section": "commands", "type": "atomic"}},
            skill_body="step 1: live-step を実行",
        )
        proc = _run(plugin, "--audit")
        for n in range(1, 10):
            section_headers = [
                f"## {n}.",
            ]
            assert any(h in proc.stdout for h in section_headers), \
                f"Section {n} header missing in output. stdout=\n{proc.stdout}"


# ===========================================================================
# --audit --section 9 で Section 9 のみ実行可能
# ===========================================================================

class TestSectionFilter:
    def setup_method(self):
        self.tmp = Path(tempfile.mkdtemp())

    def teardown_method(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_section_9_only_text(self):
        plugin = _make_plugin(
            self.tmp,
            workflow_calls=[{"atomic": "live-step", "step": "1"}],
            dispatched=["live-step"],
            components={"live-step": {"section": "commands", "type": "atomic"}},
            skill_body="step 1: live-step を実行",
        )
        proc = _run(plugin, "--audit", "--section", "9")
        assert "## 9. Chain Integrity" in proc.stdout
        # Section 1-8 ヘッダーは出力されない
        assert "## 1. Controller" not in proc.stdout
        assert "## 8. Prompt" not in proc.stdout

    def test_section_9_only_json(self):
        plugin = _make_plugin(
            self.tmp,
            workflow_calls=[{"atomic": "ghost-step", "step": "1"}],
            dispatched=[],
            components={"ghost-step": {"section": "commands", "type": "atomic"}},
            skill_body="何もしない",
        )
        proc = _run(plugin, "--audit", "--format", "json", "--section", "9")
        payload = json.loads(proc.stdout)
        items = payload.get("data", payload).get("items", [])
        assert items, f"Expected at least one item, got {items}"
        assert all(i['section'] == 'chain_integrity' for i in items), items


# ===========================================================================
# main runner
# ===========================================================================

if __name__ == "__main__":
    import traceback
    classes = [
        TestOrphanCall,
        TestDispatchGap,
        TestNormalCase,
        TestLlmExemption,
        TestSkillMentionExemption,
        TestBackwardCompatibility,
        TestSectionFilter,
    ]
    passed = failed = 0
    errors = []
    for cls in classes:
        for m in sorted(dir(cls)):
            if not m.startswith("test_"):
                continue
            inst = cls()
            if hasattr(inst, "setup_method"):
                inst.setup_method()
            try:
                getattr(inst, m)()
                passed += 1
                print(f"  PASS: {cls.__name__}.{m}")
            except Exception as e:
                failed += 1
                errors.append((f"{cls.__name__}.{m}", e))
                print(f"  FAIL: {cls.__name__}.{m}: {e}")
                traceback.print_exc()
            finally:
                if hasattr(inst, "teardown_method"):
                    inst.teardown_method()
    print(f"\nResults: {passed} passed, {failed} failed")
    sys.exit(0 if failed == 0 else 1)
