"""
RED tests for Issue #1402 -- DRY refactoring of test_ac8_run_240_trials.py

TDD RED フェーズ用メタテスト。
対象ファイル自体の構造を検査する。
実装前（リファクタ前）は全件 FAIL する（意図的 RED）。

AC1: loaded_ac8_module fixture が追加され、AC8_RUN_SCRIPT 存在時に module を返す
AC2: TestAC1SkeletonImplemented の hasattr テスト 4 件が parametrize で 1 メソッドに統合
AC3: test_ac2_run_trial_with_mcp_route_succeeds が loaded_ac8_module fixture を利用し、
     メソッド body 内に importlib.util.spec_from_file_location の直接呼び出しがない
AC4: importlib.util.spec_from_file_location の出現数が 2 以下
AC5: pytest collection で parametrize 形式のテスト ID が存在する
"""

import ast
import subprocess
import sys
from pathlib import Path

# 対象ファイル（リファクタリング対象）
REPO_ROOT = Path(__file__).resolve().parent.parent.parent.parent
TARGET_FILE = REPO_ROOT / "cli" / "twl" / "tests" / "test_ac8_run_240_trials.py"

# parametrize 統合後に期待されるテストメソッド名のキーワード
EXPECTED_PARAM_METHOD_KEYWORD = "test_ac1_has_function"

# parametrize 化後に消えていることを期待する旧メソッド名（4 件別々の定義）
OLD_SEPARATE_METHODS = [
    "test_ac1_has_function_main",
    "test_ac1_has_function_run_trial",
    "test_ac1_has_function_classify_failure",
    "test_ac1_has_function_goldfile_match",
]

# AC4 しきい値
IMPORTLIB_MAX_COUNT = 2


# ---------------------------------------------------------------------------
# ヘルパー: ファイルを AST 解析して情報を取得
# ---------------------------------------------------------------------------

def _parse_target_file() -> ast.Module:
    """対象ファイルを AST として解析して返す。"""
    assert TARGET_FILE.exists(), f"対象ファイルが存在しない: {TARGET_FILE}"
    source = TARGET_FILE.read_text(encoding="utf-8")
    return ast.parse(source, filename=str(TARGET_FILE))


def _get_all_function_defs(tree: ast.Module) -> list[ast.FunctionDef]:
    """AST ツリーから全ての FunctionDef（トップレベル + クラス内）を収集する。"""
    result = []
    for node in ast.walk(tree):
        if isinstance(node, ast.FunctionDef):
            result.append(node)
    return result


def _get_fixture_names(tree: ast.Module) -> list[str]:
    """@pytest.fixture デコレータが付いた関数名一覧を返す。"""
    fixture_names = []
    for node in ast.walk(tree):
        if isinstance(node, ast.FunctionDef):
            for decorator in node.decorator_list:
                # @pytest.fixture or @pytest.fixture(...)
                if isinstance(decorator, ast.Attribute) and decorator.attr == "fixture":
                    fixture_names.append(node.name)
                elif isinstance(decorator, ast.Call):
                    func = decorator.func
                    if isinstance(func, ast.Attribute) and func.attr == "fixture":
                        fixture_names.append(node.name)
    return fixture_names


def _get_parametrize_methods(tree: ast.Module) -> list[ast.FunctionDef]:
    """@pytest.mark.parametrize デコレータが付いたメソッド一覧を返す。"""
    result = []
    for node in ast.walk(tree):
        if isinstance(node, ast.FunctionDef):
            for decorator in node.decorator_list:
                if isinstance(decorator, ast.Call):
                    func = decorator.func
                    # pytest.mark.parametrize の形式
                    if (
                        isinstance(func, ast.Attribute)
                        and func.attr == "parametrize"
                        and isinstance(func.value, ast.Attribute)
                        and func.value.attr == "mark"
                    ):
                        result.append(node)
    return result


def _get_method_source(method_name: str, class_name: str) -> str:
    """対象ファイルから特定クラスの特定メソッドのソーステキストを返す。"""
    source = TARGET_FILE.read_text(encoding="utf-8")
    lines = source.splitlines()
    tree = ast.parse(source, filename=str(TARGET_FILE))

    for node in ast.walk(tree):
        if isinstance(node, ast.ClassDef) and node.name == class_name:
            for item in node.body:
                if isinstance(item, ast.FunctionDef) and item.name == method_name:
                    start = item.lineno - 1
                    end = item.end_lineno
                    return "\n".join(lines[start:end])
    return ""


# ---------------------------------------------------------------------------
# AC1: loaded_ac8_module fixture が存在するか検査
# ---------------------------------------------------------------------------

class TestAC1LoadedFixtureExists:
    """AC1: loaded_ac8_module fixture が追加されていることを検査する。

    現在の状態（リファクタ前）: @pytest.fixture decorated な loaded_ac8_module が存在しない。
    RED: FAIL する。
    """

    def test_ac1_loaded_ac8_module_fixture_is_defined(self):
        # AC: loaded_ac8_module fixture が @pytest.fixture として定義されている
        # RED: リファクタ前は fixture が存在しないため FAIL
        tree = _parse_target_file()
        fixture_names = _get_fixture_names(tree)
        assert "loaded_ac8_module" in fixture_names, (
            f"loaded_ac8_module fixture が @pytest.fixture として定義されていない。"
            f"現在の fixture 一覧: {fixture_names}"
        )

    def test_ac1_fixture_has_pytest_skip_for_missing_script(self):
        # AC: fixture 内に pytest.skip の呼び出しが含まれる（AC8_RUN_SCRIPT 不在時の skip 処理）
        # RED: fixture 自体が存在しないため FAIL
        source = TARGET_FILE.read_text(encoding="utf-8")
        tree = ast.parse(source, filename=str(TARGET_FILE))

        fixture_source = ""
        for node in ast.walk(tree):
            if isinstance(node, ast.FunctionDef) and node.name == "loaded_ac8_module":
                lines = source.splitlines()
                start = node.lineno - 1
                end = node.end_lineno
                fixture_source = "\n".join(lines[start:end])
                break

        assert fixture_source, (
            "loaded_ac8_module fixture が定義されていないため body を検査できない"
        )
        assert "pytest.skip" in fixture_source, (
            "loaded_ac8_module fixture 内に pytest.skip が含まれていない"
        )


# ---------------------------------------------------------------------------
# AC2: hasattr テスト 4 件が parametrize で 1 メソッドに統合されているか
# ---------------------------------------------------------------------------

class TestAC2HasattrParametrizeIntegration:
    """AC2: TestAC1SkeletonImplemented の 4 hasattr テストが parametrize で 1 メソッドに統合。

    現在の状態（リファクタ前）: 4 つの別々のメソッドが存在する。
    RED: FAIL する。
    """

    def test_ac2_old_separate_methods_are_removed(self):
        # AC: 旧 4 メソッド（test_ac1_has_function_main 等）が独立メソッドとして存在しない
        # RED: リファクタ前は 4 メソッドが別々に存在するため FAIL
        source = TARGET_FILE.read_text(encoding="utf-8")
        tree = ast.parse(source, filename=str(TARGET_FILE))

        # TestAC1SkeletonImplemented クラスのメソッド名を収集
        skeleton_methods = []
        for node in ast.walk(tree):
            if isinstance(node, ast.ClassDef) and node.name == "TestAC1SkeletonImplemented":
                for item in node.body:
                    if isinstance(item, ast.FunctionDef):
                        skeleton_methods.append(item.name)

        # 旧メソッドが残っている場合は FAIL
        remaining_old_methods = [m for m in OLD_SEPARATE_METHODS if m in skeleton_methods]
        assert not remaining_old_methods, (
            f"旧 hasattr 個別メソッドがまだ残存している（parametrize 統合前）: "
            f"{remaining_old_methods}"
        )

    def test_ac2_parametrize_method_exists_in_skeleton_class(self):
        # AC: TestAC1SkeletonImplemented に @pytest.mark.parametrize 付きメソッドが存在する
        # RED: リファクタ前は parametrize メソッドがないため FAIL
        source = TARGET_FILE.read_text(encoding="utf-8")
        tree = ast.parse(source, filename=str(TARGET_FILE))

        skeleton_parametrize_methods = []
        for node in ast.walk(tree):
            if isinstance(node, ast.ClassDef) and node.name == "TestAC1SkeletonImplemented":
                for item in node.body:
                    if isinstance(item, ast.FunctionDef):
                        for decorator in item.decorator_list:
                            if isinstance(decorator, ast.Call):
                                func = decorator.func
                                if (
                                    isinstance(func, ast.Attribute)
                                    and func.attr == "parametrize"
                                    and isinstance(func.value, ast.Attribute)
                                    and func.value.attr == "mark"
                                ):
                                    skeleton_parametrize_methods.append(item.name)

        assert skeleton_parametrize_methods, (
            "TestAC1SkeletonImplemented に @pytest.mark.parametrize が付いたメソッドが存在しない"
        )

    def test_ac2_parametrize_covers_all_four_functions(self):
        # AC: parametrize のパラメータに main/run_trial/classify_failure/goldfile_match が含まれる
        # RED: parametrize メソッドが存在しないため FAIL
        source = TARGET_FILE.read_text(encoding="utf-8")
        tree = ast.parse(source, filename=str(TARGET_FILE))

        expected_functions = {"main", "run_trial", "classify_failure", "goldfile_match"}
        found_params: set[str] = set()

        for node in ast.walk(tree):
            if isinstance(node, ast.ClassDef) and node.name == "TestAC1SkeletonImplemented":
                for item in node.body:
                    if isinstance(item, ast.FunctionDef):
                        for decorator in item.decorator_list:
                            if isinstance(decorator, ast.Call):
                                func = decorator.func
                                if (
                                    isinstance(func, ast.Attribute)
                                    and func.attr == "parametrize"
                                    and isinstance(func.value, ast.Attribute)
                                    and func.value.attr == "mark"
                                ):
                                    # parametrize の args から文字列定数を収集
                                    for arg in decorator.args:
                                        if isinstance(arg, (ast.List, ast.Tuple)):
                                            for elt in arg.elts:
                                                if isinstance(elt, ast.Constant) and isinstance(elt.value, str):
                                                    found_params.add(elt.value)

        missing = expected_functions - found_params
        assert not missing, (
            f"parametrize パラメータに関数名が不足: {missing}。"
            f"検出されたパラメータ: {found_params}"
        )


# ---------------------------------------------------------------------------
# AC3: test_ac2_run_trial_with_mcp_route_succeeds 内に直接 importlib がないか
# ---------------------------------------------------------------------------

class TestAC3NoDirectImportlibInMcpTest:
    """AC3: test_ac2_run_trial_with_mcp_route_succeeds が loaded_ac8_module fixture を利用し、
    メソッド body 内に importlib.util.spec_from_file_location の直接呼び出しがない。

    現在の状態（リファクタ前）: 行 169 に直接呼び出しが存在する。
    RED: FAIL する。
    """

    def test_ac3_mcp_test_method_has_no_direct_importlib_call(self):
        # AC: test_ac2_run_trial_with_mcp_route_succeeds のメソッド body に
        #     importlib.util.spec_from_file_location が含まれない
        # RED: リファクタ前は行 169 に直接呼び出しが存在するため FAIL
        method_source = _get_method_source(
            "test_ac2_run_trial_with_mcp_route_succeeds",
            "TestAC2CldMcpPoC",
        )
        assert method_source, (
            "test_ac2_run_trial_with_mcp_route_succeeds メソッドが TestAC2CldMcpPoC 内に見つからない"
        )
        assert "importlib.util.spec_from_file_location" not in method_source, (
            "test_ac2_run_trial_with_mcp_route_succeeds メソッド body 内に "
            "importlib.util.spec_from_file_location の直接呼び出しが残存している"
        )

    def test_ac3_mcp_test_method_uses_loaded_ac8_module_fixture(self):
        # AC: test_ac2_run_trial_with_mcp_route_succeeds が loaded_ac8_module を引数に持つ
        # RED: リファクタ前は fixture を使わずに直接 importlib を呼んでいるため FAIL
        source = TARGET_FILE.read_text(encoding="utf-8")
        tree = ast.parse(source, filename=str(TARGET_FILE))

        fixture_used = False
        for node in ast.walk(tree):
            if isinstance(node, ast.ClassDef) and node.name == "TestAC2CldMcpPoC":
                for item in node.body:
                    if (
                        isinstance(item, ast.FunctionDef)
                        and item.name == "test_ac2_run_trial_with_mcp_route_succeeds"
                    ):
                        # 引数に loaded_ac8_module が含まれるか確認
                        arg_names = [arg.arg for arg in item.args.args]
                        if "loaded_ac8_module" in arg_names:
                            fixture_used = True

        assert fixture_used, (
            "test_ac2_run_trial_with_mcp_route_succeeds が loaded_ac8_module fixture を "
            "引数として使用していない"
        )


# ---------------------------------------------------------------------------
# AC4: importlib.util.spec_from_file_location の出現数が 2 以下
# ---------------------------------------------------------------------------

class TestAC4ImportlibOccurrenceCount:
    """AC4: grep -c "importlib.util.spec_from_file_location" の結果が 2 以下。

    現在の状態（リファクタ前）: 7 回出現。
    RED: FAIL する。
    """

    def test_ac4_importlib_spec_occurrence_count_is_at_most_2(self):
        # AC: importlib.util.spec_from_file_location の出現数が 2 以下
        # RED: リファクタ前は 7 回出現するため FAIL
        source = TARGET_FILE.read_text(encoding="utf-8")
        count = source.count("importlib.util.spec_from_file_location")
        assert count <= IMPORTLIB_MAX_COUNT, (
            f"importlib.util.spec_from_file_location の出現数が {IMPORTLIB_MAX_COUNT} を超過: "
            f"{count} 回。"
            f"fixture 内 1 回 + test_ac1_script_importable の subprocess 文字列内 1 回の計 2 回が上限。"
        )


# ---------------------------------------------------------------------------
# AC5: pytest collection で parametrize 形式のテスト ID が存在する
# ---------------------------------------------------------------------------

class TestAC5ParametrizeTestIds:
    """AC5: pytest --collect-only で parametrize 形式のテスト ID が存在する。

    現在の状態（リファクタ前）: parametrize がないため "[...]" 形式の ID が存在しない。
    RED: FAIL する。
    """

    def test_ac5_collected_ids_include_parametrize_format(self):
        # AC: pytest --collect-only で TestAC1SkeletonImplemented 内に [...] 形式の ID が存在する
        # RED: リファクタ前は parametrize がないため [...] 形式が存在しない → FAIL
        result = subprocess.run(
            [
                sys.executable,
                "-m",
                "pytest",
                str(TARGET_FILE),
                "-v",
                "--collect-only",
                "-q",
                "--no-header",
            ],
            capture_output=True,
            text=True,
            timeout=60,
            cwd=str(REPO_ROOT),
        )
        output = result.stdout + result.stderr

        # parametrize 形式: TestAC1SkeletonImplemented::test_ac1_has_function[...]
        # "[" + "]" の組合せで parametrize ID を検出
        parametrize_ids = [
            line for line in output.splitlines()
            if "TestAC1SkeletonImplemented" in line
            and "[" in line
            and "]" in line
        ]

        assert parametrize_ids, (
            "pytest --collect-only の結果に TestAC1SkeletonImplemented 配下の "
            "parametrize 形式テスト ID（[...] 形式）が存在しない。\n"
            f"collection 出力:\n{output[:2000]}"
        )

    def test_ac5_test_execution_count_preserved(self):
        # AC: リファクタ前後でテスト実行件数の総和が等価（4 hasattr 分は維持される）
        # RED: parametrize 統合前は TestAC1SkeletonImplemented に
        #      個別 hasattr メソッドしか存在しないため、このテストは
        #      "parametrize で 4 件が生成されていること" を確認できず FAIL
        #
        # 検証: parametrize で 4 パラメータ分のテストが生成されるか確認する
        result = subprocess.run(
            [
                sys.executable,
                "-m",
                "pytest",
                str(TARGET_FILE),
                "-v",
                "--collect-only",
                "-q",
                "--no-header",
            ],
            capture_output=True,
            text=True,
            timeout=60,
            cwd=str(REPO_ROOT),
        )
        output = result.stdout + result.stderr

        # TestAC1SkeletonImplemented の parametrize テスト ID を収集
        skeleton_parametrize_ids = [
            line for line in output.splitlines()
            if "TestAC1SkeletonImplemented" in line
            and "[" in line
            and "]" in line
        ]

        # 4 関数分（main, run_trial, classify_failure, goldfile_match）の ID が存在するはず
        assert len(skeleton_parametrize_ids) >= 4, (
            f"TestAC1SkeletonImplemented の parametrize テスト ID が 4 件未満: "
            f"{len(skeleton_parametrize_ids)} 件。\n"
            f"検出 ID: {skeleton_parametrize_ids}"
        )
