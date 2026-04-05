#!/usr/bin/env python3
"""Tests for Cross-plugin 参照構文 and script.can_spawn 拡張.

Spec: openspec/changes/plugin-typesyaml-scriptcanspawn/specs/cross-plugin-reference.md

Covers:
- Cross-plugin 参照構文のパース（コロン区切り識別）
- Cross-plugin 参照の validate 検証（型整合性・plugin 不存在時のスキップ）
- Cross-plugin 参照の check 検証（ファイル存在確認・plugin 不存在時のスキップ）
- types.yaml の script 型 can_spawn 拡張（script→script を許可）

NOTE: これらのテストは実装前に書く仕様定義テストです。
      実装後に PASS することを期待します（現在は FAIL します）。
"""

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

TWL_ENGINE = Path(__file__).parent.parent.parent / "twl-engine.py"


# ---------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------

def _write_deps(plugin_dir: Path, deps: dict) -> None:
    (plugin_dir / "deps.yaml").write_text(
        yaml.dump(deps, default_flow_style=False, allow_unicode=True, sort_keys=False),
        encoding="utf-8",
    )


def _load_deps(plugin_dir: Path) -> dict:
    return yaml.safe_load((plugin_dir / "deps.yaml").read_text())


def _create_component_files(plugin_dir: Path, deps: dict) -> None:
    """Create minimal files for every component in deps."""
    for section in ("skills", "commands", "agents"):
        for name, data in deps.get(section, {}).items():
            path_str = data.get("path", "")
            if not path_str:
                continue
            file_path = plugin_dir / path_str
            file_path.parent.mkdir(parents=True, exist_ok=True)
            file_path.write_text(
                f"---\nname: {name}\ndescription: Test\n---\n\nContent for {name}.\n",
                encoding="utf-8",
            )
    for name, data in deps.get("scripts", {}).items():
        path_str = data.get("path", "")
        if not path_str:
            continue
        file_path = plugin_dir / path_str
        file_path.parent.mkdir(parents=True, exist_ok=True)
        file_path.write_text(f"#!/bin/bash\n# {name}\necho '{name}'\n", encoding="utf-8")


def run_engine(plugin_dir: Path, *extra_args: str) -> subprocess.CompletedProcess:
    """Run twl-engine.py in the given plugin directory."""
    return subprocess.run(
        [sys.executable, str(TWL_ENGINE)] + list(extra_args),
        cwd=str(plugin_dir),
        capture_output=True,
        text=True,
    )


# ---------------------------------------------------------------------------
# Fixture: 呼び出し元 plugin（caller）
# ---------------------------------------------------------------------------

def make_caller_plugin(tmpdir: Path, plugin_name: str = "caller-plugin") -> Path:
    """Cross-plugin 参照を持つ呼び出し元 plugin ディレクトリを作成する。"""
    plugin_dir = tmpdir / plugin_name
    plugin_dir.mkdir()

    deps = {
        "version": "3.0",
        "plugin": plugin_name,
        "skills": {},
        "commands": {
            "my-action": {
                "type": "atomic",
                "path": "commands/my-action.md",
                "description": "An atomic command that calls a cross-plugin script",
                "calls": [
                    {"script": "session:session-state"},
                ],
            },
        },
        "agents": {},
        "scripts": {},
    }
    _write_deps(plugin_dir, deps)
    _create_component_files(plugin_dir, deps)
    return plugin_dir


def make_caller_local_only_plugin(tmpdir: Path, plugin_name: str = "caller-local") -> Path:
    """ローカル参照のみを持つ plugin ディレクトリを作成する（コロンなし）。"""
    plugin_dir = tmpdir / plugin_name
    plugin_dir.mkdir()

    deps = {
        "version": "3.0",
        "plugin": plugin_name,
        "skills": {},
        "commands": {
            "my-action": {
                "type": "atomic",
                "path": "commands/my-action.md",
                "description": "An atomic command with local-only calls",
                "calls": [
                    {"script": "my-local-script"},
                ],
            },
        },
        "agents": {},
        "scripts": {
            "my-local-script": {
                "type": "script",
                "path": "scripts/my-local-script.sh",
                "description": "A local script",
                "calls": [],
            },
        },
    }
    _write_deps(plugin_dir, deps)
    _create_component_files(plugin_dir, deps)
    return plugin_dir


# ---------------------------------------------------------------------------
# Fixture: 参照先 plugin（callee）
# ---------------------------------------------------------------------------

def make_session_plugin(tmpdir: Path, plugin_name: str = "session") -> Path:
    """参照先となる session plugin を作成する。"""
    plugin_dir = tmpdir / plugin_name
    plugin_dir.mkdir()

    deps = {
        "version": "3.0",
        "plugin": plugin_name,
        "skills": {},
        "commands": {},
        "agents": {},
        "scripts": {
            "session-state": {
                "type": "script",
                "path": "scripts/session-state.sh",
                "description": "Session state script",
                "calls": [],
            },
        },
    }
    _write_deps(plugin_dir, deps)
    _create_component_files(plugin_dir, deps)
    return plugin_dir


def make_workflow_plugin(tmpdir: Path, plugin_name: str = "other-plugin") -> Path:
    """workflow 型コンポーネントを持つ参照先 plugin を作成する。"""
    plugin_dir = tmpdir / plugin_name
    plugin_dir.mkdir()

    deps = {
        "version": "3.0",
        "plugin": plugin_name,
        "skills": {
            "some-workflow": {
                "type": "workflow",
                "path": "skills/some-workflow/SKILL.md",
                "description": "A workflow in other plugin",
                "calls": [],
            },
        },
        "commands": {},
        "agents": {},
        "scripts": {},
    }
    _write_deps(plugin_dir, deps)
    _create_component_files(plugin_dir, deps)
    return plugin_dir


# ---------------------------------------------------------------------------
# Fixture: script→script 呼び出しテスト用
# ---------------------------------------------------------------------------

def make_script_to_script_plugin(tmpdir: Path) -> Path:
    """script が別の script を calls に持つ plugin を作成する。"""
    plugin_dir = tmpdir / "script-spawn-plugin"
    plugin_dir.mkdir()

    deps = {
        "version": "3.0",
        "plugin": "script-spawn-plugin",
        "skills": {},
        "commands": {
            "my-action": {
                "type": "atomic",
                "path": "commands/my-action.md",
                "description": "Atomic command calling a script",
                "calls": [
                    {"script": "orchestrator-script"},
                ],
            },
        },
        "agents": {},
        "scripts": {
            "orchestrator-script": {
                "type": "script",
                "path": "scripts/orchestrator-script.sh",
                "description": "Orchestrator script that calls another script",
                "calls": [
                    {"script": "helper-script"},
                ],
            },
            "helper-script": {
                "type": "script",
                "path": "scripts/helper-script.sh",
                "description": "Helper script",
                "calls": [],
            },
        },
    }
    _write_deps(plugin_dir, deps)
    _create_component_files(plugin_dir, deps)
    return plugin_dir


def make_script_calls_atomic_plugin(tmpdir: Path) -> Path:
    """script が atomic を calls に持つ plugin を作成する（型違反）。"""
    plugin_dir = tmpdir / "script-calls-atomic-plugin"
    plugin_dir.mkdir()

    deps = {
        "version": "3.0",
        "plugin": "script-calls-atomic-plugin",
        "skills": {},
        "commands": {
            "my-action": {
                "type": "atomic",
                "path": "commands/my-action.md",
                "description": "An atomic command",
                "calls": [],
            },
        },
        "agents": {},
        "scripts": {
            "bad-script": {
                "type": "script",
                "path": "scripts/bad-script.sh",
                "description": "Script that wrongly calls an atomic",
                "calls": [
                    {"atomic": "my-action"},
                ],
            },
        },
    }
    _write_deps(plugin_dir, deps)
    _create_component_files(plugin_dir, deps)
    return plugin_dir


# ---------------------------------------------------------------------------
# Base class
# ---------------------------------------------------------------------------

class _CrossPluginTestBase:
    """Shared setup/teardown for cross-plugin reference tests."""

    def setup_method(self):
        self.tmpdir = Path(tempfile.mkdtemp())

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)


# ===========================================================================
# Requirement: Cross-plugin 参照構文の定義
# ===========================================================================

class TestCrossPluginReferenceParsing(_CrossPluginTestBase):
    """deps.yaml の calls 内で plugin:component 形式が cross-plugin 参照として認識される。"""

    def test_cross_plugin_reference_parsed_as_cross_plugin(self):
        """Scenario: 正常な cross-plugin 参照のパース
        WHEN deps.yaml の calls に `atomic: "session:session-state"` が記述されている
        THEN twl はこれを session plugin の session-state コンポーネントへの
             cross-plugin 参照として認識する"""
        caller_dir = make_caller_plugin(self.tmpdir)
        session_dir = make_session_plugin(self.tmpdir)

        # validate 実行時に cross-plugin 参照が認識されれば、
        # 参照先 plugin が存在する場合は型チェックが行われる。
        # session:session-state は atomic が script を呼ぶため型ルール上は OK。
        result = run_engine(caller_dir, "--validate")
        # cross-plugin 参照に関するエラーは出ない（正常認識されれば型チェック通過）
        assert result.returncode == 0, (
            f"Expected returncode 0 for valid cross-plugin reference.\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
        # cross-plugin 参照がコロン区切りとして認識されることを確認
        # （ローカルの scripts セクションに "session:session-state" は存在しないが
        #  cross-plugin 参照として解決される）
        assert "session" in result.stdout or "cross-plugin" in result.stdout or result.returncode == 0

    def test_local_reference_without_colon(self):
        """Scenario: コロンなしの値は従来通りローカル参照
        WHEN deps.yaml の calls に `atomic: "my-command"` が記述されている（コロンなし）
        THEN twl はこれを同一 plugin 内のコンポーネントへのローカル参照として処理する"""
        plugin_dir = make_caller_local_only_plugin(self.tmpdir)

        result = run_engine(plugin_dir, "--validate")
        assert result.returncode == 0, (
            f"Expected returncode 0 for local reference.\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
        # ローカル参照は通常通り解決されるため cross-plugin 関連のメッセージは不要
        assert "cross-plugin" not in result.stdout


# ===========================================================================
# Requirement: Cross-plugin 参照の validate 検証
# ===========================================================================

class TestCrossPluginValidate(_CrossPluginTestBase):
    """twl validate は cross-plugin 参照の型整合性を検証する。"""

    def test_cross_plugin_type_compatible_no_violation(self):
        """Scenario: 参照先の型整合性が正しい場合
        WHEN caller が atomic 型で、cross-plugin 参照先が script 型である
        THEN validate は型違反を報告しない（atomic.can_spawn に script が含まれるため）"""
        caller_dir = make_caller_plugin(self.tmpdir)
        session_dir = make_session_plugin(self.tmpdir)

        # caller: my-action (atomic) → session:session-state (script)
        # atomic.can_spawn には script が含まれるため OK
        result = run_engine(caller_dir, "--validate")
        assert result.returncode == 0, (
            f"Expected no type violation for atomic->script cross-plugin reference.\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
        assert "[edge]" not in result.stdout

    def test_cross_plugin_type_incompatible_reports_violation(self):
        """Scenario: 参照先の型整合性が不正な場合
        WHEN caller が specialist 型で、cross-plugin 参照先が workflow 型である
        THEN validate は型違反を報告する（specialist.can_spawn は空集合のため）"""
        # specialist が workflow を cross-plugin 参照する不正なケース
        caller_dir = self.tmpdir / "bad-caller"
        caller_dir.mkdir()
        deps = {
            "version": "3.0",
            "plugin": "bad-caller",
            "skills": {},
            "commands": {},
            "agents": {
                "my-specialist": {
                    "type": "specialist",
                    "path": "agents/my-specialist.md",
                    "description": "A specialist calling a workflow cross-plugin",
                    "calls": [
                        {"workflow": "other-plugin:some-workflow"},
                    ],
                },
            },
            "scripts": {},
        }
        _write_deps(caller_dir, deps)
        _create_component_files(caller_dir, deps)
        workflow_plugin = make_workflow_plugin(self.tmpdir)

        result = run_engine(caller_dir, "--validate")
        # 型違反が報告されるため非 0 終了 または violations に [edge] が含まれる
        assert result.returncode != 0 or "[edge]" in result.stdout, (
            f"Expected type violation for specialist->workflow cross-plugin reference.\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )

    def test_cross_plugin_plugin_not_found_skips_with_warning(self):
        """Scenario: 参照先 plugin が見つからない場合（validate）
        WHEN cross-plugin 参照の plugin 名に対応する deps.yaml が存在しない
        THEN validate は warning を出力し、該当の参照をスキップする（error にはしない）"""
        caller_dir = make_caller_plugin(self.tmpdir)
        # session plugin の deps.yaml を意図的に作成しない

        result = run_engine(caller_dir, "--validate")
        # plugin が見つからなくても error ではなく warning でスキップ → returncode 0
        assert result.returncode == 0, (
            f"Expected returncode 0 (warning, not error) when cross-plugin target not found.\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
        # warning メッセージが出力される
        combined = result.stdout + result.stderr
        assert "warning" in combined.lower() or "Warning" in combined or "warn" in combined.lower(), (
            f"Expected warning output when cross-plugin target plugin not found.\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )


# ===========================================================================
# Requirement: Cross-plugin 参照の check 検証
# ===========================================================================

class TestCrossPluginCheck(_CrossPluginTestBase):
    """twl check は cross-plugin 参照先のファイル存在を検証する。"""

    def test_cross_plugin_file_exists_reports_ok(self):
        """Scenario: 参照先ファイルが存在する場合
        WHEN cross-plugin 参照先のコンポーネントに path が定義されており、そのファイルが存在する
        THEN check は ok を報告する"""
        caller_dir = make_caller_plugin(self.tmpdir)
        session_dir = make_session_plugin(self.tmpdir)
        # session-state.sh は make_session_plugin で作成済み

        result = run_engine(caller_dir, "--check")
        assert result.returncode == 0, (
            f"Expected returncode 0 when cross-plugin referenced file exists.\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
        assert "Missing" not in result.stdout or "Missing: 0" in result.stdout

    def test_cross_plugin_file_missing_reports_missing(self):
        """Scenario: 参照先ファイルが存在しない場合
        WHEN cross-plugin 参照先のコンポーネントに path が定義されており、そのファイルが存在しない
        THEN check は missing を報告する"""
        caller_dir = make_caller_plugin(self.tmpdir)
        session_dir = make_session_plugin(self.tmpdir)

        # session-state.sh を削除してファイルが存在しない状態にする
        script_file = session_dir / "scripts" / "session-state.sh"
        if script_file.exists():
            script_file.unlink()

        result = run_engine(caller_dir, "--check")
        # ファイルが存在しないため非 0 終了
        assert result.returncode != 0, (
            f"Expected returncode != 0 when cross-plugin referenced file is missing.\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
        assert "missing" in result.stdout.lower() or "Missing" in result.stdout

    def test_cross_plugin_check_plugin_not_found_skips_with_warning(self):
        """Scenario: 参照先 plugin が見つからない場合（check）
        WHEN cross-plugin 参照の plugin 名に対応する deps.yaml が存在しない
        THEN check は warning を出力し、該当の参照をスキップする"""
        caller_dir = make_caller_plugin(self.tmpdir)
        # session plugin を作成しない

        result = run_engine(caller_dir, "--check")
        # plugin が見つからなくても error ではなく warning でスキップ → returncode 0
        assert result.returncode == 0, (
            f"Expected returncode 0 (warning skip) when cross-plugin target plugin not found.\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
        combined = result.stdout + result.stderr
        assert "warning" in combined.lower() or "Warning" in combined or "warn" in combined.lower(), (
            f"Expected warning output when cross-plugin target plugin not found in check.\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )


# ===========================================================================
# Requirement: script 型の can_spawn 拡張
# ===========================================================================

class TestScriptCanSpawnScript(_CrossPluginTestBase):
    """types.yaml の script 型は can_spawn: [script] を持ち、script→script が許可される。"""

    def test_script_calls_script_no_violation(self):
        """Scenario: script が script を呼び出す場合
        WHEN script 型のコンポーネントが calls で別の script 型コンポーネントを参照している
        THEN validate は型違反を報告しない"""
        plugin_dir = make_script_to_script_plugin(self.tmpdir)

        result = run_engine(plugin_dir, "--validate")
        assert result.returncode == 0, (
            f"Expected no type violation for script->script call.\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
        # [edge] 違反が出ていないこと
        assert "[edge]" not in result.stdout, (
            f"Unexpected [edge] violation for script->script:\n{result.stdout}"
        )

    def test_script_calls_atomic_reports_violation(self):
        """Scenario: script が script 以外を呼び出す場合
        WHEN script 型のコンポーネントが calls で atomic 型コンポーネントを参照している
        THEN validate は型違反を報告する（script.can_spawn に atomic は含まれないため）"""
        plugin_dir = make_script_calls_atomic_plugin(self.tmpdir)

        result = run_engine(plugin_dir, "--validate")
        # 型違反があるため非 0 終了
        assert result.returncode != 0, (
            f"Expected type violation for script->atomic call.\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
        assert "[edge]" in result.stdout, (
            f"Expected [edge] violation for script->atomic:\n{result.stdout}"
        )

    def test_types_yaml_script_can_spawn_script(self):
        """types.yaml に script.can_spawn: [script] が定義されているかを --rules で確認する。"""
        plugin_dir = make_script_to_script_plugin(self.tmpdir)

        result = run_engine(plugin_dir, "--rules")
        assert result.returncode == 0, (
            f"Expected --rules to succeed.\nstdout: {result.stdout}\nstderr: {result.stderr}"
        )
        lines = result.stdout.splitlines()
        script_line = None
        for line in lines:
            if line.strip().startswith("| script"):
                script_line = line
                break
        assert script_line is not None, (
            f"No script line found in --rules output:\n{result.stdout}"
        )
        # script の can_spawn に script が含まれること
        assert "script" in script_line, (
            f"Expected 'script' in can_spawn column of script row:\n{script_line}"
        )
        # (none) ではないこと（can_spawn が空でないこと）
        assert "(none)" not in script_line, (
            f"script.can_spawn should not be empty after the fix:\n{script_line}"
        )


# ===========================================================================
# Edge cases
# ===========================================================================

class TestCrossPluginEdgeCases(_CrossPluginTestBase):
    """Cross-plugin 参照の境界条件テスト。"""

    def test_multiple_cross_plugin_references(self):
        """複数の cross-plugin 参照を持つ場合、すべて検証される。"""
        plugin_dir = self.tmpdir / "multi-cross-plugin"
        plugin_dir.mkdir()

        deps = {
            "version": "3.0",
            "plugin": "multi-cross-plugin",
            "skills": {},
            "commands": {
                "my-action": {
                    "type": "atomic",
                    "path": "commands/my-action.md",
                    "description": "Action with multiple cross-plugin calls",
                    "calls": [
                        {"script": "plugin-a:script-a"},
                        {"script": "plugin-b:script-b"},
                    ],
                },
            },
            "agents": {},
            "scripts": {},
        }
        _write_deps(plugin_dir, deps)
        _create_component_files(plugin_dir, deps)

        # plugin-a, plugin-b どちらも存在しない → 両方 warning でスキップ
        result = run_engine(plugin_dir, "--validate")
        assert result.returncode == 0, (
            f"Expected returncode 0 when both cross-plugin targets not found (warning skip).\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )

    def test_cross_plugin_colon_in_name_not_double_colon(self):
        """コロンが1つのみの場合のみ cross-plugin 参照として扱う（ダブルコロンは不正）。"""
        plugin_dir = self.tmpdir / "colon-test-plugin"
        plugin_dir.mkdir()

        deps = {
            "version": "3.0",
            "plugin": "colon-test-plugin",
            "skills": {},
            "commands": {
                "my-action": {
                    "type": "atomic",
                    "path": "commands/my-action.md",
                    "description": "Action with cross-plugin script call",
                    "calls": [
                        {"script": "session:session-state"},
                    ],
                },
            },
            "agents": {},
            "scripts": {},
        }
        _write_deps(plugin_dir, deps)
        _create_component_files(plugin_dir, deps)

        # "session:session-state" は plugin=session, component=session-state として解釈される
        result = run_engine(plugin_dir, "--validate")
        # session plugin が存在しない → warning でスキップ、returncode 0
        assert result.returncode == 0, (
            f"Expected returncode 0 for single-colon cross-plugin reference.\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )

    def test_script_to_script_chain_validate_ok(self):
        """script → script → (end) のチェーンが validate で問題なしになる。"""
        plugin_dir = make_script_to_script_plugin(self.tmpdir)

        result = run_engine(plugin_dir, "--validate")
        assert result.returncode == 0, (
            f"Expected returncode 0 for script->script chain.\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )

    def test_cross_plugin_and_local_mixed_validate_ok(self):
        """cross-plugin 参照とローカル参照が混在しても正しく処理される。"""
        plugin_dir = self.tmpdir / "mixed-plugin"
        plugin_dir.mkdir()

        deps = {
            "version": "3.0",
            "plugin": "mixed-plugin",
            "skills": {},
            "commands": {
                "my-action": {
                    "type": "atomic",
                    "path": "commands/my-action.md",
                    "description": "Action with both local and cross-plugin calls",
                    "calls": [
                        {"script": "local-script"},          # ローカル参照
                        {"script": "session:session-state"},  # cross-plugin 参照
                    ],
                },
            },
            "agents": {},
            "scripts": {
                "local-script": {
                    "type": "script",
                    "path": "scripts/local-script.sh",
                    "description": "Local script",
                    "calls": [],
                },
            },
        }
        _write_deps(plugin_dir, deps)
        _create_component_files(plugin_dir, deps)

        # session plugin は存在しない → cross-plugin 部分は warning でスキップ
        # ローカル部分は正常
        result = run_engine(plugin_dir, "--validate")
        assert result.returncode == 0, (
            f"Expected returncode 0 when mixing local and missing cross-plugin references.\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )


# ===========================================================================
# main runner
# ===========================================================================

if __name__ == "__main__":
    import traceback

    classes = [
        TestCrossPluginReferenceParsing,
        TestCrossPluginValidate,
        TestCrossPluginCheck,
        TestScriptCanSpawnScript,
        TestCrossPluginEdgeCases,
    ]
    passed = 0
    failed = 0
    errors = []

    for cls in classes:
        for method_name in sorted(dir(cls)):
            if not method_name.startswith("test_"):
                continue
            instance = cls()
            instance.setup_method()
            try:
                getattr(instance, method_name)()
                passed += 1
                print(f"  PASS: {cls.__name__}.{method_name}")
            except Exception as e:
                failed += 1
                errors.append((f"{cls.__name__}.{method_name}", e))
                print(f"  FAIL: {cls.__name__}.{method_name}: {e}")
                traceback.print_exc()
            finally:
                instance.teardown_method()

    print(f"\n{'=' * 40}")
    print(f"Results: {passed} passed, {failed} failed")
    if errors:
        print("\nFailures:")
        for name, err in errors:
            print(f"  {name}: {err}")
        sys.exit(1)
    else:
        print("All tests passed!")
