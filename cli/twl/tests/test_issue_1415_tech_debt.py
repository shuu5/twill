"""Tests for Issue #1415: tech-debt cleanup of test_mcp_lifecycle.py.

TDD RED フェーズ用テスト。
実装前は全テストが FAIL する（意図的 RED）。

AC1: patch("builtins.open", ...) 全10箇所を
     patch("twl.mcp_server.lifecycle.open", ...) または mock_open ベースに置換
AC2: conftest.py に make_mcp_json fixture が定義されている
AC3: 各クラスの _make_mcp_json() メソッドが削除され共有 fixture を利用している
AC4: test_mcp_lifecycle.py の行数が 500行以下に削減されている
AC5: pytest が PR #1412 と同じテスト数かつ全 PASS する（構造確認）
AC6: ac-test-mapping-1398.yaml のカバレッジが維持されている（mapping 確認）
"""

import subprocess
import sys
from pathlib import Path

import pytest

TESTS_DIR = Path(__file__).resolve().parent
REPO_ROOT = TESTS_DIR.parent.parent.parent
TWL_TESTS = TESTS_DIR
LIFECYCLE_TEST_FILE = TESTS_DIR / "test_mcp_lifecycle.py"
CONFTEST_FILE = TESTS_DIR / "conftest.py"
MAPPING_1398 = TESTS_DIR / "ac-test-mapping-1398.yaml"


# ---------------------------------------------------------------------------
# AC1: patch("builtins.open", ...) がテスト本体から消えていること
# ---------------------------------------------------------------------------


class TestAC1PatchTarget:
    """AC1: test_mcp_lifecycle.py 内の patch("builtins.open", ...) が
    モジュール限定パッチ（patch("twl.mcp_server.lifecycle.open", ...)）
    または mock_open ベースの形式に置き換えられている。

    RED: 現状は builtins.open が10箇所存在するため FAIL する。
    """

    def test_ac1_no_builtins_open_in_lifecycle_test(self):
        # AC: test_mcp_lifecycle.py に 'builtins.open' が存在しないこと
        # RED: 現状は10箇所存在するため FAIL する
        content = LIFECYCLE_TEST_FILE.read_text()
        occurrences = content.count('builtins.open')
        assert occurrences == 0, (
            f"test_mcp_lifecycle.py に 'builtins.open' が {occurrences} 箇所残存している。"
            f"patch('twl.mcp_server.lifecycle.open', ...) または mock_open ベースへの"
            f"置換が必要 (AC1 未実装)"
        )

    def test_ac1_module_scoped_patch_used(self):
        # AC: モジュール限定パッチ（lifecycle.open）または mock_open が使用されていること
        # RED: 現状は builtins.open のみで lifecycle.open / mock_open が存在しない
        content = LIFECYCLE_TEST_FILE.read_text()
        has_lifecycle_open = "twl.mcp_server.lifecycle.open" in content
        has_mock_open = "mock_open" in content
        assert has_lifecycle_open or has_mock_open, (
            "test_mcp_lifecycle.py に patch('twl.mcp_server.lifecycle.open', ...) "
            "または mock_open の使用がない。"
            "builtins.open への置換が完了していない (AC1 未実装)"
        )

    def test_ac1_builtins_open_count_is_zero(self):
        # AC: grep で builtins.open が0件
        # RED: 現在10件存在するため FAIL する
        result = subprocess.run(
            ["grep", "-c", "builtins.open", str(LIFECYCLE_TEST_FILE)],
            capture_output=True,
            text=True,
        )
        # grep -c が 0 件の場合は returncode=1 + stdout="0\n"
        count = int(result.stdout.strip()) if result.stdout.strip().isdigit() else 0
        assert count == 0, (
            f"grep: builtins.open が {count} 箇所存在 (AC1 未実装: 0 になるまで置換必要)"
        )


# ---------------------------------------------------------------------------
# AC2: conftest.py に make_mcp_json fixture が存在すること
# ---------------------------------------------------------------------------


class TestAC2ConfTestFixture:
    """AC2: conftest.py に make_mcp_json fixture（または同等の共有ヘルパー）が
    (command: str, args: list[str] | None = None, tmp_path: Path) -> Path
    シグネチャで定義されている。

    RED: 現状は conftest.py に make_mcp_json が存在しないため FAIL する。
    """

    def test_ac2_make_mcp_json_exists_in_conftest(self):
        # AC: conftest.py に make_mcp_json という名前が存在すること
        # RED: 現状は存在しないため FAIL する
        content = CONFTEST_FILE.read_text()
        assert "make_mcp_json" in content, (
            "conftest.py に make_mcp_json fixture が存在しない (AC2 未実装)"
        )

    def test_ac2_make_mcp_json_is_fixture(self):
        # AC: make_mcp_json が @pytest.fixture デコレータを持つ関数であること
        # RED: 現状は存在しないため FAIL する
        content = CONFTEST_FILE.read_text()
        assert "make_mcp_json" in content, (
            "conftest.py に make_mcp_json が存在しない (AC2 未実装)"
        )
        # fixture デコレータが存在すること
        assert "@pytest.fixture" in content, (
            "conftest.py に @pytest.fixture デコレータが存在しない (AC2 未実装)"
        )
        # make_mcp_json がfixture として定義されていること
        has_fixture_def = (
            "def make_mcp_json" in content
            or "fixture" in content and "make_mcp_json" in content
        )
        assert has_fixture_def, (
            "conftest.py に def make_mcp_json が存在しない (AC2 未実装)"
        )

    def test_ac2_fixture_signature_has_command_param(self):
        # AC: make_mcp_json は command パラメータを受け付けること
        # RED: 現状は存在しないため FAIL する
        content = CONFTEST_FILE.read_text()
        # def make_mcp_json の行に command が含まれること
        for line in content.splitlines():
            if "def make_mcp_json" in line:
                assert "command" in line, (
                    f"make_mcp_json の定義に 'command' パラメータがない: {line} (AC2 未実装)"
                )
                return
        pytest.fail("conftest.py に def make_mcp_json が存在しない (AC2 未実装)")

    def test_ac2_fixture_signature_has_tmp_path_param(self):
        # AC: make_mcp_json は tmp_path パラメータを受け付けること
        # RED: 現状は存在しないため FAIL する
        content = CONFTEST_FILE.read_text()
        for line in content.splitlines():
            if "def make_mcp_json" in line:
                assert "tmp_path" in line, (
                    f"make_mcp_json の定義に 'tmp_path' パラメータがない: {line} (AC2 未実装)"
                )
                return
        pytest.fail("conftest.py に def make_mcp_json が存在しない (AC2 未実装)")

    def test_ac2_fixture_returns_path(self):
        # AC: make_mcp_json は Path を返すこと（-> Path または .mcp.json を生成して return）
        # RED: 現状は存在しないため FAIL する
        content = CONFTEST_FILE.read_text()
        assert "make_mcp_json" in content, (
            "conftest.py に make_mcp_json が存在しない (AC2 未実装)"
        )
        # .mcp.json が生成されて return されること
        assert ".mcp.json" in content, (
            "conftest.py の make_mcp_json 実装に '.mcp.json' の参照がない (AC2 未実装)"
        )


# ---------------------------------------------------------------------------
# AC3: 各クラスの _make_mcp_json() メソッドが削除されていること
# ---------------------------------------------------------------------------


class TestAC3RemoveClassLevelMakeMcpJson:
    """AC3: TestAC1AllowlistValidation / TestAC2AbsolutePathValidation /
    TestAC3StructuredLogging / TestAC4LegitimateCommandsUnaffected の
    各クラス内 _make_mcp_json() メソッドが削除され、共有 fixture を利用している。

    RED: 現状は4クラスに _make_mcp_json が重複定義されているため FAIL する。
    """

    def test_ac3_no_duplicate_make_mcp_json_in_lifecycle_test(self):
        # AC: test_mcp_lifecycle.py 内の _make_mcp_json メソッド定義が0件
        # RED: 現状は4箇所存在するため FAIL する
        content = LIFECYCLE_TEST_FILE.read_text()
        count = content.count("def _make_mcp_json")
        assert count == 0, (
            f"test_mcp_lifecycle.py に def _make_mcp_json が {count} 箇所存在している。"
            f"共有 fixture への移行が必要 (AC3 未実装)"
        )

    def test_ac3_testac1_class_no_make_mcp_json(self):
        # AC: TestAC1AllowlistValidation クラスに _make_mcp_json がないこと
        # RED: 現状は存在するため FAIL する
        content = LIFECYCLE_TEST_FILE.read_text()
        # クラスのブロックを検出して確認
        lines = content.splitlines()
        in_class = False
        class_lines = []
        for line in lines:
            if "class TestAC1AllowlistValidation" in line:
                in_class = True
            elif in_class and line.startswith("class "):
                break
            if in_class:
                class_lines.append(line)
        class_content = "\n".join(class_lines)
        assert "def _make_mcp_json" not in class_content, (
            "TestAC1AllowlistValidation に _make_mcp_json が残存している (AC3 未実装)"
        )

    def test_ac3_testac2_class_no_make_mcp_json(self):
        # AC: TestAC2AbsolutePathValidation クラスに _make_mcp_json がないこと
        # RED: 現状は存在するため FAIL する
        content = LIFECYCLE_TEST_FILE.read_text()
        lines = content.splitlines()
        in_class = False
        class_lines = []
        for line in lines:
            if "class TestAC2AbsolutePathValidation" in line:
                in_class = True
            elif in_class and line.startswith("class "):
                break
            if in_class:
                class_lines.append(line)
        class_content = "\n".join(class_lines)
        assert "def _make_mcp_json" not in class_content, (
            "TestAC2AbsolutePathValidation に _make_mcp_json が残存している (AC3 未実装)"
        )

    def test_ac3_testac3_class_no_make_mcp_json(self):
        # AC: TestAC3StructuredLogging クラスに _make_mcp_json がないこと
        # RED: 現状は存在するため FAIL する
        content = LIFECYCLE_TEST_FILE.read_text()
        lines = content.splitlines()
        in_class = False
        class_lines = []
        for line in lines:
            if "class TestAC3StructuredLogging" in line:
                in_class = True
            elif in_class and line.startswith("class "):
                break
            if in_class:
                class_lines.append(line)
        class_content = "\n".join(class_lines)
        assert "def _make_mcp_json" not in class_content, (
            "TestAC3StructuredLogging に _make_mcp_json が残存している (AC3 未実装)"
        )

    def test_ac3_testac4_class_no_make_mcp_json(self):
        # AC: TestAC4LegitimateCommandsUnaffected クラスに _make_mcp_json がないこと
        # RED: 現状は存在するため FAIL する
        content = LIFECYCLE_TEST_FILE.read_text()
        lines = content.splitlines()
        in_class = False
        class_lines = []
        for line in lines:
            if "class TestAC4LegitimateCommandsUnaffected" in line:
                in_class = True
            elif in_class and line.startswith("class "):
                break
            if in_class:
                class_lines.append(line)
        class_content = "\n".join(class_lines)
        assert "def _make_mcp_json" not in class_content, (
            "TestAC4LegitimateCommandsUnaffected に _make_mcp_json が残存している (AC3 未実装)"
        )

    def test_ac3_shared_fixture_referenced_in_lifecycle_test(self):
        # AC: test_mcp_lifecycle.py が make_mcp_json fixture を参照していること
        # RED: 現状は _make_mcp_json（クラスメソッド）を使用し、
        #      共有 fixture への参照がないため FAIL する
        content = LIFECYCLE_TEST_FILE.read_text()
        # fixture として make_mcp_json が引数に現れること
        # （self._make_mcp_json ではなく make_mcp_json 単体で使われること）
        has_fixture_usage = (
            "make_mcp_json" in content
            and "self._make_mcp_json" not in content
        )
        assert has_fixture_usage, (
            "test_mcp_lifecycle.py で共有 fixture make_mcp_json が使われていない、"
            "または self._make_mcp_json が残存している (AC3 未実装)"
        )


# ---------------------------------------------------------------------------
# AC4: test_mcp_lifecycle.py の行数が 500 行以下に削減されている
# ---------------------------------------------------------------------------


class TestAC4LineCount:
    """AC4: test_mcp_lifecycle.py の行数が 500 行以下に削減されている
    （DRY 解消による削減 + 必要であれば AC 別ファイル分割）。

    RED: 現状は 615 行のため FAIL する。
    """

    def test_ac4_lifecycle_test_line_count_under_500(self):
        # AC: test_mcp_lifecycle.py が 500 行以下であること
        # RED: 現状は 615 行のため FAIL する
        lines = LIFECYCLE_TEST_FILE.read_text().splitlines()
        line_count = len(lines)
        assert line_count <= 500, (
            f"test_mcp_lifecycle.py が {line_count} 行ある（上限: 500 行）。"
            f"DRY 解消（_make_mcp_json 削除 + fixture 化）による削減が必要 (AC4 未実装)"
        )

    def test_ac4_line_count_reduction_amount(self):
        # AC: 行数が現在（615行）より少なくなっていること（削減の事実確認）
        # RED: 現状は 615 行のため FAIL する
        lines = LIFECYCLE_TEST_FILE.read_text().splitlines()
        line_count = len(lines)
        BASELINE_LINE_COUNT = 615  # PR #1412 時点での行数
        assert line_count < BASELINE_LINE_COUNT, (
            f"test_mcp_lifecycle.py が {line_count} 行のまま（ベースライン: {BASELINE_LINE_COUNT} 行）。"
            f"削減されていない (AC4 未実装)"
        )


# ---------------------------------------------------------------------------
# AC5: テストが PR #1412 と同じテスト数・全 PASS すること（構造確認）
# ---------------------------------------------------------------------------


class TestAC5TestCountAndPass:
    """AC5: uv run pytest tests/test_mcp_lifecycle*.py -v が PR #1412 と同じ
    テスト数（既存テスト消失なし）かつ全 PASS する。

    このクラスはテスト構造チェックとして実装前に FAIL するテストを提供する。
    AC1〜AC4 が実装されていない間は対応するテストが FAIL し、
    全 PASS の前提が崩れているため RED を維持する。
    """

    def test_ac5_lifecycle_test_classes_preserved(self):
        # AC: PR #1412 で確立されたテストクラス（AC1〜AC6）が全て存在すること
        # RED: クラス消失があれば FAIL する
        content = LIFECYCLE_TEST_FILE.read_text()
        required_classes = [
            "TestAC1AllowlistValidation",
            "TestAC2AbsolutePathValidation",
            "TestAC3StructuredLogging",
            "TestAC4LegitimateCommandsUnaffected",
            "TestAC5UnitTestCoverage",
            "TestAC6CliValueErrorHandling",
        ]
        for cls_name in required_classes:
            assert cls_name in content, (
                f"テストクラス {cls_name} が test_mcp_lifecycle.py から消えている (AC5 違反)"
            )

    def test_ac5_test_method_count_not_reduced(self):
        # AC: test_mcp_lifecycle.py のテストメソッド数が PR #1412 時点（20件）以上であること
        # 現状の test_mcp_lifecycle.py のメソッド数を数える
        content = LIFECYCLE_TEST_FILE.read_text()
        test_methods = [
            line for line in content.splitlines()
            if line.strip().startswith("def test_")
        ]
        current_count = len(test_methods)
        BASELINE_TEST_COUNT = 20  # PR #1412 時点でのテスト数
        assert current_count >= BASELINE_TEST_COUNT, (
            f"test_mcp_lifecycle.py のテストメソッド数が {current_count} 件に減少している。"
            f"ベースライン: {BASELINE_TEST_COUNT} 件以上が必要 (AC5 テスト消失)"
        )

    def test_ac5_no_test_deletion_in_refactor(self):
        # AC: リファクタリングでテストメソッドが削除されていないこと（名前チェック）
        # RED: このテスト自体は現在 PASS するが、
        #      AC1〜AC4 未実装により他テストが FAIL している間は全体として RED を維持する
        content = LIFECYCLE_TEST_FILE.read_text()
        # PR #1412 で確立された代表的なテストメソッドが存在すること
        required_tests = [
            "test_ac1_unknown_command_raises_value_error",
            "test_ac1_arbitrary_binary_raises_value_error",
            "test_ac1_allowlist_attribute_or_constant_exists",
            "test_ac2_arbitrary_absolute_path_raises_value_error",
            "test_ac3_value_error_message_contains_command",
            "test_ac4_uv_command_is_in_allowlist",
            "test_ac6_mcp_restart_catches_value_error_exits_1",
        ]
        for test_name in required_tests:
            assert test_name in content, (
                f"テストメソッド '{test_name}' が test_mcp_lifecycle.py から消えている (AC5 テスト消失)"
            )


# ---------------------------------------------------------------------------
# AC6: ac-test-mapping-1398.yaml のカバレッジが維持されていること
# ---------------------------------------------------------------------------


class TestAC6MappingCoveragePreserved:
    """AC6: PR #1412 で確立された AC1〜AC6 のテストカバレッジ
    （ac-test-mapping-1398.yaml）が維持されている。

    RED: mapping の内容と実際のテストファイルの乖離を検出する。
    """

    def test_ac6_mapping_1398_exists(self):
        # AC: ac-test-mapping-1398.yaml が存在すること
        assert MAPPING_1398.exists(), (
            f"ac-test-mapping-1398.yaml が存在しない: {MAPPING_1398} (AC6 前提違反)"
        )

    def test_ac6_mapping_references_test_file_exists(self):
        # AC: mapping が参照するテストファイルが実在すること
        assert LIFECYCLE_TEST_FILE.exists(), (
            f"mapping が参照する test_mcp_lifecycle.py が存在しない: {LIFECYCLE_TEST_FILE} (AC6 違反)"
        )

    def test_ac6_mapping_ac_indices_1_to_6_present(self):
        # AC: mapping に ac_index 1〜6 のエントリが存在すること
        content = MAPPING_1398.read_text()
        for ac_index in range(1, 7):
            assert f"ac_index: {ac_index}" in content, (
                f"ac-test-mapping-1398.yaml に ac_index: {ac_index} のエントリがない (AC6 違反)"
            )

    def test_ac6_all_mapped_test_names_exist_in_lifecycle_test(self):
        # AC: mapping が参照する全テストメソッド名が test_mcp_lifecycle.py に存在すること
        # RED: リファクタリングでテストが削除されれば FAIL する
        mapping_content = MAPPING_1398.read_text()
        lifecycle_content = LIFECYCLE_TEST_FILE.read_text()

        # mapping から test_name を抽出
        test_names = []
        for line in mapping_content.splitlines():
            stripped = line.strip()
            if stripped.startswith("test_name:"):
                # "test_name: TestAC1::test_foo" から "test_foo" を取り出す
                value = stripped.split(":", 1)[1].strip().strip('"')
                # クラス::メソッド形式の場合はメソッド名のみ
                if "::" in value:
                    method_name = value.split("::")[-1]
                else:
                    method_name = value
                test_names.append(method_name)

        missing = []
        for name in test_names:
            if name not in lifecycle_content:
                missing.append(name)

        assert not missing, (
            f"mapping が参照する以下のテストが test_mcp_lifecycle.py に存在しない:\n"
            + "\n".join(f"  - {n}" for n in missing)
            + "\n(AC6: カバレッジ消失)"
        )
