import json
import re
from typing import List, Tuple


def build_envelope(command: str, version: str, plugin: str, items: list, exit_code: int) -> dict:
    """JSON 出力用の共通エンベロープを構築"""
    summary = {"critical": 0, "warning": 0, "info": 0, "ok": 0}
    for item in items:
        sev = item.get("severity", "info")
        if sev in summary:
            summary[sev] += 1
    summary["total"] = len(items)
    return {
        "command": command,
        "version": version,
        "plugin": plugin,
        "items": items,
        "summary": summary,
        "exit_code": exit_code,
    }


def output_json(envelope: dict):
    """エンベロープを stdout に JSON 出力"""
    print(json.dumps(envelope, ensure_ascii=False, indent=2))


def _parse_violation_to_item(violation: str, default_severity: str = "critical") -> dict:
    """violation 文字列を items 形式に変換

    パターン: [code] section/component: message
    """
    item = {"severity": default_severity, "component": "", "message": violation, "code": ""}
    m = re.match(r'\[([^\]]+)\]\s+(\S+?)/([\w-]+):\s*(.*)', violation)
    if m:
        item["code"] = m.group(1)
        item["component"] = m.group(3)
        item["message"] = m.group(4)
    else:
        m2 = re.match(r'\[([^\]]+)\]\s+([\w-]+):\s*(.*)', violation)
        if m2:
            item["code"] = m2.group(1)
            item["component"] = m2.group(2)
            item["message"] = m2.group(3)
    return item


def _violations_to_items(violations: List[str], severity: str = "critical") -> List[dict]:
    """violation 文字列リストを items リストに変換"""
    return [_parse_violation_to_item(v, severity) for v in violations]


def _check_results_to_items(results: List[Tuple[str, str, str]]) -> List[dict]:
    """check_files() の結果を items 形式に変換"""
    severity_map = {"missing": "critical", "no_path": "warning", "ok": "ok", "external": "info"}
    message_map = {"missing": "File missing", "no_path": "No path defined", "ok": "File exists", "external": "External component"}
    items = []
    for status, node_id, path in results:
        items.append({
            "severity": severity_map.get(status, "info"),
            "component": node_id,
            "message": message_map.get(status, status),
            "path": path or "",
            "status": status,
        })
    return items


def _extract_check_label(msg: str) -> str:
    """deep-validate メッセージからチェックラベルを抽出

    [controller-bloat] → A, [ref-placement] → B, [tools-mismatch]/[tools-unused] → C,
    [chain-*] → chain, その他 → code そのまま
    """
    m = re.match(r'\[([^\]]+)\]', msg)
    if not m:
        return ""
    code = m.group(1)
    label_map = {
        "controller-bloat": "A",
        "ref-placement": "B",
        "tools-mismatch": "C",
        "tools-unused": "C",
    }
    if code in label_map:
        return label_map[code]
    if code.startswith("chain-"):
        return "chain"
    return code


def _deep_validate_to_items(criticals: List[str], warnings: List[str], infos: List[str]) -> List[dict]:
    """deep_validate() の結果を items 形式に変換"""
    items = []
    for msg in criticals:
        item = _parse_violation_to_item(msg, "critical")
        item["check"] = _extract_check_label(msg)
        items.append(item)
    for msg in warnings:
        item = _parse_violation_to_item(msg, "warning")
        item["check"] = _extract_check_label(msg)
        items.append(item)
    for msg in infos:
        item = _parse_violation_to_item(msg, "info")
        item["check"] = _extract_check_label(msg)
        items.append(item)
    return items
