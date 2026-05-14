#!/usr/bin/env python3
"""audit-status-log.py — status transition + anti-sabotage drift audit.

Phase G anti-sabotage infrastructure (registry-schema.html §10.3 + Phase F-3 持ち越し findings).

4 検知 logic:
  1. status transition + lattice violation (jumping CRITICAL、downgrade WARN)
  2. A3: SKIP_PRERUN_AUDIT bypass detection (git diff で env var 追加検知)
  3. A6: gen-manifest.py integrity (SHA256 baseline 比較)
  4. I-3: 4-file drift detection (registry-schema/experiment-index/glossary/registry.yaml)

Pure stdlib (re + json + argparse + pathlib + html.parser + subprocess + hashlib).

Exit codes:
  0  all OK
  1  one or more violations detected
  2  invocation error (file not found, etc.)

Usage:
  python3 experiments/audit-status-log.py [--baseline-file <path>] [--output <json>] [--quiet]
"""
import argparse
import hashlib
import html.parser
import json
import re
import subprocess
import sys
from pathlib import Path

LATTICE_ORDER = {
    "inferred": 0,
    "deduced": 1,
    "verified": 2,
    "experiment-verified": 3,
}

ALL_STATUSES = set(LATTICE_ORDER.keys())

REPO_ROOT = Path(__file__).resolve().parent.parent

SPEC_DIR = REPO_ROOT / "architecture" / "spec" / "twill-plugin-rebuild"

I3_TARGETS = {
    "registry-schema": SPEC_DIR / "registry-schema.html",
    "experiment-index": SPEC_DIR / "experiment-index.html",
    "glossary": SPEC_DIR / "glossary.html",
    "registry-yaml": REPO_ROOT / "plugins" / "twl" / "registry.yaml",
}


class ExperimentStatusParser(html.parser.HTMLParser):
    """experiment-index.html から exp_id → status mapping を抽出 (gen-manifest.py から簡易転載)."""

    def __init__(self):
        super().__init__()
        self.statuses: dict[str, str] = {}
        self.cur_exp = None
        self.in_dt = False
        self.cur_dt = ""
        self.dt_seen = ""
        self.in_dd = False

    def handle_starttag(self, tag, attrs):
        d = dict(attrs)
        if tag == "div" and "exp-block" in (d.get("class") or "") and d.get("id", "").startswith("EXP-"):
            self.cur_exp = d["id"]
        elif tag == "dt" and self.cur_exp:
            self.in_dt = True
            self.cur_dt = ""
        elif tag == "dd" and self.cur_exp:
            self.in_dd = True
        elif tag == "span" and self.cur_exp and self.in_dd and self.dt_seen.startswith("status"):
            cls = d.get("class", "")
            m = re.match(r"vs\s+([\w-]+)", cls)
            if m and self.statuses.get(self.cur_exp) is None:
                self.statuses[self.cur_exp] = m.group(1)

    def handle_endtag(self, tag):
        if tag == "dt":
            self.in_dt = False
            self.dt_seen = self.cur_dt.strip().lower()
        elif tag == "dd":
            self.in_dd = False
        elif tag == "div" and self.cur_exp:
            # exp-block 終了は厳密 tracking しないが、次の exp-block で上書きされる
            pass

    def handle_data(self, data):
        if self.in_dt:
            self.cur_dt += data


def extract_statuses(html_text: str) -> dict[str, str]:
    """experiment-index.html text から {EXP-NNN: status} を返す."""
    parser = ExperimentStatusParser()
    parser.feed(html_text)
    return parser.statuses


def git_show(commit_ref: str, path: str) -> str:
    """git show <ref>:<path> の内容を返す。失敗時は空文字列."""
    try:
        result = subprocess.run(
            ["git", "show", f"{commit_ref}:{path}"],
            cwd=str(REPO_ROOT),
            capture_output=True,
            text=True,
            check=False,
            timeout=10,
        )
        if result.returncode != 0:
            return ""
        return result.stdout
    except (subprocess.SubprocessError, OSError):
        return ""


def git_diff(commit_range: str, path: str = "") -> str:
    """git diff <range> [-- path] の出力を返す."""
    cmd = ["git", "diff", commit_range]
    if path:
        cmd.extend(["--", path])
    try:
        result = subprocess.run(
            cmd, cwd=str(REPO_ROOT), capture_output=True, text=True, check=False, timeout=10
        )
        return result.stdout if result.returncode == 0 else ""
    except (subprocess.SubprocessError, OSError):
        return ""


def _diff_statuses(prev_statuses: dict[str, str], curr_statuses: dict[str, str]) -> list[dict]:
    """status mapping を比較し、変更があった EXP の transition record list を返す."""
    transitions = []
    for exp_id, curr in curr_statuses.items():
        prev = prev_statuses.get(exp_id)
        if prev is None or prev == curr:
            continue
        if curr not in LATTICE_ORDER or prev not in LATTICE_ORDER:
            transitions.append({
                "exp_id": exp_id, "from": prev, "to": curr,
                "level": "WARN", "reason": f"unknown status: {prev} or {curr}",
            })
            continue
        prev_rank = LATTICE_ORDER[prev]
        curr_rank = LATTICE_ORDER[curr]
        delta = curr_rank - prev_rank
        if delta < 0:
            level = "WARN"
            reason = f"downgrade: {prev} → {curr} (audit 発覚時のみ user 確認下で許容)"
        elif delta > 1:
            level = "CRITICAL"
            reason = (
                f"lattice skip jump: {prev} → {curr} (delta={delta}, "
                "registry-schema.html §10.2 で跳躍禁止、verified 経由必須。"
                "multi-stage upgrade pattern なら user 判断下で許容)"
            )
        else:
            level = "INFO"
            reason = f"valid upgrade: {prev} → {curr}"
        transitions.append({
            "exp_id": exp_id, "from": prev, "to": curr,
            "delta": delta, "level": level, "reason": reason,
        })
    return transitions


# ─── Check 1: status transition + lattice violation (full git history scan) ─────
def detect_status_transitions(commit_before: str = "HEAD~1", commit_after: str = "HEAD",
                              full_history: bool = False) -> list[dict]:
    """experiment-index.html の status 変更を git diff 経由で検知.

    full_history=True の場合: experiment-index.html の add commit から HEAD までの全 transition を scan
    (Phase G cross-AI re-audit で発見した「Phase F-2 の transition (e.g. EXP-038 inferred → experiment-verified)
    が 1-commit diff では検知漏れ」問題への対応)。
    """
    spec_path = "architecture/spec/twill-plugin-rebuild/experiment-index.html"

    if not full_history:
        # 1-commit diff モード
        prev_html = git_show(commit_before, spec_path)
        curr_path = REPO_ROOT / spec_path
        curr_html = curr_path.read_text(encoding="utf-8") if curr_path.exists() else ""

        if not prev_html or not curr_html:
            return [{"check": "status_transitions", "level": "INFO",
                     "reason": "git show or file read failed (initial commit?)"}]

        return _diff_statuses(extract_statuses(prev_html), extract_statuses(curr_html))

    # full_history モード: git log で全 commit を辿る
    try:
        result = subprocess.run(
            ["git", "log", "--reverse", "--format=%H", "--", spec_path],
            cwd=str(REPO_ROOT), capture_output=True, text=True, check=False, timeout=10,
        )
        if result.returncode != 0:
            return [{"check": "status_transitions", "level": "WARN",
                     "reason": "git log failed"}]
        commits = result.stdout.strip().split("\n")
    except (subprocess.SubprocessError, OSError):
        return [{"check": "status_transitions", "level": "WARN",
                 "reason": "git log subprocess error"}]

    if len(commits) < 2:
        return [{"check": "status_transitions", "level": "INFO",
                 "reason": "less than 2 commits modify spec, no transition history"}]

    all_transitions = []
    prev_html_text = git_show(commits[0], spec_path)
    prev_statuses = extract_statuses(prev_html_text) if prev_html_text else {}
    for i in range(1, len(commits)):
        curr_html_text = git_show(commits[i], spec_path)
        if not curr_html_text:
            continue
        curr_statuses = extract_statuses(curr_html_text)
        diffs = _diff_statuses(prev_statuses, curr_statuses)
        for d in diffs:
            d["commit"] = commits[i][:8]
        all_transitions.extend(diffs)
        prev_statuses = curr_statuses

    return all_transitions


# ─── Check 2: A3 SKIP_PRERUN_AUDIT bypass detection ─────────────────────
def detect_a3_bypass(commit_before: str = "HEAD~1", commit_after: str = "HEAD") -> dict:
    """git diff で SKIP_PRERUN_AUDIT=1 の追加を検知 (audit bypass の試み)."""
    diff = git_diff(f"{commit_before}..{commit_after}")
    if not diff:
        return {"check": "A3_skip_prerun_audit", "level": "INFO",
                "reason": "no diff or git error"}
    # added lines (start with +) で SKIP_PRERUN_AUDIT=1 を含むものを検出
    # ただし run-all.sh 内既存実装 (SKIP_PRERUN_AUDIT を変数として参照) は除外
    bypass_lines = []
    for line in diff.splitlines():
        if not line.startswith("+") or line.startswith("+++"):
            continue
        # SKIP_PRERUN_AUDIT=1 が新規追加された行
        if re.search(r"\bSKIP_PRERUN_AUDIT\s*=\s*1\b", line):
            # commented line or test fixture は INFO
            stripped = line[1:].strip()
            if stripped.startswith("#") or "test" in stripped.lower():
                bypass_lines.append({"line": line, "level": "INFO",
                                     "reason": "commented or test context"})
            else:
                bypass_lines.append({"line": line, "level": "CRITICAL",
                                     "reason": "audit bypass added (SKIP_PRERUN_AUDIT=1)"})
    if not bypass_lines:
        return {"check": "A3_skip_prerun_audit", "level": "OK",
                "reason": "no SKIP_PRERUN_AUDIT=1 bypass detected"}
    return {"check": "A3_skip_prerun_audit",
            "level": "CRITICAL" if any(b["level"] == "CRITICAL" for b in bypass_lines) else "INFO",
            "bypass_lines": bypass_lines,
            "reason": f"{len([b for b in bypass_lines if b['level'] == 'CRITICAL'])} CRITICAL bypass(es) detected"}


# ─── Check 3: A6 gen-manifest.py integrity ──────────────────────────────
def check_a6_gen_manifest_integrity(baseline_file: Path | None) -> dict:
    """experiments/gen-manifest.py の SHA256 を baseline と比較."""
    target = REPO_ROOT / "experiments" / "gen-manifest.py"
    if not target.exists():
        return {"check": "A6_gen_manifest_integrity", "level": "CRITICAL",
                "reason": "gen-manifest.py not found"}
    current_sha = hashlib.sha256(target.read_bytes()).hexdigest()
    if baseline_file is None or not baseline_file.exists():
        return {"check": "A6_gen_manifest_integrity", "level": "INFO",
                "current_sha256": current_sha,
                "reason": "baseline not provided, recording current SHA only",
                "action_required": f"echo '{current_sha}' > <baseline_file> to enable future drift check"}
    baseline_sha = baseline_file.read_text(encoding="utf-8").strip()
    if current_sha == baseline_sha:
        return {"check": "A6_gen_manifest_integrity", "level": "OK",
                "current_sha256": current_sha,
                "baseline_sha256": baseline_sha,
                "reason": "SHA256 matches baseline"}
    return {"check": "A6_gen_manifest_integrity", "level": "CRITICAL",
            "current_sha256": current_sha,
            "baseline_sha256": baseline_sha,
            "reason": "gen-manifest.py SHA256 differs from baseline (改ざん or 正規 update?)"}


# ─── Check 4: I-3 4-file drift detection ────────────────────────────────
def check_i3_drift() -> dict:
    """4 file で verify-status 4-state defining word の存在を確認."""
    results = {}
    missing_total = []
    for label, path in I3_TARGETS.items():
        if not path.exists():
            results[label] = {"path": str(path), "level": "CRITICAL",
                              "reason": f"file not found: {path}"}
            missing_total.append(f"{label}: file not found")
            continue
        content = path.read_text(encoding="utf-8")
        missing = []
        for status in ALL_STATUSES:
            # status word は word boundary で出現するか
            # YAML の場合は引用符内も含む
            if not re.search(rf"\b{re.escape(status)}\b", content):
                missing.append(status)
        if missing:
            results[label] = {"path": str(path), "level": "CRITICAL",
                              "missing_statuses": missing,
                              "reason": f"{len(missing)} status word(s) missing: {missing}"}
            missing_total.append(f"{label}: missing {missing}")
        else:
            results[label] = {"path": str(path), "level": "OK",
                              "reason": "all 4 status words present"}
    overall = "CRITICAL" if missing_total else "OK"
    return {"check": "I3_4file_drift", "level": overall,
            "results": results,
            "reason": "; ".join(missing_total) if missing_total else "all 4 files contain all 4 status words"}


# ─── Main ────────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(description="Audit status transitions + anti-sabotage drift")
    parser.add_argument("--baseline-file", type=Path, default=None,
                        help="Path to baseline file containing gen-manifest.py SHA256")
    parser.add_argument("--commit-before", default="HEAD~1",
                        help="Earlier commit for transition diff (default: HEAD~1)")
    parser.add_argument("--commit-after", default="HEAD",
                        help="Later commit for transition diff (default: HEAD)")
    parser.add_argument("--full-history", action="store_true",
                        help="Scan all commits in spec history (Phase G fix: detect transitions across phases)")
    parser.add_argument("--output", type=Path, default=None, help="Save full audit JSON")
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()

    # Run all 4 checks
    transitions = detect_status_transitions(args.commit_before, args.commit_after,
                                            full_history=args.full_history)
    a3 = detect_a3_bypass(args.commit_before, args.commit_after)
    a6 = check_a6_gen_manifest_integrity(args.baseline_file)
    i3 = check_i3_drift()

    # Count violations
    critical = 0
    warn = 0
    for t in transitions:
        if t.get("level") == "CRITICAL":
            critical += 1
        elif t.get("level") == "WARN":
            warn += 1
    if a3.get("level") == "CRITICAL":
        critical += 1
    if a6.get("level") == "CRITICAL":
        critical += 1
    if i3.get("level") == "CRITICAL":
        critical += 1

    summary = {
        "critical": critical,
        "warn": warn,
        "transitions_count": len([t for t in transitions if t.get("level") != "INFO"]),
        "a3_status": a3.get("level"),
        "a6_status": a6.get("level"),
        "i3_status": i3.get("level"),
    }

    result = {
        "summary": summary,
        "transitions": transitions,
        "a3_skip_prerun_audit": a3,
        "a6_gen_manifest_integrity": a6,
        "i3_4file_drift": i3,
    }

    if not args.quiet:
        print("===== audit-status-log =====", file=sys.stderr)
        print(f"  critical: {summary['critical']}", file=sys.stderr)
        print(f"  warn:     {summary['warn']}", file=sys.stderr)
        print(f"  transitions: {summary['transitions_count']}", file=sys.stderr)
        print(f"  A3 (SKIP_PRERUN_AUDIT bypass): {summary['a3_status']}", file=sys.stderr)
        print(f"  A6 (gen-manifest SHA256):      {summary['a6_status']}", file=sys.stderr)
        print(f"  I-3 (4-file drift):            {summary['i3_status']}", file=sys.stderr)
        for t in transitions:
            if t.get("level") in ("CRITICAL", "WARN"):
                print(f"  {t['level']} {t.get('exp_id', '?')}: {t.get('from', '?')} → {t.get('to', '?')} ({t.get('reason', '')})", file=sys.stderr)

    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    return 1 if critical > 0 else 0


if __name__ == "__main__":
    sys.exit(main())
