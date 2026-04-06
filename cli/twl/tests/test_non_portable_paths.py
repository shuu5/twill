#!/usr/bin/env python3
"""Tests for non-portable script path detection in deep-validate.

Coverage:
- bash scripts/ パターン検出
- source.*scripts/ パターン（CLAUDE_PLUGIN_ROOT なし）検出
- $SCRIPTS_ROOT パターン検出
- ${CLAUDE_PLUGIN_ROOT}/scripts/ パターンは false positive なし
- skills/*/SKILL.md と commands/*.md を走査
- openspec/, tests/, docs/ は検査対象外
"""

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


def _minimal_deps(plugin_dir: Path) -> None:
    deps = {
        "version": "3.0",
        "plugin": "test-plugin",
        "skills": {},
        "commands": {},
        "agents": {},
    }
    _write_deps(plugin_dir, deps)


def run_engine(plugin_dir: Path, *extra_args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, "-m", "twl"] + list(extra_args),
        cwd=str(plugin_dir),
        capture_output=True,
        text=True,
    )


class _BaseTest:
    def setup_method(self):
        self.tmpdir = Path(tempfile.mkdtemp())
        self.plugin_dir = self.tmpdir / "test-plugin"
        self.plugin_dir.mkdir()

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def _write_skill(self, skill_name: str, body: str) -> None:
        skill_dir = self.plugin_dir / "skills" / skill_name
        skill_dir.mkdir(parents=True, exist_ok=True)
        (skill_dir / "SKILL.md").write_text(
            f"---\nname: {skill_name}\ndescription: Test skill\n---\n\n{body}\n",
            encoding="utf-8",
        )

    def _write_command(self, cmd_name: str, body: str) -> None:
        cmd_dir = self.plugin_dir / "commands"
        cmd_dir.mkdir(parents=True, exist_ok=True)
        (cmd_dir / f"{cmd_name}.md").write_text(
            f"---\nname: {cmd_name}\ndescription: Test command\n---\n\n{body}\n",
            encoding="utf-8",
        )


class TestNonPortablePathsInSkills(_BaseTest):
    """skills/*/SKILL.md 内の非ポータブルパス検出"""

    def test_bash_scripts_pattern_detected(self):
        """GIVEN SKILL.md に bash scripts/chain-runner.sh が含まれる
        THEN deep-validate は [non-portable-path] CRITICAL を報告する"""
        _minimal_deps(self.plugin_dir)
        self._write_skill("my-skill", "```bash\nbash scripts/chain-runner.sh foo\n```")
        result = run_engine(self.plugin_dir, "--deep-validate")
        assert "[non-portable-path]" in result.stdout, result.stdout

    def test_source_scripts_without_plugin_root_detected(self):
        """GIVEN SKILL.md に source "$(git rev-parse --show-toplevel)/scripts/" が含まれる
        THEN deep-validate は [non-portable-path] CRITICAL を報告する"""
        _minimal_deps(self.plugin_dir)
        self._write_skill(
            "my-skill",
            '```bash\nsource "$(git rev-parse --show-toplevel)/scripts/lib.sh"\n```',
        )
        result = run_engine(self.plugin_dir, "--deep-validate")
        assert "[non-portable-path]" in result.stdout, result.stdout

    def test_scripts_root_variable_detected(self):
        """GIVEN SKILL.md に $SCRIPTS_ROOT が含まれる
        THEN deep-validate は [non-portable-path] CRITICAL を報告する"""
        _minimal_deps(self.plugin_dir)
        self._write_skill("my-skill", "```bash\nbash $SCRIPTS_ROOT/run.sh\n```")
        result = run_engine(self.plugin_dir, "--deep-validate")
        assert "[non-portable-path]" in result.stdout, result.stdout

    def test_portable_path_not_detected(self):
        """GIVEN SKILL.md に bash "${CLAUDE_PLUGIN_ROOT}/scripts/" が含まれる
        THEN deep-validate は [non-portable-path] を報告しない（false positive なし）"""
        _minimal_deps(self.plugin_dir)
        self._write_skill(
            "my-skill",
            '```bash\nbash "${CLAUDE_PLUGIN_ROOT}/scripts/chain-runner.sh" foo\n```',
        )
        result = run_engine(self.plugin_dir, "--deep-validate")
        assert "[non-portable-path]" not in result.stdout, result.stdout

    def test_source_with_plugin_root_not_detected(self):
        """GIVEN SKILL.md に source "${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh" が含まれる
        THEN deep-validate は [non-portable-path] を報告しない"""
        _minimal_deps(self.plugin_dir)
        self._write_skill(
            "my-skill",
            '```bash\nsource "${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh"\n```',
        )
        result = run_engine(self.plugin_dir, "--deep-validate")
        assert "[non-portable-path]" not in result.stdout, result.stdout


class TestNonPortablePathsInCommands(_BaseTest):
    """commands/*.md 内の非ポータブルパス検出"""

    def test_bash_scripts_in_command_detected(self):
        """GIVEN commands/*.md に bash scripts/ が含まれる
        THEN deep-validate は [non-portable-path] CRITICAL を報告する"""
        _minimal_deps(self.plugin_dir)
        self._write_command("my-cmd", "```bash\nbash scripts/helper.sh\n```")
        result = run_engine(self.plugin_dir, "--deep-validate")
        assert "[non-portable-path]" in result.stdout, result.stdout

    def test_portable_path_in_command_not_detected(self):
        """GIVEN commands/*.md に ${CLAUDE_PLUGIN_ROOT}/scripts/ が含まれる
        THEN deep-validate は [non-portable-path] を報告しない"""
        _minimal_deps(self.plugin_dir)
        self._write_command(
            "my-cmd",
            '```bash\nbash "${CLAUDE_PLUGIN_ROOT}/scripts/helper.sh"\n```',
        )
        result = run_engine(self.plugin_dir, "--deep-validate")
        assert "[non-portable-path]" not in result.stdout, result.stdout


class TestNonPortablePathsExclusions(_BaseTest):
    """検査対象外ディレクトリの確認"""

    def test_openspec_excluded(self):
        """GIVEN openspec/ 配下のファイルに bash scripts/ が含まれる
        THEN deep-validate は [non-portable-path] を報告しない"""
        _minimal_deps(self.plugin_dir)
        openspec_dir = self.plugin_dir / "openspec" / "changes" / "test-change" / "specs"
        openspec_dir.mkdir(parents=True)
        (openspec_dir / "spec.md").write_text(
            "```bash\nbash scripts/run.sh\n```\n", encoding="utf-8"
        )
        result = run_engine(self.plugin_dir, "--deep-validate")
        assert "[non-portable-path]" not in result.stdout, result.stdout

    def test_clean_plugin_passes(self):
        """GIVEN 非ポータブルパスが含まれない plugin
        THEN deep-validate は exit code 0 で終了する"""
        _minimal_deps(self.plugin_dir)
        self._write_skill(
            "clean-skill",
            '```bash\nbash "${CLAUDE_PLUGIN_ROOT}/scripts/chain-runner.sh" foo\n```',
        )
        result = run_engine(self.plugin_dir, "--deep-validate")
        assert result.returncode == 0, result.stdout + result.stderr
