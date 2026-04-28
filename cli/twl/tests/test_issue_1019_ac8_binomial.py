"""
Tests for Issue #1019 AC8 — AI 失敗率測定プロトコル + 実証 (binomial proportion test)

AC1-AC4 実装済み（GREEN）。AC5（doobidoo）・実測データ依存テストは NotImplementedError 継続。

AC1: 測定プロトコル文書化 (N=240 設計)
AC2: 測定環境ガードレール (cold-start + prompt 標準化 + 両経路強制)
AC3: 4 失敗パターン分類 + state での具体化
AC4: 統計判定 (one-sided proportion test, α=0.05)
AC5: 実証結果を doobidoo memory に記録
AC6: PR merge 完遂
"""

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest

# パス定義
REPO_ROOT = Path(__file__).resolve().parent.parent.parent.parent
CLI_TWL_DIR = REPO_ROOT / "cli" / "twl"
PLUGINS_TWL_DIR = REPO_ROOT / "plugins" / "twl"

# AC1 対象
PROTOCOL_DOC = PLUGINS_TWL_DIR / "architecture" / "phases" / "phase1-ai-failure-rate-protocol.md"

# AC4 対象
SIGNIFICANCE_SCRIPT = CLI_TWL_DIR / "tests" / "scripts" / "ac8_significance_test.py"
AC8_DATA_DIR = CLI_TWL_DIR / "tests" / "scripts" / "ac8_data"
AC8_GOLDFILES_DIR = CLI_TWL_DIR / "tests" / "scripts" / "ac8_goldfiles"

# GREEN フェーズ実装ガイド: 以下の定数を各テストメソッドの検証ロジックで使用する
REQUIRED_OPERATIONS = [  # AC1: 6 操作
    "issue_init",
    "read_field",
    "status_transition",
    "rbac_violation",
    "failed_done_force",
    "sets_nested_key",
]

REQUIRED_FINGERPRINT_FIELDS = [  # AC2: environment fingerprint
    "host",
    "git_HEAD",
    "python_version",
    "fastmcp_version",
    "mcp_server_pid",
    "session_id",
    "timestamp",
]

FAILURE_PATTERN_KEYS = [  # AC3: 4 失敗パターン
    "pythonpath_not_set",
    "subcommand_name_error",
    "enum_notation_error",
    "missing_required_option",
]

REQUIRED_CSV_COLUMNS = [  # AC4: CSV 必須カラム
    "operation",
    "route",
    "trial_index",
    "success",
    "failure_pattern",
    "session_id",
    "timestamp",
]


def _make_minimal_csv() -> str:
    """全 6 操作 × 2 経路を 1 試行ずつ含む最小 CSV を返す。"""
    lines = ["operation,route,trial_index,success,failure_pattern,session_id,timestamp"]
    for op in REQUIRED_OPERATIONS:
        for route in ("cli", "mcp"):
            lines.append(f"{op},{route},1,true,,sess-test,2026-01-01T00:00:00Z")
    return "\n".join(lines) + "\n"


class TestAC1ProtocolDocument:
    """AC1: 測定プロトコル文書化 (N=240 設計)"""

    def test_ac1_protocol_doc_exists(self):
        # AC: plugins/twl/architecture/phases/phase1-ai-failure-rate-protocol.md が存在する
        assert PROTOCOL_DOC.exists(), f"Protocol doc not found: {PROTOCOL_DOC}"

    def test_ac1_n240_justification_present(self):
        # AC: N=240 の根拠 (20/操作 × 6 操作 × 2 経路) が明示されている
        text = PROTOCOL_DOC.read_text(encoding="utf-8")
        assert "240" in text, "N=240 が文書化されていない"
        assert "20" in text, "20 trials/操作/経路 が文書化されていない"
        assert "6" in text, "6 操作 が文書化されていない"

    def test_ac1_power_analysis_mentioned(self):
        # AC: power analysis が文書内に含まれている
        text = PROTOCOL_DOC.read_text(encoding="utf-8").lower()
        assert "power" in text or "検出力" in text, "power analysis が文書化されていない"

    def test_ac1_six_operations_documented(self):
        # AC: 6 操作が全て文書化されている
        text = PROTOCOL_DOC.read_text(encoding="utf-8")
        for op in REQUIRED_OPERATIONS:
            assert op in text, f"操作 '{op}' が文書化されていない"

    def test_ac1_cli_route_defined(self):
        # AC: CLI 経路 = `python3 -m twl.autopilot.state ...` が明示されている
        text = PROTOCOL_DOC.read_text(encoding="utf-8")
        assert "python3 -m twl.autopilot.state" in text, "CLI 経路が文書化されていない"

    def test_ac1_mcp_route_defined(self):
        # AC: MCP 経路 = `mcp__twl__twl_state_read` / `twl_state_write` が明示されている
        text = PROTOCOL_DOC.read_text(encoding="utf-8")
        assert "mcp__twl__twl_state_read" in text, "MCP 経路 (state_read) が文書化されていない"

    def test_ac1_goldfile_definition_present(self):
        # AC: goldfile (success criterion) の定義が文書化されている
        text = PROTOCOL_DOC.read_text(encoding="utf-8").lower()
        assert "goldfile" in text, "goldfile 定義が文書化されていない"

    def test_ac1_prerequisite_verify_documented(self):
        # AC: #1018 PR merge 後の MCP server 動作確認が前提として文書化されている
        text = PROTOCOL_DOC.read_text(encoding="utf-8")
        assert "1018" in text or "#1018" in text, "#1018 前提条件が文書化されていない"


class TestAC2MeasurementGuardrails:
    """AC2: 測定環境ガードレール (cold-start + prompt 標準化 + 両経路強制)"""

    def test_ac2_cold_start_requirement_documented(self):
        # AC: cold-start session 必須が文書化されている
        text = PROTOCOL_DOC.read_text(encoding="utf-8").lower()
        assert "cold-start" in text or "cold start" in text, "cold-start 要件が文書化されていない"

    def test_ac2_prompt_standardization_documented(self):
        # AC: prompt 標準化が文書化されている
        text = PROTOCOL_DOC.read_text(encoding="utf-8")
        assert "prompt" in text or "プロンプト" in text, "prompt 標準化が文書化されていない"

    def test_ac2_forced_subset_design_documented(self):
        # AC: forced subset 設計が文書化されている
        text = PROTOCOL_DOC.read_text(encoding="utf-8")
        assert "240" in text, "試行数設計が文書化されていない"

    def test_ac2_trial_total_matches_240(self):
        # AC: forced 30 (CLI) + 30 (MCP) + free 120 = 240 試行の内訳が CSV で一致する
        # RED: 実測データ CSV が存在しないため FAIL
        raise NotImplementedError("AC #2 未実装: 試行数合計 240 の検証が未完了（実測 CSV 待ち）")

    def test_ac2_environment_fingerprint_fields_present(self):
        # AC: environment fingerprint に必須 7 フィールド全て含まれる
        # RED: 実測データ CSV が存在しないため FAIL
        raise NotImplementedError("AC #2 未実装: environment fingerprint フィールドの検証が未完了")

    def test_ac2_data_csv_exists(self):
        # AC: ac8_data/<timestamp>.csv が 1 件以上存在する
        # RED: 実測未完了のため FAIL
        raise NotImplementedError("AC #2 未実装: ac8_data CSV ファイルが存在しない")


class TestAC3FailurePatternClassification:
    """AC3: 4 失敗パターン分類 + state での具体化"""

    def _get_classifier(self):
        sys.path.insert(0, str(SIGNIFICANCE_SCRIPT.parent))
        from ac8_significance_test import classify_failure
        return classify_failure

    def test_ac3_pattern1_pythonpath_not_set(self):
        # AC: PYTHONPATH 未設定パターンを stderr の ModuleNotFoundError で検出できる
        classify = self._get_classifier()
        result = classify(exit_code=1, stderr="ModuleNotFoundError: No module named 'twl'")
        assert result == "pythonpath_not_set"

    def test_ac3_pattern2_subcommand_name_error(self):
        # AC: subcommand 名間違いを検出できる
        classify = self._get_classifier()
        result = classify(exit_code=1, stderr="Error: unknown command 'stat'")
        assert result == "subcommand_name_error"

    def test_ac3_pattern3_enum_notation_error(self):
        # AC: enum 値の表記ゆれを検出できる
        classify = self._get_classifier()
        result = classify(exit_code=2, stderr="invalid value 'Done', expected one of: running, merge-ready")
        assert result == "enum_notation_error"

    def test_ac3_pattern4_missing_required_option(self):
        # AC: 必須オプション漏れを検出できる
        classify = self._get_classifier()
        result = classify(exit_code=2, stderr="error: the following arguments are required: --issue")
        assert result == "missing_required_option"

    def test_ac3_mece_guarantee_pattern5_out_of_scope(self):
        # AC: logic error (StateError exit 1) は pattern 5 (out-of-scope) として分類される
        classify = self._get_classifier()
        result = classify(exit_code=1, stderr="StateError: invalid transition from done to running")
        assert result == "out_of_scope"

    def test_ac3_numerator_definition_excludes_pattern5(self):
        # AC: 分子定義がパターン 1-4 のみであり、パターン 5 (logic error) を除外する
        # out_of_scope が FAILURE_PATTERN_KEYS に含まれないことで確認
        assert "out_of_scope" not in FAILURE_PATTERN_KEYS
        assert all(k in ["pythonpath_not_set", "subcommand_name_error", "enum_notation_error", "missing_required_option"] for k in FAILURE_PATTERN_KEYS)


class TestAC4StatisticalTest:
    """AC4: 統計判定 (one-sided proportion test, α=0.05)"""

    def test_ac4_significance_script_exists(self):
        # AC: cli/twl/tests/scripts/ac8_significance_test.py が存在する
        assert SIGNIFICANCE_SCRIPT.exists(), f"Significance script not found: {SIGNIFICANCE_SCRIPT}"

    def test_ac4_script_accepts_csv_input(self):
        # AC: ac8_significance_test.py が CSV ファイルを入力として受け付ける
        with tempfile.NamedTemporaryFile(mode="w", suffix=".csv", delete=False) as f:
            f.write(_make_minimal_csv())
            tmp = f.name
        try:
            result = subprocess.run(
                ["python3", str(SIGNIFICANCE_SCRIPT), "--csv", tmp],
                capture_output=True, text=True, timeout=60,
            )
            assert result.returncode == 0, f"Script failed: {result.stderr}"
        finally:
            os.unlink(tmp)

    def test_ac4_script_outputs_json(self):
        # AC: ac8_significance_test.py が JSON 形式で結果を出力する
        with tempfile.NamedTemporaryFile(mode="w", suffix=".csv", delete=False) as f:
            f.write(_make_minimal_csv())
            tmp = f.name
        try:
            result = subprocess.run(
                ["python3", str(SIGNIFICANCE_SCRIPT), "--csv", tmp],
                capture_output=True, text=True, timeout=60,
            )
            assert result.returncode == 0
            output = json.loads(result.stdout)
            assert isinstance(output, dict)
        finally:
            os.unlink(tmp)

    def test_ac4_approach_a_linear_combination_ztest(self):
        # AC: アプローチ A — 線形結合の z-test が実装されている
        with tempfile.NamedTemporaryFile(mode="w", suffix=".csv", delete=False) as f:
            f.write(_make_minimal_csv())
            tmp = f.name
        try:
            result = subprocess.run(
                ["python3", str(SIGNIFICANCE_SCRIPT), "--csv", tmp],
                capture_output=True, text=True, timeout=60,
            )
            output = json.loads(result.stdout)
            # per_operation 内の各エントリに approach_a が存在する
            for op_result in output.get("per_operation", []):
                assert "approach_a" in op_result, f"approach_a missing in {op_result}"
                assert "z" in op_result["approach_a"]
                assert "p_value" in op_result["approach_a"]
        finally:
            os.unlink(tmp)

    def test_ac4_approach_b_bootstrap_ratio_test(self):
        # AC: アプローチ B — bootstrap 比率比検定が実装されている
        with tempfile.NamedTemporaryFile(mode="w", suffix=".csv", delete=False) as f:
            f.write(_make_minimal_csv())
            tmp = f.name
        try:
            result = subprocess.run(
                ["python3", str(SIGNIFICANCE_SCRIPT), "--csv", tmp],
                capture_output=True, text=True, timeout=120,
            )
            output = json.loads(result.stdout)
            for op_result in output.get("per_operation", []):
                assert "approach_b" in op_result, f"approach_b missing in {op_result}"
                assert "ci_upper" in op_result["approach_b"]
        finally:
            os.unlink(tmp)

    def test_ac4_bonferroni_correction_applied(self):
        # AC: Bonferroni 補正 (α/6 = 0.0083) が適用されている
        with tempfile.NamedTemporaryFile(mode="w", suffix=".csv", delete=False) as f:
            f.write(_make_minimal_csv())
            tmp = f.name
        try:
            result = subprocess.run(
                ["python3", str(SIGNIFICANCE_SCRIPT), "--csv", tmp],
                capture_output=True, text=True, timeout=60,
            )
            output = json.loads(result.stdout)
            bonferroni_alpha = output.get("bonferroni_corrected_alpha", 0)
            assert abs(bonferroni_alpha - (0.05 / 6)) < 1e-4, f"Bonferroni α mismatch: {bonferroni_alpha}"
        finally:
            os.unlink(tmp)

    def test_ac4_overall_judgment_categories(self):
        # AC: overall 判定が 全達成 / 部分達成 / 未達成 の 3 カテゴリで出力される
        with tempfile.NamedTemporaryFile(mode="w", suffix=".csv", delete=False) as f:
            f.write(_make_minimal_csv())
            tmp = f.name
        try:
            result = subprocess.run(
                ["python3", str(SIGNIFICANCE_SCRIPT), "--csv", tmp],
                capture_output=True, text=True, timeout=120,
            )
            output = json.loads(result.stdout)
            assert output.get("overall_judgment") in ("全達成", "部分達成", "未達成")
        finally:
            os.unlink(tmp)

    def test_ac4_goldfiles_exist_for_all_operations_and_routes(self):
        # AC: ac8_goldfiles/<op>_<route>.txt が 6 操作 × 2 経路 = 12 件存在する
        assert AC8_GOLDFILES_DIR.exists(), f"Goldfiles dir not found: {AC8_GOLDFILES_DIR}"
        for op in REQUIRED_OPERATIONS:
            for route in ("cli", "mcp"):
                gf = AC8_GOLDFILES_DIR / f"{op}_{route}.txt"
                assert gf.exists(), f"Goldfile missing: {gf}"


class TestAC5DoobidooMemoryRecord:
    """AC5: 実証結果を doobidoo memory に記録

    実測データおよび doobidoo memory への記録が存在しない現状では全件 FAIL する。
    """

    def test_ac5_raw_trial_data_recorded(self):
        # AC: 各試行の raw data が mcp__doobidoo__memory_store で記録されている
        # RED: 実測前のため FAIL
        raise NotImplementedError("AC #5 未実装: 各試行の raw data が doobidoo memory に記録されていない")

    def test_ac5_tags_include_required_fields(self):
        # AC: tags に ["phase1", "ac8", "ai-failure-rate", "<route>", "<operation>"] が含まれる
        # RED: 実測前のため FAIL
        raise NotImplementedError("AC #5 未実装: 必須 tags フィールドが doobidoo memory に記録されていない")

    def test_ac5_summary_hash_recorded(self):
        # AC: 集計後サマリーが別 hash で doobidoo memory に記録されている
        # RED: 実測前のため FAIL
        raise NotImplementedError("AC #5 未実装: 集計サマリー hash が doobidoo memory に記録されていない")


class TestAC6PRMergeComplete:
    """AC6: PR merge 完遂"""

    def test_ac6_protocol_doc_in_repo(self):
        # AC: 測定プロトコル文書が存在する
        assert PROTOCOL_DOC.exists(), f"Protocol doc not found: {PROTOCOL_DOC}"

    def test_ac6_significance_script_in_repo(self):
        # AC: 検定スクリプトが存在する
        assert SIGNIFICANCE_SCRIPT.exists(), f"Significance script not found: {SIGNIFICANCE_SCRIPT}"

    def test_ac6_measured_csv_in_repo(self):
        # AC: 実測 CSV (ac8_data/<timestamp>.csv) が存在する
        # RED: 実測データ未作成のため FAIL
        raise NotImplementedError("AC #6 未実装: 実測 CSV が存在しない (実測待ち)")

    def test_ac6_goldfiles_in_repo(self):
        # AC: goldfiles (ac8_goldfiles/<op>_<route>.txt) が存在する
        assert AC8_GOLDFILES_DIR.exists()
        goldfiles = list(AC8_GOLDFILES_DIR.glob("*.txt"))
        assert len(goldfiles) == 12, f"Expected 12 goldfiles, found {len(goldfiles)}"

    def test_ac6_doobidoo_memory_ac8_judgment_recorded(self):
        # AC: doobidoo memory に AC8 達成判定結果が記録されている
        # RED: 実測・判定が未完了のため FAIL
        raise NotImplementedError("AC #6 未実装: doobidoo memory に AC8 達成判定結果が記録されていない")
