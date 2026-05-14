#!/usr/bin/env python3
"""verify-source-check.py — verify_source URL reachability + domain whitelist audit.

Phase F anti-sabotage infrastructure (registry-schema.html §10.3).

Reads experiments/manifest.json and verifies each EXP's verify_source URL:
  1. Domain is in ALLOWED_DOMAINS whitelist (architecture spec §10.3)
  2. HTTP HEAD returns 200 OK (URL reachable)

Pure stdlib (urllib + json + argparse + pathlib).

Exit codes:
  0  all reachable + all domains whitelisted
  1  one or more URLs failed (unreachable or domain not in whitelist)
  2  invocation error (manifest not found, etc.)

Usage:
  python3 experiments/verify-source-check.py [--manifest <path>] [--skip-network]
  python3 experiments/verify-source-check.py --output <json>  # save full audit result
"""
import argparse
import json
import socket
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ALLOWED_DOMAINS = {
    'code.claude.com',
    'docs.claude.com',
    'cli.github.com',
    'docs.github.com',
    'github.com',
    'man7.org',
    'gofastmcp.com',
    'gnu.org',
    'git-scm.com',
}

USER_AGENT = 'twill-verify-source-check/1.0 (+https://github.com/shuu5/twill)'
TIMEOUT_SEC = 5


def check_domain(url):
    """Return (ok, domain, reason). ok=True if scheme is http(s) AND hostname is whitelisted.

    Uses `parsed.hostname` (lowercase, no userinfo / port) instead of `netloc`
    to prevent `attacker.com@code.claude.com` style userinfo bypass attacks.
    """
    try:
        parsed = urllib.parse.urlparse(url)
    except ValueError as e:
        return False, '', f'URL parse error: {e}'
    if parsed.scheme not in ('http', 'https'):
        return False, parsed.scheme or '', f'scheme not http(s): {parsed.scheme!r}'
    domain = (parsed.hostname or '').lower()
    if not domain:
        return False, '', 'empty hostname'
    if any(domain == d or domain.endswith('.' + d) for d in ALLOWED_DOMAINS):
        return True, domain, ''
    return False, domain, f'domain not in whitelist: {domain}'


def check_reachable(url):
    """Return (ok, status, reason). HEAD request with fallback to GET.

    urllib follows 3xx redirects automatically, so we only see the final status.
    If HEAD returns 405 (Method Not Allowed) or fails the network call, retry with GET.
    """
    for method in ('HEAD', 'GET'):
        req = urllib.request.Request(url, method=method, headers={'User-Agent': USER_AGENT})
        try:
            with urllib.request.urlopen(req, timeout=TIMEOUT_SEC) as resp:
                if 200 <= resp.status < 400:
                    return True, resp.status, ''
                return False, resp.status, f'HTTP {resp.status}'
        except urllib.error.HTTPError as e:
            # 405 = Method Not Allowed (server rejects HEAD) → retry with GET
            if method == 'HEAD' and e.code == 405:
                continue
            return False, e.code, f'HTTP {e.code}'
        except (urllib.error.URLError, socket.timeout, ConnectionError, TimeoutError) as e:
            if method == 'HEAD':
                continue
            return False, None, f'network: {e}'
    return False, None, 'all methods failed'


def audit_url(url, skip_network=False):
    """Run full audit on one URL. Returns dict with ok/domain/reachable/reason."""
    result = {'url': url}
    ok_d, domain, reason_d = check_domain(url)
    result['domain'] = domain
    result['domain_ok'] = ok_d
    if not ok_d:
        result['ok'] = False
        result['reason'] = reason_d
        return result
    if skip_network:
        # Domain check passed but reachability not verified — return ok=None (neither
        # pass nor fail) so callers can distinguish "domain-only audit" from full pass.
        # Prevents bypass via VERIFY_SOURCE_SKIP_NETWORK=1 marking fake URLs as "ok".
        result['ok'] = None
        result['reachable'] = None
        result['reason'] = 'skip-network (domain ok, reachable not verified)'
        return result
    ok_n, status, reason_n = check_reachable(url)
    result['reachable'] = ok_n
    result['http_status'] = status
    result['ok'] = ok_n
    result['reason'] = '' if ok_n else reason_n
    return result


def main():
    parser = argparse.ArgumentParser(description='Audit verify_source URLs in manifest.json')
    parser.add_argument('--manifest', type=Path, default=None)
    parser.add_argument('--output', type=Path, default=None, help='Save full audit result as JSON')
    parser.add_argument('--skip-network', action='store_true', help='Domain whitelist only (no HTTP)')
    parser.add_argument('--quiet', action='store_true')
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    manifest = args.manifest or repo_root / 'experiments' / 'manifest.json'
    if not manifest.exists():
        print(f'error: manifest not found: {manifest}', file=sys.stderr)
        return 2

    data = json.loads(manifest.read_text(encoding='utf-8'))
    experiments = data.get('experiments', [])
    if not experiments:
        print('error: no experiments in manifest', file=sys.stderr)
        return 2

    results = []
    pass_count = 0
    fail_count = 0
    no_source_count = 0
    domain_only_count = 0  # ok=None (skip-network: domain whitelisted but reachability not checked)
    for exp in experiments:
        exp_id = exp.get('exp_id', '?')
        vs = exp.get('verify_source')
        if not vs:
            no_source_count += 1
            results.append({'exp_id': exp_id, 'verify_source': None, 'ok': None, 'reason': 'no verify_source'})
            continue
        r = audit_url(vs, skip_network=args.skip_network)
        r['exp_id'] = exp_id
        results.append(r)
        if r['ok'] is True:
            pass_count += 1
        elif r['ok'] is None:
            # skip-network: domain check passed but reachability not verified
            domain_only_count += 1
        else:
            fail_count += 1
            if not args.quiet:
                print(f"FAIL {exp_id}: {vs} -- {r['reason']}", file=sys.stderr)

    summary = {
        'total': len(experiments),
        'pass': pass_count,
        'fail': fail_count,
        'domain_only': domain_only_count,
        'no_source': no_source_count,
    }
    if not args.quiet:
        print(f"\n===== verify-source audit =====", file=sys.stderr)
        print(f"  total:       {summary['total']}", file=sys.stderr)
        print(f"  pass:        {summary['pass']}", file=sys.stderr)
        print(f"  fail:        {summary['fail']}", file=sys.stderr)
        print(f"  domain_only: {summary['domain_only']} (skip-network mode)", file=sys.stderr)
        print(f"  no_source:   {summary['no_source']}", file=sys.stderr)

    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(
            json.dumps({'summary': summary, 'results': results}, indent=2, ensure_ascii=False) + '\n',
            encoding='utf-8',
        )

    return 1 if fail_count > 0 else 0


if __name__ == '__main__':
    sys.exit(main())
