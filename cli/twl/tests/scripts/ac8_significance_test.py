#!/usr/bin/env python3
"""AC8 binomial proportion significance test.

Tests H0: p_mcp >= 0.5 * p_cli  (one-sided, alpha=0.05 with Bonferroni correction).

Usage:
    python3 ac8_significance_test.py --csv <path> [--output-json] [--alpha 0.05]
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import random
import sys
from pathlib import Path
from typing import Optional

# Failure pattern classifier (MECE 4 + 1)
FAILURE_PATTERN_KEYS = [
    "pythonpath_not_set",
    "subcommand_name_error",
    "enum_notation_error",
    "missing_required_option",
    "out_of_scope",
]

REQUIRED_OPERATIONS = [
    "issue_init",
    "read_field",
    "status_transition",
    "rbac_violation",
    "failed_done_force",
    "sets_nested_key",
]

REQUIRED_CSV_COLUMNS = [
    "operation",
    "route",
    "trial_index",
    "success",
    "failure_pattern",
    "session_id",
    "timestamp",
]

BONFERRONI_N = 6  # number of operations
BASE_ALPHA = 0.05
BONFERRONI_ALPHA = BASE_ALPHA / BONFERRONI_N  # 0.008333...
BOOTSTRAP_SAMPLES = 10000


def classify_failure(exit_code: int, stderr: str) -> str:
    """Classify a failure into one of 4+1 patterns (MECE).

    Evaluation order: pattern 1 → 4, else pattern 5.
    Pattern 5 (out_of_scope) is excluded from the failure-rate numerator.
    """
    if "ModuleNotFoundError" in stderr:
        return "pythonpath_not_set"
    if exit_code != 0 and ("unknown" in stderr.lower() or "invalid choice" in stderr.lower()):
        return "subcommand_name_error"
    if exit_code == 2 and "invalid" in stderr.lower() and "expected" in stderr.lower():
        return "enum_notation_error"
    if exit_code == 2 and ("required" in stderr.lower() or "missing" in stderr.lower()):
        return "missing_required_option"
    return "out_of_scope"


def load_csv(path: Path) -> list[dict]:
    with open(path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    missing = [c for c in REQUIRED_CSV_COLUMNS if c not in (reader.fieldnames or [])]
    if missing:
        raise ValueError(f"CSV missing required columns: {missing}")
    return rows


def compute_failure_rates(rows: list[dict]) -> dict[str, dict[str, dict]]:
    """Return {operation: {route: {n, failures, rate}}}."""
    stats: dict[str, dict[str, dict]] = {}
    for op in REQUIRED_OPERATIONS:
        stats[op] = {"cli": {"n": 0, "failures": 0}, "mcp": {"n": 0, "failures": 0}}

    for row in rows:
        op = row.get("operation", "")
        route = row.get("route", "")
        success = row.get("success", "true").lower() in ("true", "1", "yes")
        failure_pattern = row.get("failure_pattern", "")

        if op not in stats or route not in ("cli", "mcp"):
            continue

        stats[op][route]["n"] += 1
        # Only patterns 1-4 count as failures in the numerator
        if not success and failure_pattern != "out_of_scope":
            stats[op][route]["failures"] += 1

    for op in stats:
        for route in ("cli", "mcp"):
            n = stats[op][route]["n"]
            f = stats[op][route]["failures"]
            stats[op][route]["rate"] = f / n if n > 0 else 0.0

    return stats


def approach_a_ztest(p_mcp: float, p_cli: float, n_mcp: int, n_cli: int) -> dict:
    """Linear combination z-test: H0: p_mcp - 0.5*p_cli >= 0 (one-sided).

    SE via delta method: Var(p_mcp - 0.5*p_cli) = Var(p_mcp) + 0.25*Var(p_cli)
    = p_mcp*(1-p_mcp)/n_mcp + 0.25*p_cli*(1-p_cli)/n_cli
    """
    if n_mcp == 0 or n_cli == 0:
        return {"z": float("nan"), "p_value": float("nan"), "significant": False}

    var_mcp = p_mcp * (1 - p_mcp) / n_mcp if n_mcp > 0 else 0
    var_cli = p_cli * (1 - p_cli) / n_cli if n_cli > 0 else 0
    se = math.sqrt(var_mcp + 0.25 * var_cli)

    if se == 0:
        # Both rates are 0 → MCP is already <= 0.5*CLI (trivially satisfied when p_cli=0 → H0: 0>=0)
        z = 0.0
        p_value = 0.5
    else:
        # Test statistic: z = (p_mcp - 0.5*p_cli) / SE
        # Reject H0 when z is sufficiently negative
        z = (p_mcp - 0.5 * p_cli) / se
        p_value = _norm_cdf(z)  # P(Z <= z) for one-sided lower-tail test

    significant = p_value < BONFERRONI_ALPHA
    return {"z": round(z, 4), "p_value": round(p_value, 6), "significant": significant}


def approach_b_bootstrap(
    failures_mcp: int, n_mcp: int, failures_cli: int, n_cli: int, B: int = BOOTSTRAP_SAMPLES
) -> dict:
    """Bootstrap ratio test: proportion ratio p_mcp / p_cli, one-sided 95% CI."""
    if n_mcp == 0 or n_cli == 0:
        return {"ci_upper": float("nan"), "significant": False}

    rng = random.Random(42)
    mcp_data = [1] * failures_mcp + [0] * (n_mcp - failures_mcp)
    cli_data = [1] * failures_cli + [0] * (n_cli - failures_cli)

    ratios = []
    for _ in range(B):
        resample_mcp = [rng.choice(mcp_data) for _ in range(n_mcp)]
        resample_cli = [rng.choice(cli_data) for _ in range(n_cli)]
        p_m = sum(resample_mcp) / n_mcp
        p_c = sum(resample_cli) / n_cli
        if p_c > 0:
            ratios.append(p_m / p_c)
        else:
            ratios.append(0.0 if p_m == 0 else float("inf"))

    ratios.sort()
    # One-sided 95% CI upper bound (5th percentile from top)
    ci_upper_idx = int(0.95 * B)
    ci_upper = ratios[min(ci_upper_idx, B - 1)]

    # Significant if CI upper < 0.5 (MCP rate is less than half of CLI rate)
    significant = ci_upper < 0.5
    return {"ci_upper": round(ci_upper, 4), "significant": significant}


def _norm_cdf(z: float) -> float:
    """Standard normal CDF via math.erfc."""
    return 0.5 * math.erfc(-z / math.sqrt(2))


def run_significance_test(csv_path: Path, alpha: float = BASE_ALPHA) -> dict:
    rows = load_csv(csv_path)
    stats = compute_failure_rates(rows)

    per_operation: list[dict] = []
    overall_achieved = 0

    for op in REQUIRED_OPERATIONS:
        s_cli = stats[op]["cli"]
        s_mcp = stats[op]["mcp"]
        p_cli = s_cli["rate"]
        p_mcp = s_mcp["rate"]
        n_cli = s_cli["n"]
        n_mcp = s_mcp["n"]

        a = approach_a_ztest(p_mcp, p_cli, n_mcp, n_cli)
        b = approach_b_bootstrap(s_mcp["failures"], n_mcp, s_cli["failures"], n_cli)

        achieved = a["significant"] or b["significant"]
        if achieved:
            overall_achieved += 1

        per_operation.append({
            "operation": op,
            "p_cli": round(p_cli, 4),
            "p_mcp": round(p_mcp, 4),
            "n_cli": n_cli,
            "n_mcp": n_mcp,
            "approach_a": a,
            "approach_b": b,
            "achieved": achieved,
        })

    # Overall judgment
    if overall_achieved == len(REQUIRED_OPERATIONS):
        overall_judgment = "全達成"
    elif overall_achieved > 0:
        overall_judgment = "部分達成"
    else:
        overall_judgment = "未達成"

    # CSV hash
    csv_hash = hashlib.sha256(csv_path.read_bytes()).hexdigest()

    return {
        "overall_judgment": overall_judgment,
        "achieved_count": overall_achieved,
        "total_operations": len(REQUIRED_OPERATIONS),
        "bonferroni_corrected_alpha": round(BONFERRONI_ALPHA, 6),
        "base_alpha": BASE_ALPHA,
        "per_operation": per_operation,
        "csv_path": str(csv_path),
        "csv_sha256": csv_hash,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="AC8 binomial significance test")
    parser.add_argument("--csv", required=True, help="Path to measurement CSV file")
    parser.add_argument("--alpha", type=float, default=BASE_ALPHA, help="Base alpha (default 0.05)")
    args = parser.parse_args()

    csv_path = Path(args.csv)
    if not csv_path.exists():
        print(json.dumps({"error": f"CSV not found: {csv_path}"}))
        sys.exit(1)

    result = run_significance_test(csv_path, alpha=args.alpha)
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
