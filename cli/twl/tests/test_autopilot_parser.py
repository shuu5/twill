"""Tests for twl.autopilot.parser.

Covers:
  - Normal parse: status + findings JSON block (AC4)
  - Parse failure fallback: WARN + confidence=50 finding (AC4)
  - Status-only output (no JSON block)
  - Failure classifier: step → category/severity mapping
"""

from __future__ import annotations

import json

import pytest

from twl.autopilot.parser import (
    ParseResult,
    classify_failure,
    parse_specialist_output,
)


# ---------------------------------------------------------------------------
# parse_specialist_output
# ---------------------------------------------------------------------------


class TestParseSpecialistOutput:
    def test_pass_with_empty_findings(self):
        text = "status: PASS\nNo issues found."
        result = parse_specialist_output(text)
        assert result.status == "PASS"
        assert result.findings == []
        assert result.parse_error is False

    def test_fail_with_findings_block(self):
        findings = [
            {
                "severity": "CRITICAL",
                "confidence": 90,
                "file": "src/foo.py",
                "line": 10,
                "message": "SQL injection risk",
                "category": "security",
            }
        ]
        text = (
            "status: FAIL\n"
            "```json\n"
            + json.dumps(findings)
            + "\n```"
        )
        result = parse_specialist_output(text)
        assert result.status == "FAIL"
        assert len(result.findings) == 1
        assert result.findings[0]["severity"] == "CRITICAL"
        assert result.parse_error is False

    def test_warn_status(self):
        text = "status: WARN\nSome warnings detected."
        result = parse_specialist_output(text)
        assert result.status == "WARN"
        assert result.parse_error is False

    def test_case_insensitive_status(self):
        text = "status: pass"
        result = parse_specialist_output(text)
        assert result.status == "PASS"

    def test_fallback_on_missing_status(self):
        text = "No status line here at all."
        result = parse_specialist_output(text)
        assert result.status == "WARN"
        assert result.parse_error is True
        assert len(result.findings) == 1
        assert result.findings[0]["confidence"] == 50
        assert result.findings[0]["category"] == "parse-failure"

    def test_fallback_on_invalid_json_block(self):
        text = "status: PASS\n```json\nnot valid json\n```"
        result = parse_specialist_output(text)
        assert result.status == "WARN"
        assert result.parse_error is True
        assert result.findings[0]["confidence"] == 50

    def test_fallback_message_contains_raw_output(self):
        raw = "some specialist output that cannot be parsed"
        result = parse_specialist_output(raw)
        assert raw in result.findings[0]["message"]

    def test_to_dict(self):
        result = ParseResult(status="PASS", findings=[], parse_error=False)
        d = result.to_dict()
        assert d["status"] == "PASS"
        assert d["findings"] == []
        assert d["parse_error"] is False

    def test_to_json_is_valid(self):
        result = ParseResult(status="FAIL", findings=[{"a": 1}], parse_error=False)
        parsed = json.loads(result.to_json())
        assert parsed["status"] == "FAIL"
        assert parsed["findings"] == [{"a": 1}]

    def test_multiple_findings(self):
        findings = [
            {"severity": "CRITICAL", "confidence": 90, "file": "a.py", "line": 1,
             "message": "msg1", "category": "security"},
            {"severity": "HIGH", "confidence": 80, "file": "b.py", "line": 2,
             "message": "msg2", "category": "quality"},
        ]
        text = "status: FAIL\n```json\n" + json.dumps(findings) + "\n```"
        result = parse_specialist_output(text)
        assert len(result.findings) == 2

    def test_non_list_json_block_triggers_fallback(self):
        # JSON block is an object, not a list
        text = 'status: PASS\n```json\n{"key": "value"}\n```'
        result = parse_specialist_output(text)
        assert result.parse_error is True


# ---------------------------------------------------------------------------
# classify_failure
# ---------------------------------------------------------------------------


class TestClassifyFailure:
    def test_pr_test_is_critical(self):
        finding = classify_failure("pr-test", "Tests failed")
        assert finding["severity"] == "CRITICAL"
        assert finding["confidence"] >= 80
        assert finding["category"] == "test-failure"

    def test_ts_preflight_is_critical(self):
        finding = classify_failure("ts-preflight", "Type error")
        assert finding["severity"] == "CRITICAL"
        assert finding["category"] == "typecheck-failure"

    def test_merge_gate_is_critical(self):
        finding = classify_failure("merge-gate", "Blocked")
        assert finding["severity"] == "CRITICAL"
        assert finding["category"] == "merge-gate-failure"

    def test_all_pass_check_is_high(self):
        finding = classify_failure("all-pass-check", "Quality gate failed")
        assert finding["severity"] == "HIGH"
        assert finding["category"] == "quality-failure"

    def test_unknown_step(self):
        finding = classify_failure("unknown-step", "Some error")
        assert finding["severity"] == "MEDIUM"
        assert finding["category"] == "unknown-failure"

    def test_finding_contains_step_and_details(self):
        finding = classify_failure("pr-test", "Unit test failure in foo.py")
        assert "pr-test" in finding["message"]
        assert "Unit test failure in foo.py" in finding["message"]

    def test_finding_has_required_keys(self):
        finding = classify_failure("check", "Details")
        required_keys = {"severity", "confidence", "file", "line", "message", "category"}
        assert required_keys.issubset(finding.keys())


# ---------------------------------------------------------------------------
# ac-alignment post-processing (worker-issue-pr-alignment specialist)
# ---------------------------------------------------------------------------


class TestAcAlignmentProcessing:
    def _make_finding(self, **overrides):
        base = {
            "severity": "CRITICAL",
            "confidence": 80,
            "file": "Issue body",
            "line": 1,
            "message": "AC が未達成",
            "category": "ac-alignment",
        }
        base.update(overrides)
        return base

    def test_critical_without_quotes_downgraded_to_warning(self, monkeypatch):
        monkeypatch.delenv("PR_LABELS", raising=False)
        findings = [self._make_finding(message="AC が未達成（引用なし）")]
        text = "status: FAIL\n```json\n" + json.dumps(findings) + "\n```"
        result = parse_specialist_output(text)
        # Re-derived: only WARNING remains → WARN
        assert result.status == "WARN"
        assert result.findings[0]["severity"] == "WARNING"
        assert "downgraded" in result.findings[0]["message"]

    def test_critical_with_two_quote_segments_kept(self, monkeypatch):
        monkeypatch.delenv("PR_LABELS", raising=False)
        msg = "Issue 引用: 「worker-prompt-reviewer 実行」 / diff 引用: 「diff にゼロ言及」"
        findings = [self._make_finding(message=msg)]
        text = "status: FAIL\n```json\n" + json.dumps(findings) + "\n```"
        result = parse_specialist_output(text)
        assert result.status == "FAIL"
        assert result.findings[0]["severity"] == "CRITICAL"

    def test_critical_with_blockquote_evidence_kept(self, monkeypatch):
        monkeypatch.delenv("PR_LABELS", raising=False)
        msg = "未達成。\n> Issue 行 1\n> diff hunk\n"
        findings = [self._make_finding(message=msg)]
        text = "status: FAIL\n```json\n" + json.dumps(findings) + "\n```"
        result = parse_specialist_output(text)
        assert result.findings[0]["severity"] == "CRITICAL"

    def test_alignment_override_drops_findings(self, monkeypatch):
        monkeypatch.setenv("PR_LABELS", "enhancement,alignment-override,refined")
        msg = "「Issue 引用」 / 「diff 引用」"
        findings = [
            self._make_finding(message=msg),
            self._make_finding(category="ac-alignment-unknown", severity="INFO", confidence=50, message=msg),
            # non-alignment finding should be preserved
            {
                "severity": "CRITICAL",
                "confidence": 90,
                "file": "src/x.py",
                "line": 1,
                "message": "real bug",
                "category": "vulnerability",
            },
        ]
        text = "status: FAIL\n```json\n" + json.dumps(findings) + "\n```"
        result = parse_specialist_output(text)
        # alignment findings dropped, vulnerability kept → still FAIL
        assert result.status == "FAIL"
        assert len(result.findings) == 1
        assert result.findings[0]["category"] == "vulnerability"

    def test_unknown_category_passthrough(self):
        # AC: 既存 parser が未知 category を WARNING 降格せず素通し
        findings = [
            {
                "severity": "INFO",
                "confidence": 50,
                "file": "Issue body",
                "line": 1,
                "message": "判断不能",
                "category": "ac-alignment-unknown",
            }
        ]
        text = "status: PASS\n```json\n" + json.dumps(findings) + "\n```"
        result = parse_specialist_output(text)
        assert result.status == "PASS"
        assert len(result.findings) == 1
        assert result.findings[0]["category"] == "ac-alignment-unknown"
        assert result.findings[0]["severity"] == "INFO"

    def test_warning_alignment_finding_unchanged(self, monkeypatch):
        # WARNING level alignment findings are kept as-is regardless of quotes
        monkeypatch.delenv("PR_LABELS", raising=False)
        findings = [self._make_finding(severity="WARNING", confidence=75, message="部分達成")]
        text = "status: WARN\n```json\n" + json.dumps(findings) + "\n```"
        result = parse_specialist_output(text)
        assert result.status == "WARN"
        assert result.findings[0]["severity"] == "WARNING"
        assert "downgraded" not in result.findings[0]["message"]

    def test_existing_specialist_unchanged(self):
        # 後方互換: 既存 specialist (vulnerability category) は影響を受けない
        findings = [
            {
                "severity": "CRITICAL",
                "confidence": 90,
                "file": "src/auth.ts",
                "line": 42,
                "message": "SQL injection",
                "category": "vulnerability",
            }
        ]
        text = "status: FAIL\n```json\n" + json.dumps(findings) + "\n```"
        result = parse_specialist_output(text)
        assert result.status == "FAIL"
        assert result.findings[0]["severity"] == "CRITICAL"


# ---------------------------------------------------------------------------
# AC11: refined label → Status field 分離テスト（#943 RED フェーズ）
# PR_LABELS から refined を除去し、Status field で管理する
# ---------------------------------------------------------------------------


class TestRefinedStatusFieldSeparation:
    """AC11: refined は PR_LABELS ではなく Status field で管理される。"""

    def _make_finding(self, **overrides):
        base = {
            "severity": "CRITICAL",
            "confidence": 80,
            "file": "Issue body",
            "line": 1,
            "message": "AC が未達成",
            "category": "ac-alignment",
        }
        base.update(overrides)
        return base

    def test_ac11_alignment_override_without_refined_label(self, monkeypatch):
        # AC11: PR_LABELS から refined を除去しても alignment-override は機能すること
        # RED: alignment-override ロジックが refined label の有無に依存しないことを確認
        # 実装後: PR_LABELS="enhancement,alignment-override" で refined なしでも override が効く
        monkeypatch.setenv("PR_LABELS", "enhancement,alignment-override")
        msg = "「Issue 引用」 / 「diff 引用」"
        findings = [
            self._make_finding(message=msg),
        ]
        text = "status: FAIL\n```json\n" + json.dumps(findings) + "\n```"
        result = parse_specialist_output(text)
        # alignment-override が有効 → alignment findings が除去される
        # RED: 現状の実装が PR_LABELS に refined を要求していれば、ここで alignment finding が残る
        # 実装後: PR_LABELS に refined がなくても alignment-override が機能する
        assert result.status != "FAIL" or not any(
            f.get("category") == "ac-alignment" for f in result.findings
        ), (
            "RED: #943 実装後は alignment-override が refined label なしでも機能すること。"
            "現状: refined が PR_LABELS に必要な場合がある"
        )

    def test_ac11_refined_in_pr_labels_is_no_longer_required_for_gate(self, monkeypatch):
        # AC11: PR_LABELS に refined が含まれることは Status gate の判定に使わない
        # RED: Status field ベースのチェックが実装されていないことを明示
        # 実装後: refined label は PR_LABELS ではなく Board Status field で管理される
        monkeypatch.setenv("PR_LABELS", "enhancement,refined")
        # 従来は PR_LABELS に "refined" を入れていたが、#943 後は labels から除去
        # このテストは PR_LABELS に refined を含む旧パターンが deprecated であることを記録する
        # 実装後: PR_LABELS の refined は無視され Status=Refined のみで判定される
        pytest.fail(
            "RED: AC11 - #943 実装後は PR_LABELS の 'refined' は Status gate 判定に使用しない。"
            "Status field ベースの gate 実装後にこのテストを GREEN 化すること。"
        )
