#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
python3 - "${REPO_ROOT}" <<'PY'
from pathlib import Path
from urllib.parse import unquote, urlsplit
import re
import sys
import unicodedata

root = Path(sys.argv[1]).resolve()
wiki = root / 'docs/wiki'
base = 'https://github.com/KnowSky404/sing-box-vps/'
files = [root / 'README.md', root / 'AGENTS.md', root / 'SECURITY.md',
         root / 'skills/sing-box-vps-operator/SKILL.md', root / 'src/install/README.md',
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

markdown_link = re.compile(
    r'\[(?:\\.|[^\[\]\\\n]|\[(?:\\.|[^\]\\\n])*\])*\]\([ \t]*(<[^<>\n]*>|[^\s)]+)'
    r"""(?:[ \t]+(?:"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'|\((?:\\.|[^)\\\n])*\)))?[ \t]*\)""")

for page in files:
    content = prose(page.read_text())
    for url in markdown_link.findall(content):
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

# Bare index paths are checkout-relative; explicit Markdown links use the index directory.
index_path = root / 'docs/agents/llms.txt'
index = prose(index_path.read_text())
source_prefix = base + 'blob/main/'
wiki_prefix = base + 'wiki'
repository_url = re.escape(source_prefix) + '|' + re.escape(wiki_prefix)
references = {(url.strip('<>'), True) for url in markdown_link.findall(index)}
link_delimiters = r"""\s<>()\[\]\x60"'*，。；：、！？（）【】《》“”‘’「」『』–—…"""
bare_references = re.findall(
    rf'(?<![A-Za-z0-9_/.])(_{{1,3}})?((?:{repository_url})[^{link_delimiters}]*|'
    r'(?:(?:\.\./)+|(?:\./|/)?(?:AGENTS\.md|SECURITY\.md|README\.md|(?:docs|skills)/))'
    rf'[^{link_delimiters}:;,?#]*(?:[?#][^{link_delimiters}]*)?)',
    markdown_link.sub('', index))
for emphasis, reference in bare_references:
    reference = reference.rstrip('.:;,')
    if emphasis and reference.endswith(emphasis):
        reference = reference[:-len(emphasis)]
    references.add((reference, False))

for reference, explicit_link in sorted(references):
    source_url = reference.startswith(source_prefix)
    relative = reference[len(source_prefix):] if source_url else reference
    link = urlsplit(relative)
    if reference == wiki_prefix or reference.startswith((wiki_prefix + '/', wiki_prefix + '?', wiki_prefix + '#')):
        page_name = unquote(link.path.split('/wiki', 1)[1]).strip('/') or 'Home'
        path = f'docs/wiki/{page_name}.md'
        target = (root / path).resolve()
    elif link.scheme or link.netloc:
        continue
    else:
        from_index = not (source_url or link.path.startswith('/')) and (
            explicit_link or link.path.startswith('../'))
        relative_root = index_path.parent if from_index else root
        path = unquote(link.path.lstrip('/') if not source_url else link.path)
        target = (relative_root / path).resolve() if link.path or source_url else index_path
    fragment = unquote(link.fragment)
    if (target != root and root not in target.parents) or not target.exists():
        errors.append(f'llms.txt: missing target {path}')
    elif fragment and not target.is_file():
        errors.append(f'llms.txt: missing anchor {path}#{fragment}')
    elif fragment:
        lines = re.fullmatch(r'L([1-9][0-9]*)(?:-L([1-9][0-9]*))?', fragment) if source_url else None
        if lines:
            start = int(lines[1])
            end = int(lines[2] or lines[1])
            valid = start <= end <= len(target.read_bytes().splitlines())
        else:
            valid = fragment in anchors(target)
        if not valid:
            errors.append(f'llms.txt: missing anchor {path}#{fragment}')

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
