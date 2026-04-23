"""Specialist output parser and failure classifier.

Replaces: specialist-output-parse.sh, classify-failure.sh

CLI usage:
    echo "$SPECIALIST_OUTPUT" | python3 -m twl.autopilot.parser
    python3 -m twl.autopilot.parser --input FILE
    python3 -m twl.autopilot.parser --classify STEP DETAILS
"""

from __future__ import annotations

import json
import os
import re
import sys
from typing import Any

# ac-alignment categories handled by worker-issue-pr-alignment specialist
_AC_ALIGNMENT_CATEGORIES = frozenset(["ac-alignment", "ac-alignment-unknown"])
# Markdown blockquote, Japanese 「」 quotes, or pair of " quotes
_QUOTE_PATTERNS = [
    re.compile(r"^>\s+.+$", re.MULTILINE),
    re.compile(r"「[^」]+」"),
    re.compile(r"\"[^\"]{2,}\""),
    re.compile(r"`[^`\n]{2,}`"),
]


# ---------------------------------------------------------------------------
# Data structures
# ---------------------------------------------------------------------------

VALID_STATUSES = frozenset(["PASS", "WARN", "FAIL"])
VALID_SEVERITIES = frozenset(["CRITICAL", "HIGH", "MEDIUM", "LOW", "WARNING"])

_STATUS_RE = re.compile(r"status:\s*(PASS|WARN|FAIL)", re.IGNORECASE)
_JSON_BLOCK_RE = re.compile(r"```json\s*(.*?)```", re.DOTALL)


class ParseResult:
    """Result of parsing a specialist output."""

    def __init__(
        self,
        status: str,
        findings: list[dict[str, Any]],
        parse_error: bool = False,
    ) -> None:
        self.status = status
        self.findings = findings
        self.parse_error = parse_error

    def to_dict(self) -> dict[str, Any]:
        return {
            "status": self.status,
            "findings": self.findings,
            "parse_error": self.parse_error,
        }

    def to_json(self) -> str:
        return json.dumps(self.to_dict())


# ---------------------------------------------------------------------------
# Parser
# ---------------------------------------------------------------------------


def parse_specialist_output(text: str) -> ParseResult:
    """Parse specialist output into structured data.

    Mirrors specialist-output-parse.sh behaviour:
    - Extract ``status: PASS|WARN|FAIL`` line
    - Extract JSON findings from ```json...``` block
    - On parse failure: return WARN with full text as single finding
    """
    # Step 1: extract status
    m = _STATUS_RE.search(text)
    status = m.group(1).upper() if m else None

    # Step 2: extract JSON findings block
    findings: list[dict[str, Any]] | None = None
    block_match = _JSON_BLOCK_RE.search(text)
    if block_match:
        raw_json = block_match.group(1).strip()
        try:
            parsed = json.loads(raw_json)
            if isinstance(parsed, list):
                findings = parsed
            else:
                findings = None  # invalid structure → parse failure
        except json.JSONDecodeError:
            findings = None

    # Step 3: determine success
    if status is None:
        # Cannot determine status → fallback
        return _fallback_result(text)

    if findings is None and block_match:
        # JSON block present but invalid → fallback
        return _fallback_result(text)

    if findings is None:
        # No JSON block → empty findings (status line alone is valid)
        findings = []

    # Post-process ac-alignment findings (downgrade unsubstantiated CRITICALs,
    # honour PR_LABELS=alignment-override skip).
    new_findings, alignment_modified = _process_alignment_findings(findings)
    if alignment_modified:
        findings = new_findings
        # 後処理で severity 構成が変わったので status を機械的に再導出
        status = _derive_status(findings)

    return ParseResult(status=status, findings=findings, parse_error=False)


def _has_quote_evidence(message: str) -> bool:
    """Heuristic: at least 2 quoted segments (Issue 引用 + diff 引用)."""
    if not message:
        return False
    total = 0
    for pat in _QUOTE_PATTERNS:
        total += len(pat.findall(message))
        if total >= 2:
            return True
    return False


def _alignment_override_active() -> bool:
    """Check whether the PR has the `alignment-override` label.

    Reads the PR_LABELS env var (comma-separated list of label names),
    typically set by autopilot-launch.sh / merge-gate from `gh pr view`.
    """
    raw = os.environ.get("PR_LABELS", "")
    if not raw:
        return False
    labels = {lbl.strip() for lbl in raw.split(",") if lbl.strip()}
    return "alignment-override" in labels


def _process_alignment_findings(
    findings: list[dict[str, Any]],
) -> tuple[list[dict[str, Any]], bool]:
    """Apply ac-alignment-specific post-processing.

    1. If PR has `alignment-override` label → drop all ac-alignment findings.
    2. CRITICAL findings without verbatim quotes → downgrade to WARNING (parser
       cannot block on un-evidenced LLM judgements).

    Returns (new_findings, modified_flag). modified_flag is True if any
    alignment finding was dropped or downgraded.
    """
    # Fast path: no ac-alignment findings → no work
    has_alignment = any(
        isinstance(f, dict) and f.get("category") in _AC_ALIGNMENT_CATEGORIES
        for f in findings
    )
    if not has_alignment:
        return findings, False

    override = _alignment_override_active()
    out: list[dict[str, Any]] = []
    modified = False
    for f in findings:
        if not isinstance(f, dict):
            out.append(f)
            continue
        category = f.get("category", "")
        if category not in _AC_ALIGNMENT_CATEGORIES:
            out.append(f)
            continue
        if override:
            modified = True
            continue
        if f.get("severity") == "CRITICAL" and not _has_quote_evidence(str(f.get("message", ""))):
            new_f = dict(f)
            new_f["severity"] = "WARNING"
            new_f["message"] = (
                "[downgraded: 逐語引用なし] " + str(f.get("message", ""))
            )
            out.append(new_f)
            modified = True
            continue
        out.append(f)
    return out, modified


def _derive_status(findings: list[dict[str, Any]]) -> str:
    """Derive status from findings (CRITICAL → FAIL, WARNING → WARN, else PASS)."""
    has_critical = any(
        isinstance(f, dict) and f.get("severity") == "CRITICAL" for f in findings
    )
    if has_critical:
        return "FAIL"
    has_warning = any(
        isinstance(f, dict) and f.get("severity") == "WARNING" for f in findings
    )
    if has_warning:
        return "WARN"
    return "PASS"


def _fallback_result(raw_text: str) -> ParseResult:
    """Fallback: wrap full output as a WARNING finding with confidence=50."""
    # Truncate and sanitize to prevent log injection from large/malicious inputs
    truncated = raw_text[:2000]
    truncated = "".join(c if c.isprintable() or c in ("\n", "\t") else "?" for c in truncated)
    finding: dict[str, Any] = {
        "severity": "WARNING",
        "confidence": 50,
        "file": "unknown",
        "line": 0,
        "message": f"Parse failed. Raw output: {truncated}",
        "category": "parse-failure",
    }
    return ParseResult(status="WARN", findings=[finding], parse_error=True)


# ---------------------------------------------------------------------------
# Failure classifier
# ---------------------------------------------------------------------------

# Maps step names to failure categories
_STEP_CATEGORIES: dict[str, str] = {
    "pr-test": "test-failure",
    "ts-preflight": "typecheck-failure",
    "merge-gate": "merge-gate-failure",
    "all-pass-check": "quality-failure",
    "check": "check-failure",
}


def classify_failure(step: str, details: str) -> dict[str, Any]:
    """Classify a failure into a structured finding.

    Mirrors classify-failure.sh logic:
    - Map step → category
    - Determine severity based on step
    - Return structured finding dict
    """
    category = _STEP_CATEGORIES.get(step, "unknown-failure")

    # Critical steps: test failures and typecheck block merges
    if step in ("pr-test", "ts-preflight", "merge-gate"):
        severity = "CRITICAL"
        confidence = 90
    elif step in ("all-pass-check",):
        severity = "HIGH"
        confidence = 80
    else:
        severity = "MEDIUM"
        confidence = 70

    return {
        "severity": severity,
        "confidence": confidence,
        "file": "unknown",
        "line": 0,
        "message": f"Step '{step}' failed: {details}",
        "category": category,
    }


# ---------------------------------------------------------------------------
# CLI entrypoint
# ---------------------------------------------------------------------------


def _run_parse(args: list[str]) -> int:
    if "--input" in args:
        idx = args.index("--input")
        if idx + 1 >= len(args):
            print("Error: --input requires a file path", file=sys.stderr)
            return 1
        path = args[idx + 1]
        try:
            with open(path) as f:
                text = f.read()
        except OSError as e:
            print(f"Error: {e}", file=sys.stderr)
            return 1
    else:
        text = sys.stdin.read()

    result = parse_specialist_output(text)
    print(result.to_json())
    return 0


def _run_classify(args: list[str]) -> int:
    idx = args.index("--classify")
    if idx + 2 >= len(args):
        print("Error: --classify requires STEP DETAILS", file=sys.stderr)
        return 1
    step = args[idx + 1]
    details = args[idx + 2]
    result = classify_failure(step, details)
    print(json.dumps(result))
    return 0


def main(argv: list[str] | None = None) -> int:
    args = argv if argv is not None else sys.argv[1:]

    if "--classify" in args:
        return _run_classify(args)
    return _run_parse(args)


if __name__ == "__main__":
    sys.exit(main())
