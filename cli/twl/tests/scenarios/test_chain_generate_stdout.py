#!/usr/bin/env python3
"""Tests for chain generate stdout output (Template A/B/C).

Spec: openspec/changes/chain-generate/specs/chain-generate-stdout.md

These tests are TDD-style: they define expected behavior BEFORE implementation.
The `chain generate` subcommand will be invoked via `twl chain generate <chain-name>`.
"""

import shutil
import subprocess
import os
import sys
import tempfile
from pathlib import Path

import yaml

TWL_ENGINE = Path(__file__).parent.parent.parent / "src" / "twl" / "engine.py"


# ---------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------

def _write_deps(plugin_dir: Path, deps: dict) -> None:
    (plugin_dir / "deps.yaml").write_text(
        yaml.dump(deps, default_flow_style=False, allow_unicode=True, sort_keys=False),
        encoding="utf-8",
    )


def _create_component_files(plugin_dir: Path, deps: dict) -> None:
    """Create minimal markdown files for every component in deps."""
    for section in ("skills", "commands", "agents"):
        for name, data in deps.get(section, {}).items():
            path_str = data.get("path", "")
            if not path_str:
                continue
            file_path = plugin_dir / path_str
            file_path.parent.mkdir(parents=True, exist_ok=True)
            file_path.write_text(
                f"---\nname: {name}\ndescription: {data.get('description', 'Test')}\n---\n\nContent for {name}.\n",
                encoding="utf-8",
            )


def run_engine(plugin_dir: Path, *extra_args: str) -> subprocess.CompletedProcess:
    """Run twl-engine.py in the given plugin directory."""
    return subprocess.run(
        [sys.executable, "-m", "twl"] + list(extra_args),
        cwd=str(plugin_dir),
        capture_output=True,
        text=True,
    )


def make_v3_chain_fixture(tmpdir: Path) -> Path:
    """Create a v3.0 plugin fixture with a 4-step chain for testing generate.

    Chain: dev-pr-cycle
      steps: [workflow-setup, workflow-test-ready, apply, workflow-pr-cycle]

    Each component has a type (workflow/atomic), description, and path.
    workflow-setup calls workflow-test-ready (step "2"),
    workflow-test-ready calls apply (step "3"),
    apply calls workflow-pr-cycle (step "4").

    Components:
      - workflow-setup: workflow, chain=dev-pr-cycle
      - workflow-test-ready: workflow, chain=dev-pr-cycle, step_in={parent: workflow-setup}
      - apply: atomic command, chain=dev-pr-cycle, step_in={parent: workflow-test-ready}
      - workflow-pr-cycle: workflow, chain=dev-pr-cycle, step_in={parent: apply}
    """
    plugin_dir = tmpdir / "test-plugin-chain-gen"
    plugin_dir.mkdir()

    deps = {
        "version": "3.0",
        "plugin": "test-chain-gen",
        "chains": {
            "dev-pr-cycle": {
                "description": "Development PR cycle",
                "type": "A",
                "steps": [
                    "workflow-setup",
                    "workflow-test-ready",
                    "apply",
                    "workflow-pr-cycle",
                ],
            },
        },
        "skills": {
            "workflow-setup": {
                "type": "workflow",
                "path": "skills/workflow-setup/SKILL.md",
                "description": "開発準備ワークフロー",
                "chain": "dev-pr-cycle",
                "calls": [
                    {"workflow": "workflow-test-ready", "step": "2"},
                ],
            },
            "workflow-test-ready": {
                "type": "workflow",
                "path": "skills/workflow-test-ready/SKILL.md",
                "description": "テスト準備ワークフロー",
                "chain": "dev-pr-cycle",
                "step_in": {"parent": "workflow-setup"},
                "calls": [
                    {"atomic": "apply", "step": "3"},
                ],
            },
            "workflow-pr-cycle": {
                "type": "workflow",
                "path": "skills/workflow-pr-cycle/SKILL.md",
                "description": "PRサイクルワークフロー",
                "chain": "dev-pr-cycle",
                "step_in": {"parent": "apply"},
                "calls": [],
            },
        },
        "commands": {
            "apply": {
                "type": "atomic",
                "path": "commands/apply.md",
                "description": "変更適用コマンド",
                "chain": "dev-pr-cycle",
                "step_in": {"parent": "workflow-test-ready"},
                "calls": [
                    {"workflow": "workflow-pr-cycle", "step": "4"},
                ],
            },
        },
        "agents": {},
    }
    _write_deps(plugin_dir, deps)
    _create_component_files(plugin_dir, deps)
    return plugin_dir


def make_v2_fixture(tmpdir: Path) -> Path:
    """Create a v2.0 deps.yaml fixture (no chains support)."""
    plugin_dir = tmpdir / "test-plugin-v2"
    plugin_dir.mkdir()

    deps = {
        "version": "2.0",
        "plugin": "test-v2",
        "skills": {
            "my-skill": {
                "type": "workflow",
                "path": "skills/my-skill/SKILL.md",
                "description": "A skill",
                "calls": [],
            },
        },
        "commands": {},
        "agents": {},
    }
    _write_deps(plugin_dir, deps)
    _create_component_files(plugin_dir, deps)
    return plugin_dir


def make_step_in_fixture(tmpdir: Path) -> Path:
    """Create a fixture with step_in components for Template B testing.

    Includes:
      - comp-with-step: step_in={parent: workflow-pr-cycle, step: "3.5"}
      - comp-without-step: step_in={parent: controller-autopilot} (no step field)
    """
    plugin_dir = tmpdir / "test-plugin-step-in"
    plugin_dir.mkdir()

    deps = {
        "version": "3.0",
        "plugin": "test-step-in",
        "chains": {
            "main-chain": {
                "description": "Main chain",
                "steps": [
                    "workflow-pr-cycle",
                    "comp-with-step",
                    "controller-autopilot",
                    "comp-without-step",
                ],
            },
        },
        "skills": {
            "workflow-pr-cycle": {
                "type": "workflow",
                "path": "skills/workflow-pr-cycle/SKILL.md",
                "description": "PRサイクル",
                "chain": "main-chain",
                "calls": [
                    {"atomic": "comp-with-step", "step": "3.5"},
                ],
            },
            "controller-autopilot": {
                "type": "controller",
                "path": "skills/controller-autopilot/SKILL.md",
                "description": "オートパイロット",
                "chain": "main-chain",
                "calls": [
                    {"workflow": "comp-without-step"},
                ],
            },
        },
        "commands": {
            "comp-with-step": {
                "type": "atomic",
                "path": "commands/comp-with-step.md",
                "description": "Step付きコンポーネント",
                "chain": "main-chain",
                "step_in": {"parent": "workflow-pr-cycle", "step": "3.5"},
                "calls": [],
            },
            "comp-without-step": {
                "type": "atomic",
                "path": "commands/comp-without-step.md",
                "description": "Stepなしコンポーネント",
                "chain": "main-chain",
                "step_in": {"parent": "controller-autopilot"},
                "calls": [],
            },
        },
        "agents": {},
    }
    _write_deps(plugin_dir, deps)
    _create_component_files(plugin_dir, deps)
    return plugin_dir


# ---------------------------------------------------------------------------
# Test base class
# ---------------------------------------------------------------------------

class _ChainGenerateTestBase:
    """Shared setup/teardown for chain generate tests."""

    def setup_method(self):
        self.tmpdir = Path(tempfile.mkdtemp())

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)


# ===========================================================================
# Requirement: chain generate サブコマンド
# ===========================================================================

class TestChainGenerateSubcommand(_ChainGenerateTestBase):
    """Tests for `twl chain generate <chain-name>` subcommand basic behavior."""

    # --- Scenario: 正常な chain generate 実行 ---

    def test_normal_chain_generate_outputs_templates(self):
        """WHEN `twl chain generate dev-pr-cycle` を v3.0 deps.yaml のあるプラグインルートで実行する
        THEN dev-pr-cycle chain の Template A/B/C が stdout に出力される"""
        plugin_dir = make_v3_chain_fixture(self.tmpdir)

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle")

        assert result.returncode == 0, (
            f"Expected exit code 0 but got {result.returncode}\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
        # stdout にテンプレート出力が存在すること
        stdout = result.stdout
        assert len(stdout.strip()) > 0, "Expected non-empty stdout output"
        # Template A (チェックポイント) の出力が含まれること
        assert "チェックポイント" in stdout or "Checkpoint" in stdout or "Template A" in stdout, (
            f"Expected Template A content in stdout:\n{stdout}"
        )

    def test_normal_chain_generate_contains_all_template_types(self):
        """WHEN `twl chain generate dev-pr-cycle` を実行する
        THEN Template A, B, C 全てに対応する出力セクションが含まれる"""
        plugin_dir = make_v3_chain_fixture(self.tmpdir)

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle")

        assert result.returncode == 0, f"stderr: {result.stderr}"
        stdout = result.stdout
        # Template A: チェックポイント関連の出力
        # Template C: ライフサイクル図/テーブル関連の出力
        # 少なくとも複数のコンポーネントが出力に含まれること
        for comp_name in ["workflow-setup", "workflow-test-ready", "apply", "workflow-pr-cycle"]:
            assert comp_name in stdout, (
                f"Expected component '{comp_name}' in stdout output:\n{stdout}"
            )

    # --- Scenario: 存在しない chain 名 ---

    def test_nonexistent_chain_name_error(self):
        """WHEN `twl chain generate nonexistent-chain` を実行する
        THEN エラーメッセージ "Chain 'nonexistent-chain' not found in deps.yaml" が表示され、
        終了コード 1 で終了する"""
        plugin_dir = make_v3_chain_fixture(self.tmpdir)

        result = run_engine(plugin_dir, "chain", "generate", "nonexistent-chain")

        assert result.returncode == 1, (
            f"Expected exit code 1 but got {result.returncode}\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
        combined_output = result.stdout + result.stderr
        assert "nonexistent-chain" in combined_output, (
            f"Expected chain name in error output:\n{combined_output}"
        )
        assert "not found" in combined_output.lower() or "見つかりません" in combined_output, (
            f"Expected 'not found' in error output:\n{combined_output}"
        )

    def test_nonexistent_chain_error_message_format(self):
        """WHEN 存在しないchain名を指定する
        THEN エラーメッセージが正確に "Chain '<name>' not found in deps.yaml" 形式である"""
        plugin_dir = make_v3_chain_fixture(self.tmpdir)

        result = run_engine(plugin_dir, "chain", "generate", "does-not-exist")

        assert result.returncode == 1
        combined_output = result.stdout + result.stderr
        assert "Chain 'does-not-exist' not found in deps.yaml" in combined_output, (
            f"Expected exact error message format:\n{combined_output}"
        )

    # --- Scenario: v2.0 deps.yaml ---

    def test_v2_deps_yaml_error(self):
        """WHEN v2.0 の deps.yaml に対して `twl chain generate` を実行する
        THEN エラーメッセージ "chain generate requires deps.yaml v3.0+" が表示され、
        終了コード 1 で終了する"""
        plugin_dir = make_v2_fixture(self.tmpdir)

        result = run_engine(plugin_dir, "chain", "generate", "some-chain")

        assert result.returncode == 1, (
            f"Expected exit code 1 but got {result.returncode}\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
        combined_output = result.stdout + result.stderr
        assert "v3.0" in combined_output or "3.0" in combined_output, (
            f"Expected version requirement in error output:\n{combined_output}"
        )

    def test_v2_deps_yaml_exact_error_message(self):
        """WHEN v2.0のdeps.yamlに対して実行する
        THEN 正確に "chain generate requires deps.yaml v3.0+" が出力される"""
        plugin_dir = make_v2_fixture(self.tmpdir)

        result = run_engine(plugin_dir, "chain", "generate", "any-chain")

        assert result.returncode == 1
        combined_output = result.stdout + result.stderr
        assert "chain generate requires deps.yaml v3.0+" in combined_output, (
            f"Expected exact error message:\n{combined_output}"
        )

    def test_v2_deps_yaml_no_template_output(self):
        """WHEN v2.0のdeps.yamlでchain generateを実行する
        THEN テンプレート出力が一切含まれない（エラーメッセージのみ）"""
        plugin_dir = make_v2_fixture(self.tmpdir)

        result = run_engine(plugin_dir, "chain", "generate", "x")

        assert result.returncode == 1
        # Template content should not appear
        stdout = result.stdout
        assert "Template A" not in stdout
        assert "チェックポイント" not in stdout
        assert "ライフサイクル" not in stdout

    # --- Edge: version 2.9 should also fail ---

    def test_v2_9_deps_yaml_error(self):
        """WHEN version "2.9" のdeps.yamlに対してchain generateを実行する
        THEN v3.0未満としてエラーとなる"""
        plugin_dir = self.tmpdir / "test-plugin-v29"
        plugin_dir.mkdir()
        deps = {
            "version": "2.9",
            "plugin": "test-v29",
            "skills": {},
            "commands": {},
            "agents": {},
        }
        _write_deps(plugin_dir, deps)

        result = run_engine(plugin_dir, "chain", "generate", "x")

        assert result.returncode == 1
        combined_output = result.stdout + result.stderr
        assert "v3.0" in combined_output or "3.0" in combined_output

    # --- Edge: version 3.1 should succeed version check ---

    def test_v3_1_passes_version_check(self):
        """WHEN version "3.1" のdeps.yamlでchain generateを実行する
        THEN バージョンチェックは通過する（chain名不在エラーは別問題）"""
        plugin_dir = self.tmpdir / "test-plugin-v31"
        plugin_dir.mkdir()
        deps = {
            "version": "3.1",
            "plugin": "test-v31",
            "chains": {},
            "skills": {},
            "commands": {},
            "agents": {},
        }
        _write_deps(plugin_dir, deps)

        result = run_engine(plugin_dir, "chain", "generate", "nonexistent")

        combined_output = result.stdout + result.stderr
        # Should NOT get version error, but should get chain-not-found error
        assert "v3.0+" not in combined_output or "requires" not in combined_output, (
            "Version 3.1 should pass version check"
        )
        assert result.returncode == 1  # chain not found is fine

    # --- Edge: no chain-name argument ---

    def test_no_chain_name_argument_error(self):
        """WHEN `twl chain generate` をchain名なしで実行する
        THEN エラーが発生する（argparseのrequired引数エラーまたはカスタムエラー）"""
        plugin_dir = make_v3_chain_fixture(self.tmpdir)

        result = run_engine(plugin_dir, "chain", "generate")

        assert result.returncode != 0, (
            f"Expected non-zero exit code for missing chain name\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )

    # --- Edge: empty chains section ---

    def test_empty_chains_section(self):
        """WHEN deps.yaml v3.0 のchainsセクションが空の場合
        THEN 指定されたchain名が見つからずエラーとなる"""
        plugin_dir = self.tmpdir / "test-plugin-empty-chains"
        plugin_dir.mkdir()
        deps = {
            "version": "3.0",
            "plugin": "test-empty",
            "chains": {},
            "skills": {},
            "commands": {},
            "agents": {},
        }
        _write_deps(plugin_dir, deps)

        result = run_engine(plugin_dir, "chain", "generate", "any-chain")

        assert result.returncode == 1
        combined_output = result.stdout + result.stderr
        assert "not found" in combined_output.lower() or "見つかりません" in combined_output


# ===========================================================================
# Requirement: Template A チェックポイント生成
# ===========================================================================

class TestTemplateACheckpoint(_ChainGenerateTestBase):
    """Tests for Template A (checkpoint) generation."""

    # --- Scenario: 中間 step のチェックポイント ---

    def test_intermediate_step_checkpoint_references_next(self):
        """WHEN chain steps が [workflow-setup, workflow-test-ready, apply, workflow-pr-cycle]
        で workflow-setup のテンプレートを生成する
        THEN `/dev:workflow-test-ready` を参照するチェックポイントが生成される"""
        plugin_dir = make_v3_chain_fixture(self.tmpdir)

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle")

        assert result.returncode == 0, f"stderr: {result.stderr}"
        stdout = result.stdout
        # workflow-setup (step 1) の next は workflow-test-ready (step 2)
        assert "/dev:workflow-test-ready" in stdout, (
            f"Expected '/dev:workflow-test-ready' as next step reference in output:\n{stdout}"
        )

    def test_second_step_checkpoint_references_third(self):
        """WHEN workflow-test-ready (step 2) のチェックポイントを生成する
        THEN `/dev:apply` を参照するチェックポイントが生成される"""
        plugin_dir = make_v3_chain_fixture(self.tmpdir)

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle")

        assert result.returncode == 0, f"stderr: {result.stderr}"
        stdout = result.stdout
        assert "/dev:apply" in stdout, (
            f"Expected '/dev:apply' as next step reference:\n{stdout}"
        )

    def test_third_step_checkpoint_references_fourth(self):
        """WHEN apply (step 3) のチェックポイントを生成する
        THEN `/dev:workflow-pr-cycle` を参照するチェックポイントが生成される"""
        plugin_dir = make_v3_chain_fixture(self.tmpdir)

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle")

        assert result.returncode == 0, f"stderr: {result.stderr}"
        stdout = result.stdout
        assert "/dev:workflow-pr-cycle" in stdout, (
            f"Expected '/dev:workflow-pr-cycle' as next step reference:\n{stdout}"
        )

    def test_checkpoint_contains_must_header(self):
        """WHEN チェックポイントテンプレートを生成する
        THEN 出力に "チェックポイント" セクションヘッダーが含まれる"""
        plugin_dir = make_v3_chain_fixture(self.tmpdir)

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle")

        assert result.returncode == 0, f"stderr: {result.stderr}"
        stdout = result.stdout
        assert "チェックポイント" in stdout or "Checkpoint" in stdout, (
            f"Expected checkpoint header in output:\n{stdout}"
        )

    def test_checkpoint_contains_skill_tool_instruction(self):
        """WHEN チェックポイントテンプレートを生成する
        THEN "Skill tool で自動実行" の指示が含まれる"""
        plugin_dir = make_v3_chain_fixture(self.tmpdir)

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle")

        assert result.returncode == 0, f"stderr: {result.stderr}"
        stdout = result.stdout
        assert "Skill tool" in stdout or "自動実行" in stdout, (
            f"Expected 'Skill tool' instruction in output:\n{stdout}"
        )

    # --- Scenario: 最終 step のチェックポイント ---

    def test_final_step_checkpoint_completion_message(self):
        """WHEN chain の最終 step（workflow-pr-cycle）のテンプレートを生成する
        THEN チェーン完了メッセージ「チェーン完了」が生成される"""
        plugin_dir = make_v3_chain_fixture(self.tmpdir)

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle")

        assert result.returncode == 0, f"stderr: {result.stderr}"
        stdout = result.stdout
        assert "チェーン完了" in stdout, (
            f"Expected 'チェーン完了' completion message for final step:\n{stdout}"
        )

    def test_final_step_no_next_reference(self):
        """WHEN 最終stepのチェックポイントを生成する
        THEN /dev: 形式の次step参照ではなく、完了メッセージが出力される"""
        plugin_dir = make_v3_chain_fixture(self.tmpdir)

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle")

        assert result.returncode == 0, f"stderr: {result.stderr}"
        stdout = result.stdout
        # workflow-pr-cycle の後にはさらなる /dev: 参照があってはならない
        # (ただし他のstepの /dev: 参照は存在する)
        # チェーン完了メッセージがあることで代替検証
        assert "チェーン完了" in stdout

    # --- Edge: 1 step only chain ---

    def test_single_step_chain_shows_completion(self):
        """WHEN chain に step が 1 つしかない場合
        THEN その step のチェックポイントは完了メッセージとなる"""
        plugin_dir = self.tmpdir / "test-plugin-single-step"
        plugin_dir.mkdir()
        deps = {
            "version": "3.0",
            "plugin": "test-single",
            "chains": {
                "solo-chain": {
                    "description": "Single step chain",
                    "type": "A",
                    "steps": ["only-step"],
                },
            },
            "skills": {
                "only-step": {
                    "type": "workflow",
                    "path": "skills/only-step/SKILL.md",
                    "description": "唯一のステップ",
                    "chain": "solo-chain",
                    "calls": [],
                },
            },
            "commands": {},
            "agents": {},
        }
        _write_deps(plugin_dir, deps)
        _create_component_files(plugin_dir, deps)

        result = run_engine(plugin_dir, "chain", "generate", "solo-chain")

        assert result.returncode == 0, f"stderr: {result.stderr}"
        stdout = result.stdout
        assert "チェーン完了" in stdout, (
            f"Single step chain should show completion message:\n{stdout}"
        )


# ===========================================================================
# Requirement: Template B called-by 宣言行生成
# ===========================================================================

class TestTemplateBCalledBy(_ChainGenerateTestBase):
    """Tests for Template B (called-by declaration) generation."""

    # --- Scenario: step_in を持つコンポーネント ---

    def test_step_in_with_step_generates_called_by(self):
        """WHEN コンポーネントが step_in: {parent: workflow-pr-cycle, step: "3.5"} を持つ
        THEN `workflow-pr-cycle Step 3.5 から呼び出される。` が生成される"""
        plugin_dir = make_step_in_fixture(self.tmpdir)

        result = run_engine(plugin_dir, "chain", "generate", "main-chain")

        assert result.returncode == 0, f"stderr: {result.stderr}"
        stdout = result.stdout
        assert "workflow-pr-cycle Step 3.5 から呼び出される。" in stdout, (
            f"Expected called-by declaration with step number:\n{stdout}"
        )

    def test_step_in_with_step_exact_format(self):
        """WHEN step_in に parent と step がある
        THEN "{parent} Step {step} から呼び出される。" の正確な形式で出力される"""
        plugin_dir = make_step_in_fixture(self.tmpdir)

        result = run_engine(plugin_dir, "chain", "generate", "main-chain")

        assert result.returncode == 0, f"stderr: {result.stderr}"
        stdout = result.stdout
        # 正確な形式を検証
        assert "workflow-pr-cycle Step 3.5 から呼び出される。" in stdout

    # --- Scenario: step フィールドなしの step_in ---

    def test_step_in_without_step_generates_called_by_no_step(self):
        """WHEN コンポーネントが step_in: {parent: controller-autopilot} を持つ（step なし）
        THEN `controller-autopilot から呼び出される。` が生成される"""
        plugin_dir = make_step_in_fixture(self.tmpdir)

        result = run_engine(plugin_dir, "chain", "generate", "main-chain")

        assert result.returncode == 0, f"stderr: {result.stderr}"
        stdout = result.stdout
        assert "controller-autopilot から呼び出される。" in stdout, (
            f"Expected called-by declaration without step number:\n{stdout}"
        )

    def test_step_in_without_step_no_step_word(self):
        """WHEN step_in に step フィールドがない
        THEN "Step" という語が含まれない形式で出力される"""
        plugin_dir = make_step_in_fixture(self.tmpdir)

        result = run_engine(plugin_dir, "chain", "generate", "main-chain")

        assert result.returncode == 0, f"stderr: {result.stderr}"
        stdout = result.stdout
        # "controller-autopilot Step" が出力に含まれないこと
        # (controller-autopilot から呼び出される。には "Step" がないことを確認)
        assert "controller-autopilot から呼び出される。" in stdout
        # "controller-autopilot Step" が含まれていないことを確認
        lines = stdout.split("\n")
        for line in lines:
            if "controller-autopilot" in line and "から呼び出される" in line:
                assert "Step" not in line, (
                    f"Step field should not appear when step_in has no step: {line}"
                )

    # --- Edge: step_in with empty string step ---

    def test_step_in_with_empty_step_treated_as_no_step(self):
        """WHEN step_in の step が空文字列の場合
        THEN step なしとして扱われる"""
        plugin_dir = self.tmpdir / "test-plugin-empty-step"
        plugin_dir.mkdir()
        deps = {
            "version": "3.0",
            "plugin": "test-empty-step",
            "chains": {
                "test-chain": {
                    "description": "Test chain",
                    "steps": ["parent-comp", "child-comp"],
                },
            },
            "skills": {
                "parent-comp": {
                    "type": "workflow",
                    "path": "skills/parent-comp/SKILL.md",
                    "description": "Parent",
                    "chain": "test-chain",
                    "calls": [{"atomic": "child-comp"}],
                },
            },
            "commands": {
                "child-comp": {
                    "type": "atomic",
                    "path": "commands/child-comp.md",
                    "description": "Child",
                    "chain": "test-chain",
                    "step_in": {"parent": "parent-comp", "step": ""},
                    "calls": [],
                },
            },
            "agents": {},
        }
        _write_deps(plugin_dir, deps)
        _create_component_files(plugin_dir, deps)

        result = run_engine(plugin_dir, "chain", "generate", "test-chain")

        assert result.returncode == 0, f"stderr: {result.stderr}"
        stdout = result.stdout
        # step が空文字列の場合、"parent-comp から呼び出される。" 形式
        # "Step " が含まれないことを確認
        if "parent-comp" in stdout and "から呼び出される" in stdout:
            lines = stdout.split("\n")
            for line in lines:
                if "parent-comp" in line and "から呼び出される" in line:
                    assert "Step " not in line or "Step  " not in line, (
                        f"Empty step should not produce 'Step ' in output: {line}"
                    )


# ===========================================================================
# Requirement: Template C ライフサイクル図テーブル生成
# ===========================================================================

class TestTemplateCLifecycleTable(_ChainGenerateTestBase):
    """Tests for Template C (lifecycle diagram table) generation."""

    # --- Scenario: 4 step の chain ---

    def test_four_step_chain_generates_four_rows(self):
        """WHEN chain steps が [workflow-setup, workflow-test-ready, apply, workflow-pr-cycle]
        THEN 4行のテーブルが番号 1-4 で生成される"""
        plugin_dir = make_v3_chain_fixture(self.tmpdir)

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle")

        assert result.returncode == 0, f"stderr: {result.stderr}"
        stdout = result.stdout

        # テーブル行に番号 1, 2, 3, 4 が含まれること
        # Markdown テーブル形式: | 1 | workflow | workflow-setup | ... |
        for i in range(1, 5):
            assert f"| {i} |" in stdout, (
                f"Expected table row with number {i}:\n{stdout}"
            )

    def test_four_step_chain_contains_component_names(self):
        """WHEN 4 step の chain のテーブルを生成する
        THEN 各行にコンポーネント名が含まれる"""
        plugin_dir = make_v3_chain_fixture(self.tmpdir)

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle")

        assert result.returncode == 0, f"stderr: {result.stderr}"
        stdout = result.stdout
        for comp_name in ["workflow-setup", "workflow-test-ready", "apply", "workflow-pr-cycle"]:
            assert comp_name in stdout, (
                f"Expected component '{comp_name}' in table:\n{stdout}"
            )

    def test_four_step_chain_contains_types(self):
        """WHEN 4 step の chain のテーブルを生成する
        THEN 各行に型（workflow/atomic等）が含まれる"""
        plugin_dir = make_v3_chain_fixture(self.tmpdir)

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle")

        assert result.returncode == 0, f"stderr: {result.stderr}"
        stdout = result.stdout
        assert "workflow" in stdout, "Expected 'workflow' type in table"
        assert "atomic" in stdout, "Expected 'atomic' type in table"

    def test_four_step_chain_contains_descriptions(self):
        """WHEN 4 step の chain のテーブルを生成する
        THEN 各行に description が含まれる"""
        plugin_dir = make_v3_chain_fixture(self.tmpdir)

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle")

        assert result.returncode == 0, f"stderr: {result.stderr}"
        stdout = result.stdout
        assert "開発準備ワークフロー" in stdout, "Expected description in table"
        assert "変更適用コマンド" in stdout, "Expected description in table"

    def test_table_has_header_row(self):
        """WHEN ライフサイクル図テーブルを生成する
        THEN テーブルヘッダー行が含まれる"""
        plugin_dir = make_v3_chain_fixture(self.tmpdir)

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle")

        assert result.returncode == 0, f"stderr: {result.stderr}"
        stdout = result.stdout
        # テーブルヘッダーを検証
        assert "| # |" in stdout or "| #" in stdout, (
            f"Expected table header with '#' column:\n{stdout}"
        )

    def test_table_has_separator_row(self):
        """WHEN ライフサイクル図テーブルを生成する
        THEN テーブルセパレーター行（|---|---| 形式）が含まれる"""
        plugin_dir = make_v3_chain_fixture(self.tmpdir)

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle")

        assert result.returncode == 0, f"stderr: {result.stderr}"
        stdout = result.stdout
        assert "|---|" in stdout or "| --- |" in stdout or "|--" in stdout, (
            f"Expected Markdown table separator row:\n{stdout}"
        )

    # --- Edge: chain with component missing description ---

    def test_component_without_description_shows_empty(self):
        """WHEN コンポーネントに description がない場合
        THEN テーブル行は生成されるが description 欄は空またはデフォルト値"""
        plugin_dir = self.tmpdir / "test-plugin-no-desc"
        plugin_dir.mkdir()
        deps = {
            "version": "3.0",
            "plugin": "test-no-desc",
            "chains": {
                "test-chain": {
                    "description": "Test",
                    "type": "A",
                    "steps": ["no-desc-comp"],
                },
            },
            "skills": {
                "no-desc-comp": {
                    "type": "workflow",
                    "path": "skills/no-desc-comp/SKILL.md",
                    "chain": "test-chain",
                    "calls": [],
                },
            },
            "commands": {},
            "agents": {},
        }
        _write_deps(plugin_dir, deps)
        _create_component_files(plugin_dir, deps)

        result = run_engine(plugin_dir, "chain", "generate", "test-chain")

        assert result.returncode == 0, f"stderr: {result.stderr}"
        stdout = result.stdout
        assert "no-desc-comp" in stdout, (
            f"Component should still appear in table even without description:\n{stdout}"
        )
        assert "| 1 |" in stdout, f"Expected row number 1:\n{stdout}"

    # --- Edge: steps ordering matches deps.yaml order ---

    def test_table_row_numbering_matches_steps_order(self):
        """WHEN chain steps の順序が [workflow-setup, workflow-test-ready, apply, workflow-pr-cycle]
        THEN テーブル行の番号は steps 配列のインデックス+1 と一致する"""
        plugin_dir = make_v3_chain_fixture(self.tmpdir)

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle")

        assert result.returncode == 0, f"stderr: {result.stderr}"
        stdout = result.stdout

        # 各行が正しい番号と対応するコンポーネント名を持つことを検証
        expected_rows = [
            ("1", "workflow-setup"),
            ("2", "workflow-test-ready"),
            ("3", "apply"),
            ("4", "workflow-pr-cycle"),
        ]
        lines = stdout.split("\n")
        for num, comp_name in expected_rows:
            # テーブル行に番号とコンポーネント名が同じ行にあること
            found = False
            for line in lines:
                if f"| {num} |" in line and comp_name in line:
                    found = True
                    break
            assert found, (
                f"Expected table row with number {num} and component '{comp_name}':\n{stdout}"
            )
