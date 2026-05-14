#!/usr/bin/env python3
"""Generate experiments/manifest.json from experiment-index.html.

Pure stdlib (html.parser + json + argparse + pathlib + re).
Outputs identity-layer metadata for each EXP (no pass/fail status updates).
"""
import argparse
import datetime
import json
import re
import sys
from html.parser import HTMLParser
from pathlib import Path

CATEGORY_RE = re.compile(r'^\s*カテゴリ\s*([A-Z])\s*:')

# Canonical runner_type values used by run-all.sh.
# Derived from classification text (first comma-separated segment) via prefix detection.


class ExperimentIndexParser(HTMLParser):
    """Parse experiment-index.html into a list of EXP dicts."""

    def __init__(self):
        super().__init__()
        self.experiments = []
        self.category = None  # letter A-N
        self.exp = None
        self.dt = None
        self.div_depth = 0
        self.in_h2 = False
        self.in_h3 = False
        self.in_dt = False
        self.in_dd = False
        self.in_code = False
        self.h2_buf = []
        self.h3_buf = []
        self.dt_buf = []
        self.dd_text_buf = []
        self.dd_codes = []
        self.code_buf = []

    def _start_exp(self, exp_id):
        self.exp = {
            'exp_id': exp_id,
            'category': self.category,
            'title': None,
            'status': None,
            'verify_source': None,
            'classification': None,
            'classification_raw': None,
            'bats_path': None,
            'smoke_path': None,
        }
        self.experiments.append(self.exp)
        self.div_depth = 1

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        cls = a.get('class', '')
        if tag == 'div' and 'exp-block' in cls:
            exp_id = a.get('id', '')
            if exp_id.startswith('EXP-'):
                self._start_exp(exp_id)
            return
        if self.exp and tag == 'div':
            self.div_depth += 1
            return
        if tag == 'h2':
            self.in_h2 = True
            self.h2_buf = []
        elif tag == 'h3' and self.exp:
            self.in_h3 = True
            self.h3_buf = []
        elif tag == 'dt' and self.exp:
            self.in_dt = True
            self.dt_buf = []
        elif tag == 'dd' and self.exp:
            self.in_dd = True
            self.dd_text_buf = []
            self.dd_codes = []
        elif tag == 'code' and self.in_dd:
            self.in_code = True
            self.code_buf = []
        elif tag == 'span' and self.in_dd and (self.dt or '').startswith('status'):
            if self.exp.get('status') is None:
                m = re.match(r'vs\s+([\w-]+)', cls)
                if m:
                    self.exp['status'] = m.group(1)
        elif tag == 'a' and self.in_dd and 'src-link' in cls:
            if self.exp.get('verify_source') is None:
                href = a.get('href')
                if href:
                    self.exp['verify_source'] = href

    def handle_endtag(self, tag):
        if tag == 'div' and self.exp:
            self.div_depth -= 1
            if self.div_depth == 0:
                self.exp = None
                self.dt = None
            return
        if tag == 'h2':
            self.in_h2 = False
            m = CATEGORY_RE.match(''.join(self.h2_buf))
            if m:
                self.category = m.group(1)
        elif tag == 'h3' and self.exp:
            self.in_h3 = False
            self.exp['title'] = ''.join(self.h3_buf).strip()
        elif tag == 'dt' and self.exp:
            self.in_dt = False
            self.dt = ''.join(self.dt_buf).strip()
        elif tag == 'dd' and self.exp:
            self.in_dd = False
            if self.dt and '分類' in self.dt:
                dd_text = ''.join(self.dd_text_buf).strip()
                self.exp['classification_raw'] = dd_text
                first_seg = re.split(r'[,、]', dd_text, maxsplit=1)[0].strip()
                self.exp['classification'] = first_seg
                for code_text in self.dd_codes:
                    if code_text.endswith('.bats'):
                        self.exp['bats_path'] = code_text
                    elif code_text.endswith('.smoke.sh'):
                        self.exp['smoke_path'] = code_text
            self.dt = None
        elif tag == 'code' and self.in_code:
            self.in_code = False
            self.dd_codes.append(''.join(self.code_buf))

    def handle_data(self, data):
        if self.in_h2:
            self.h2_buf.append(data)
        if self.in_h3:
            self.h3_buf.append(data)
        if self.in_dt:
            self.dt_buf.append(data)
        if self.in_dd:
            self.dd_text_buf.append(data)
        if self.in_code:
            self.code_buf.append(data)


def derive_runner_type(classification):
    """Normalize classification text into a runner_type token.

    Recognized prefixes (case-insensitive after strip):
      "bats" + "smoke" anywhere     -> "bats+smoke"
      "bats"                        -> "bats"   (includes "bats unit", "bats / pytest unit")
      "smoke"                       -> "smoke"
      "sandbox"                     -> "sandbox"
      "調査" or contains "research" -> "research"
      otherwise                     -> None
    """
    if not classification:
        return None
    c = classification.strip().lower()
    if c.startswith('bats'):
        return 'bats+smoke' if 'smoke' in c else 'bats'
    if c.startswith('smoke'):
        return 'smoke'
    if c.startswith('sandbox'):
        return 'sandbox'
    if c.startswith('調査') or 'research' in c:
        return 'research'
    return None


def main():
    parser = argparse.ArgumentParser(description='Generate manifest.json from experiment-index.html')
    parser.add_argument('--spec', type=Path, default=None, help='Path to experiment-index.html')
    parser.add_argument('--output', type=Path, default=None, help='Output manifest.json path')
    parser.add_argument('--stdout', action='store_true', help='Print to stdout instead of file')
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    spec = args.spec or repo_root / 'architecture/spec/twill-plugin-rebuild/experiment-index.html'
    output = args.output or repo_root / 'experiments/manifest.json'

    if not spec.exists():
        print(f'error: spec file not found: {spec}', file=sys.stderr)
        sys.exit(2)

    p = ExperimentIndexParser()
    p.feed(spec.read_text(encoding='utf-8'))

    for exp in p.experiments:
        exp['runner_type'] = derive_runner_type(exp.get('classification'))

    manifest = {
        'spec': str(spec.relative_to(repo_root)) if spec.is_absolute() else str(spec),
        'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'count': len(p.experiments),
        'experiments': p.experiments,
    }
    serialized = json.dumps(manifest, indent=2, ensure_ascii=False)

    if args.stdout:
        sys.stdout.write(serialized + '\n')
    else:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(serialized + '\n', encoding='utf-8')
        print(f'wrote {len(p.experiments)} experiments to {output}', file=sys.stderr)


if __name__ == '__main__':
    main()
