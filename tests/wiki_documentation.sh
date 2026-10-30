#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
python3 - "${REPO_ROOT}" <<'PY'
from pathlib import Path
from urllib.parse import unquote, urlsplit
import re
import sys
import unicodedata

root = Path(sys.argv[1])
wiki = root / 'docs/wiki'
base = 'https://github.com/KnowSky404/sing-box-vps/'
files = [root / 'README.md', root / 'AGENTS.md', root / 'SECURITY.md',
         root / 'skills/sing-box-vps-operator/SKILL.md',
         *sorted((root / 'docs/specs').glob('*.md')), *sorted(wiki.glob('*.md'))]
errors = []

def prose(text):
    # Examples inside fenced code blocks are not navigational links.
    return re.sub(r'^(`{3,}|~{3,}).*?^\1\s*$', '', text, flags=re.M | re.S)

def anchors(path):
    counts = {}
    result = set()
    for title in re.findall(r'^#{1,6}\s+(.+)$', prose(path.read_text()), re.M):
        title = re.sub(r'<[^>]*>', '', title).lower().replace(' ', '-')
        title = ''.join(c for c in title if c in '-_' or
                        unicodedata.category(c)[0] in 'LN' or
                        unicodedata.category(c) == 'Mn')
        count = counts.get(title, 0)
        result.add(title + (f'-{count}' if count else ''))
        counts[title] = count + 1
    return result

for page in files:
    content = prose(page.read_text())
    for url in re.findall(r'\[[^\]\n]*\]\(([^\s)]+)\)', content):
        url = unquote(url.strip('<>'))
        link = urlsplit(url)
        if url.startswith(base + 'wiki'):
            name = link.path.split('/wiki', 1)[1].strip('/') or 'Home'
            target = wiki / (name + '.md')
        elif url.startswith(base + 'blob/main/'):
            target = root / link.path.split('/blob/main/', 1)[1]
        elif link.scheme or link.netloc:
            continue
        else:
            target = page.parent / link.path if link.path else page
        if not target.exists():
            errors.append(f'{page.relative_to(root)}: missing target {url}')
        elif link.fragment and target.suffix == '.md' and link.fragment not in anchors(target):
            errors.append(f'{page.relative_to(root)}: missing anchor {url}')

# Keep the offline Agent index tied to files that still exist.
for path in re.findall(r'docs/(?:wiki|specs)/[A-Za-z0-9_.-]+\.md',
                       (root / 'docs/agents/llms.txt').read_text()):
    if not (root / path).is_file():
        errors.append(f'llms.txt: missing target {path}')

# Every content page must remain reachable from both navigation surfaces.
for page in wiki.glob('*.md'):
    if page.stem in ('Home', '_Sidebar'):
        continue
    for nav in ('Home', '_Sidebar'):
        if base + 'wiki/' + page.stem + ')' not in (wiki / (nav + '.md')).read_text():
            errors.append(f'{nav}: missing navigation to {page.stem}')

if errors:
    sys.exit('\n'.join(errors))
print(f'Wiki documentation links and navigation passed ({len(files)} files)')
PY
