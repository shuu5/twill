from pathlib import Path


def _get_body_text(file_path: Path) -> str:
    """frontmatter を除外した本文テキストを返す"""
    if not file_path.exists():
        return ''
    try:
        content = file_path.read_text(encoding='utf-8')
    except Exception:
        return ''
    lines = content.splitlines()
    if lines and lines[0].strip() == '---':
        for i, line in enumerate(lines[1:], 1):
            if line.strip() == '---':
                return '\n'.join(lines[i + 1:])
    return '\n'.join(lines)


def _count_body_lines(file_path: Path) -> int:
    """frontmatter を除外した本文行数を返す"""
    if not file_path.exists():
        return 0
    try:
        lines = file_path.read_text(encoding='utf-8').splitlines()
    except Exception:
        return 0
    # frontmatter 除外
    if lines and lines[0].strip() == '---':
        for i, line in enumerate(lines[1:], 1):
            if line.strip() == '---':
                return len(lines) - i - 1
    return len(lines)
