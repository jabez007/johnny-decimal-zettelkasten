#!/usr/bin/env python3
"""Validate permanent-note structure without changing notes or the MCP selection."""
import argparse
from collections import defaultdict
from pathlib import Path
import re
import sys

try:
    import yaml
except ImportError:
    raise SystemExit('Vault validation requires PyYAML. Install python3-yaml or PyYAML in this Python environment.')

STATUSES = {'distilled', 'crystallized', 'synthesized', 'scaffolded'}
IDENTITY = re.compile(r'^([A-Z]{2,4})\.([0-9A-F]{2})\.([0-9A-F]{2})(?:-.+)?$')
LINK = re.compile(r'\[\[([^\]]+)\]\]')


class UniqueKeysLoader(yaml.SafeLoader):
    pass


def unique_mapping(loader, node, deep=False):
    values = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in values:
            raise ValueError(f'Duplicate YAML key: {key}')
        values[key] = loader.construct_object(value_node, deep=deep)
    return values


UniqueKeysLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, unique_mapping)


def frontmatter(text):
    match = re.match(r'\A---\r?\n(.*?)\r?\n---(?:\r?\n|$)', text, re.S)
    if not match:
        raise ValueError('Missing YAML frontmatter')
    data = yaml.load(match[1], Loader=UniqueKeysLoader)
    if not isinstance(data, dict):
        raise ValueError('Frontmatter must be a mapping')
    return data, text[match.end():].lstrip()


def validate_vault(root):
    root = Path(root)
    issues = []
    if not root.is_dir():
        return [f'Vault directory does not exist: {root}']
    notes, targets, identities, labels = {}, defaultdict(set), defaultdict(list), {}
    def issue(file, message):
        issues.append(f'{file.relative_to(root)}: {message}')
    for file in sorted(root.rglob('*')):
        relative = file.relative_to(root)
        if any(part.startswith('.') for part in relative.parts):
            continue
        if file.is_symlink():
            issue(file, 'Symlinks are unsupported in a validated vault')
            continue
        if not file.is_file() or file.suffix not in ('.md', '.base'):
            continue
        targets[str(relative)].add(file)
        targets[file.name].add(file)
        targets[str(relative.with_suffix(''))].add(file)
        targets[file.stem].add(file)
        if file.suffix == '.base':
            try:
                base = yaml.load(file.read_text(), Loader=UniqueKeysLoader)
                if not isinstance(base, dict) or not isinstance(base.get('views'), list) or not base['views']:
                    issue(file, 'Base must define a nonempty views list')
                if relative.parts[0] != '_SYS' or len(relative.parts) != 2:
                    issue(file, 'Base must be directly under _SYS/')
            except (yaml.YAMLError, ValueError) as error:
                issue(file, f'Invalid Base YAML: {error}')
            continue
        text = file.read_text()
        # Journals and support templates remain free-form; they still resolve links.
        if relative.parts[0] in ('JRNL', '_SYS'):
            continue
        try:
            metadata, body = frontmatter(text)
        except (yaml.YAMLError, ValueError) as error:
            issue(file, str(error))
            metadata, body = {}, text
        for field in ('entities', 'communities'):
            values = metadata.get(field)
            if not isinstance(values, list) or not values or any(not isinstance(v, str) or not v.strip() or re.search(r'<[^>]+>', v) for v in values):
                issue(file, f'{field} must be a nonempty list of labels without placeholders')
            else:
                for value in values:
                    key = field, value.casefold()
                    if key in labels and labels[key] != value:
                        issue(file, f'Inconsistent {field} casing: {value!r}; existing label is {labels[key]!r}')
                    labels.setdefault(key, value)
        if not isinstance(metadata.get('status'), str) or metadata['status'] not in STATUSES:
            issue(file, 'status must be distilled, crystallized, synthesized, or scaffolded')
        aliases = metadata.get('aliases', [])
        if not isinstance(aliases, list) or any(not isinstance(alias, str) or not alias for alias in aliases):
            issue(file, 'aliases must be a list of nonempty strings')
        else:
            for alias in aliases:
                targets[alias].add(file)
        notes[file] = body
        if relative == Path('00.00.md'):
            continue
        match = IDENTITY.fullmatch(file.stem)
        if not match:
            issue(file, 'Filename must use SYS.AC.ID-Title.md')
            continue
        system, category, number = match.groups()
        identity = f'{system}.{category}.{number}'
        identities[identity].append(file)
        index = category == number == '00'
        if index:
            if relative != Path(system, '00-IDX', f'{identity}.md'):
                issue(file, 'System index must be SYS/00-IDX/SYS.00.00.md')
        else:
            if '0' in category or number == '00':
                issue(file, 'Reserved identifier: categories use 1-F and note IDs use 01-FF')
            if '-' not in file.stem:
                issue(file, 'Permanent filename requires a title after the ID')
            if (len(relative.parts) != 4 or relative.parts[0] != system
                    or not re.fullmatch(category[0] + r'0-.+', relative.parts[1])
                    or not re.fullmatch(category + r'-.+', relative.parts[2])):
                issue(file, 'Folder placement must match SYS/A0-Area/AC-Category/SYS.AC.ID-Title.md')
        expected = '00.00' if index else f'{system}.00.00'
        first = LINK.fullmatch(body.splitlines()[0]) if body else None
        if not first or first[1].split('|')[0].split('/')[-1].removesuffix('.md') != expected:
            issue(file, f'First body line must link to [[{expected}]]')
        embedded = {Path(target.split('|')[0]).name for target in re.findall(r'!\[\[([^\]]+)\]\]', body)}
        if index and f'JDEX_{system}.base' not in embedded:
            issue(file, f'System index must embed JDEX_{system}.base')
    for identity, files in identities.items():
        if len(files) > 1:
            issues.append(f'Duplicate ID {identity}: ' + ', '.join(str(file.relative_to(root)) for file in files))
    if root / '00.00.md' not in notes:
        issues.append('Missing root index 00.00.md')
    elif 'JDEX_00.00.base' not in {Path(target.split('|')[0]).name for target in re.findall(r'!\[\[([^\]]+)\]\]', notes[root / '00.00.md'])}:
        issues.append('00.00.md: Root index must embed JDEX_00.00.base')
    for file, body in notes.items():
        for link in LINK.findall(body):
            target = re.split(r'[|#^]', link, maxsplit=1)[0]
            if not target:
                continue
            matches = targets.get(target, set())
            if not matches:
                issue(file, f'Unresolved wikilink [[{target}]]')
            elif len(matches) > 1:
                issue(file, f'Ambiguous wikilink [[{target}]]; use a vault-relative path')
    return issues


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('vault', type=Path)
    args = parser.parse_args()
    issues = validate_vault(args.vault)
    for issue in issues:
        print(f'FAIL: {issue}')
    if not issues:
        print(f'Vault structure validated: {args.vault}')
    return bool(issues)


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, UnicodeError, TypeError) as error:
        raise SystemExit(f'Vault validation: {error}') from error
