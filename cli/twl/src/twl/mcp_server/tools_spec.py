"""twl_spec_content_check: spec/ content semantic lint MCP tool.

R-20 enforce: tool-architect Phase E 機械検証 step に統合 MUST。
HTML parse (html.parser std lib) + regex で content semantic 違反を検出。

check_types:
- past_narration: R-14 過去 narration 検出
- demo_code: R-15 code block 種別検証
- declarative: R-14 補足、現在形 declarative 遵守 (未完了マーカー検出)
- changes_lifecycle: R-17 changes/ 3 文書揃い + archive 移動
- respec_markup: R-18 ReSpec markup 確認 (informative)

Output: ref-specialist-output-schema.md 準拠 findings JSON。
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from html.parser import HTMLParser
from pathlib import Path
from typing import Any, Optional


# === 検出 pattern (R-14 past_narration) ===
# regex 解釈: regexp2 lookahead 対応 (Vale rule と同期、styles/TwillSpec/PastTense.yml 参照)

PAST_NARRATION_PATTERNS = [
    re.compile(r"\(\s*\d{4}-\d{1,2}-\d{1,2}\s*\)"),  # ISO date in parens
    re.compile(r"\d{4}年\d{1,2}月\d{1,2}日"),         # Japanese date
    re.compile(r"Phase \d+ で"),                       # Phase N reference
    re.compile(r"以前は"),
    re.compile(r"を確認した"),
    re.compile(r"により実施した"),
    re.compile(r"を行った"),
    re.compile(r"であった"),
    re.compile(r"していた"),
]

# 未完了マーカー (R-14 補足、未確定状態 declarative violation)
UNCOMPLETED_PATTERNS = [
    re.compile(r"\bTODO\b"),
    re.compile(r"\bFIXME\b"),
    re.compile(r"\bWIP\b"),
    re.compile(r"\bXXX\b"),
    re.compile(r"未作成"),
    re.compile(r"\bstub\b"),
    re.compile(r"\bpending\b"),
    re.compile(r"未完了"),
    re.compile(r"未決定"),
    re.compile(r"未確定"),
]

# Howto code shebang/prompt (R-15)
HOWTO_CODE_PATTERNS = [
    re.compile(r"#!/[^\n]+"),               # shebang
    re.compile(r"^\$\s", re.MULTILINE),     # shell prompt
    re.compile(r"\bnpm install\b"),
    re.compile(r"\bpip install\b"),
    re.compile(r"\bapt-get\b"),
]

# 例外パス (R-14 例外: changelog.html / archive/ / changes/ / decisions/ は narrative 許容)
EXEMPT_PATHS = [
    "architecture/spec/changelog.html",
    "architecture/archive/",
    "architecture/changes/",
    "architecture/decisions/",
]

# data-status 許容 enum (R-18)
DATA_STATUS_ENUM = {"verified", "deduced", "inferred", "experiment-verified"}


@dataclass
class Finding:
    """ref-specialist-output-schema.md 準拠 finding."""
    severity: str  # CRITICAL | WARNING | INFO
    confidence: int  # 0-100
    file: str
    line: int
    message: str
    category: str = "spec-temporal"


class _SpecHTMLParser(HTMLParser):
    """HTML parse for spec content analysis (std lib html.parser)."""

    def __init__(self):
        super().__init__()
        self.in_pre: bool = False
        self.in_example: bool = False  # <aside class="example"> 内か
        self.in_ednote: bool = False   # <aside class="ednote"> 内か (除外)
        self.in_meta: bool = False     # <div class="meta"> 内か (除外)
        self.current_pre: dict[str, Any] = {}
        self.pre_blocks: list[dict[str, Any]] = []
        self.text_blocks: list[dict[str, Any]] = []
        self.sections: list[dict[str, Any]] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, Optional[str]]]):
        attr_dict = dict(attrs)
        line = self.getpos()[0]

        if tag == "pre":
            self.in_pre = True
            self.current_pre = {
                "line": line,
                "data-status": attr_dict.get("data-status"),
                "data-experiment": attr_dict.get("data-experiment"),
                "parent_aside_example": self.in_example,
                "content": "",
            }
        elif tag == "aside":
            cls = attr_dict.get("class", "")
            if cls and "example" in cls:
                self.in_example = True
            elif cls and "ednote" in cls:
                self.in_ednote = True
        elif tag == "section":
            self.sections.append({
                "line": line,
                "class": attr_dict.get("class", ""),
                "id": attr_dict.get("id", ""),
            })
        elif tag == "div":
            cls = attr_dict.get("class", "")
            if cls and "meta" in cls:
                self.in_meta = True

    def handle_endtag(self, tag: str):
        if tag == "pre" and self.in_pre:
            self.in_pre = False
            self.pre_blocks.append(self.current_pre)
            self.current_pre = {}
        elif tag == "aside":
            self.in_example = False
            self.in_ednote = False
        elif tag == "div":
            self.in_meta = False

    def handle_data(self, data: str):
        line = self.getpos()[0]
        if self.in_pre:
            self.current_pre["content"] += data
        elif not self.in_ednote and not self.in_meta:
            self.text_blocks.append({
                "line": line,
                "content": data,
            })


def _is_exempt(file_path: str) -> bool:
    """例外パス判定 (R-14 例外、changelog/archive/changes/decisions)。"""
    return any(exempt in file_path for exempt in EXEMPT_PATHS)


def check_past_narration(parser: _SpecHTMLParser, file_path: str) -> list[Finding]:
    """R-14 過去 narration 検出。"""
    findings: list[Finding] = []
    if _is_exempt(file_path):
        return findings

    for block in parser.text_blocks:
        for pattern in PAST_NARRATION_PATTERNS:
            for match in pattern.finditer(block["content"]):
                findings.append(Finding(
                    severity="WARNING",
                    confidence=82,
                    file=file_path,
                    line=block["line"],
                    message=(
                        f"R-14 違反 candidate: 過去 narration '{match.group(0)}' を検出。"
                        f"現在形 declarative に書き換えるか、archive/ または changes/<NNN>-<slug>/ に移動。"
                    ),
                ))
    return findings


def check_demo_code(parser: _SpecHTMLParser, file_path: str) -> list[Finding]:
    """R-15 code block 種別検証 + R-18 data-status enum 検証。"""
    findings: list[Finding] = []
    for pre in parser.pre_blocks:
        line = pre["line"]
        status = pre.get("data-status")
        in_example = pre.get("parent_aside_example", False)

        # data-status 属性チェック
        if status is None and not in_example:
            findings.append(Finding(
                severity="WARNING",
                confidence=80,
                file=file_path,
                line=line,
                message=(
                    "R-15 違反 candidate: <pre> タグに data-status 属性なし、"
                    "<aside class=\"example\"> 外。schema/table/ABNF/mermaid のみ許容、"
                    "howto code は research/ へ移動 + link only。"
                ),
            ))
        elif status and status not in DATA_STATUS_ENUM:
            findings.append(Finding(
                severity="CRITICAL",
                confidence=88,
                file=file_path,
                line=line,
                message=(
                    f"R-18 違反: <pre data-status=\"{status}\"> が enum 外。"
                    f"許容値: {sorted(DATA_STATUS_ENUM)}。"
                ),
            ))
        elif status == "experiment-verified" and not pre.get("data-experiment"):
            findings.append(Finding(
                severity="WARNING",
                confidence=85,
                file=file_path,
                line=line,
                message=(
                    "R-18 違反: experiment-verified status だが data-experiment 属性なし。"
                    "EXP-NNN への link MUST (experiment-index.html#exp-NNN)。"
                ),
            ))

        # Howto code (shebang/prompt) 検出
        content = pre.get("content", "")
        if not in_example:
            for pattern in HOWTO_CODE_PATTERNS:
                if pattern.search(content):
                    findings.append(Finding(
                        severity="WARNING",
                        confidence=80,
                        file=file_path,
                        line=line,
                        message=(
                            "R-15 違反 candidate: <pre> 内に howto code (shebang/prompt/install) "
                            "検出、<aside class=\"example\"> 外。research/ へ移動 + link only。"
                        ),
                    ))
                    break

    return findings


def check_declarative(parser: _SpecHTMLParser, file_path: str) -> list[Finding]:
    """R-14 補足: 未完了マーカー検出 (declarative violation)。"""
    findings: list[Finding] = []
    if _is_exempt(file_path):
        return findings

    for block in parser.text_blocks:
        for pattern in UNCOMPLETED_PATTERNS:
            for match in pattern.finditer(block["content"]):
                findings.append(Finding(
                    severity="WARNING",
                    confidence=85,
                    file=file_path,
                    line=block["line"],
                    message=(
                        f"R-14 違反: 未完了マーカー '{match.group(0)}' を検出。"
                        f"確定形に書き換えるか、changes/<NNN>-<slug>/tasks.md の checklist に移動。"
                    ),
                ))
    return findings


def check_changes_lifecycle(file_path: str) -> list[Finding]:
    """R-17 changes/ lifecycle 整合確認 (3 文書揃い)。"""
    findings: list[Finding] = []
    match = re.search(r"architecture/changes/(\d+-[a-z-]+)/", file_path)
    if not match:
        return findings

    package_name = match.group(1)
    package_dir = Path("architecture/changes") / package_name

    required = ["proposal.md", "design.md", "tasks.md"]
    for f in required:
        if not (package_dir / f).exists():
            findings.append(Finding(
                severity="WARNING",
                confidence=85,
                file=str(package_dir / f),
                line=1,
                message=(
                    f"R-17 違反: change package {package_name} に {f} が不在。"
                    f"proposal/design/tasks 3 文書 MUST。"
                ),
            ))
    return findings


def check_respec_markup(parser: _SpecHTMLParser, file_path: str) -> list[Finding]:
    """R-18 ReSpec markup 確認 (INFO レベル、新規 vs 既存 section の区別は本 tool 不可)。

    Grandfather: 既存 section は遡及適用なし。本 tool では git diff なしのため
    全 section をスキャン、class なし section を INFO で flag (reviewer 判断委譲)。
    """
    findings: list[Finding] = []
    for sec in parser.sections:
        cls = sec.get("class", "")
        if not cls or ("normative" not in cls and "informative" not in cls):
            findings.append(Finding(
                severity="INFO",
                confidence=80,
                file=file_path,
                line=sec["line"],
                message=(
                    "R-18 candidate: <section> に class=\"normative\" or \"informative\" がない。"
                    "新規 section の場合は ReSpec markup MUST、既存 section は grandfather "
                    "(本 tool では区別不能、reviewer 判断)。"
                ),
            ))
    return findings


def twl_spec_content_check_handler(
    file_path: str,
    check_types: Optional[list[str]] = None,
) -> dict[str, Any]:
    """spec content semantic check MCP tool handler.

    R-20 enforce: tool-architect Phase E 機械検証 step に統合。

    Args:
        file_path: 対象 file path (architecture/spec/*.html 等)
        check_types: 実行する check の list (None なら全 check)

    Returns:
        {
            "ok": bool,                  # CRITICAL/WARNING 0 件なら True
            "findings": list[dict],      # ref-specialist-output-schema 準拠
            "exit_code": int,            # 0 (PASS) / 1 (WARN/FAIL) / 2 (error)
            "error": str (optional),     # error 時のみ
        }
    """
    if check_types is None:
        check_types = [
            "past_narration",
            "demo_code",
            "declarative",
            "changes_lifecycle",
            "respec_markup",
        ]

    findings: list[Finding] = []

    path = Path(file_path)
    if not path.exists():
        return {
            "ok": False,
            "findings": [],
            "exit_code": 2,
            "error": f"file not found: {file_path}",
        }

    # HTML parse (.html file のみ)
    parser_obj: Optional[_SpecHTMLParser] = None
    if file_path.endswith(".html"):
        parser_obj = _SpecHTMLParser()
        try:
            parser_obj.feed(path.read_text(encoding="utf-8"))
        except Exception as e:
            return {
                "ok": False,
                "findings": [],
                "exit_code": 2,
                "error": f"parse error: {e}",
            }

    # 各 check 実行
    if "past_narration" in check_types and parser_obj:
        findings.extend(check_past_narration(parser_obj, file_path))
    if "demo_code" in check_types and parser_obj:
        findings.extend(check_demo_code(parser_obj, file_path))
    if "declarative" in check_types and parser_obj:
        findings.extend(check_declarative(parser_obj, file_path))
    if "changes_lifecycle" in check_types:
        findings.extend(check_changes_lifecycle(file_path))
    if "respec_markup" in check_types and parser_obj:
        findings.extend(check_respec_markup(parser_obj, file_path))

    # status 導出 (ref-specialist-output-schema.md ルール)
    has_critical = any(f.severity == "CRITICAL" for f in findings)
    has_warning = any(f.severity == "WARNING" for f in findings)

    ok = not has_critical and not has_warning
    exit_code = 1 if (has_critical or has_warning) else 0

    return {
        "ok": ok,
        "findings": [
            {
                "severity": f.severity,
                "confidence": f.confidence,
                "file": f.file,
                "line": f.line,
                "message": f.message,
                "category": f.category,
            }
            for f in findings
        ],
        "exit_code": exit_code,
    }
