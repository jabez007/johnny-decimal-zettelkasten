#!/usr/bin/env python3
"""Inspect community labels, resolve search filters, and propose normalization."""
import argparse
from collections import defaultdict
import hashlib
import json
from pathlib import Path
import re
import sys

from vault_metadata import UniqueKeysLoader, frontmatter, markdown_notes, yaml

CATALOGUE_PATH = Path('_SYS/metadata-catalogue.yaml')


def valid_label(value):
    return (isinstance(value, str) and bool(value.strip()) and value == value.strip()
            and not re.search(r'<[^>]+>', value))


class Catalogue:
    def __init__(self, data):
        if not isinstance(data, dict) or set(data) != {'version', 'communities'}:
            raise ValueError('Catalogue requires exactly version and communities')
        if type(data['version']) is not int or data['version'] != 1:
            raise ValueError('Unsupported catalogue version; expected integer 1')
        communities = data['communities']
        if not isinstance(communities, dict) or not communities:
            raise ValueError('Catalogue communities must be a nonempty mapping')
        self.communities = communities
        self.by_label = {}
        for canonical, definition in communities.items():
            if not valid_label(canonical):
                raise ValueError('Canonical community names must be nonempty, trimmed labels without placeholders')
            if not isinstance(definition, dict) or set(definition) - {'description', 'synonyms'}:
                raise ValueError(f'{canonical}: expected description and optional synonyms')
            if not isinstance(definition.get('description'), str) or not definition['description'].strip():
                raise ValueError(f'{canonical}: description must be a nonempty string')
            synonyms = definition.get('synonyms', [])
            if not isinstance(synonyms, list) or any(not valid_label(s) for s in synonyms):
                raise ValueError(f'{canonical}: synonyms must be a list of trimmed labels without placeholders')
            if len(set(synonyms)) != len(synonyms) or canonical in synonyms:
                raise ValueError(f'{canonical}: redundant synonym')
            for label in [canonical, *synonyms]:
                existing = self.by_label.get(label.casefold())
                if existing is not None and existing != canonical:
                    raise ValueError(f'Ambiguous community label {label!r}: {existing!r} and {canonical!r}')
                self.by_label[label.casefold()] = canonical

    def resolve(self, label):
        return self.by_label.get(label.strip().casefold()) if isinstance(label, str) else None

    def filter_labels(self, label, observed=()):
        canonical = self.resolve(label)
        if canonical is None:
            return []
        labels = [canonical, *self.communities[canonical].get('synonyms', [])]
        labels.extend(value for value in observed if self.resolve(value) == canonical)
        return list(dict.fromkeys(labels))


def load_catalogue(root):
    path = Path(root) / CATALOGUE_PATH
    if path.is_symlink() or path.parent.is_symlink():
        raise ValueError('Catalogue and _SYS/ must not be symlinks')
    if not path.exists():
        return None
    try:
        return Catalogue(yaml.load(path.read_text(), Loader=UniqueKeysLoader))
    except (yaml.YAMLError, ValueError, TypeError) as error:
        raise ValueError(f'{CATALOGUE_PATH}: {error}') from error


def inventory(root, include_journals=False):
    root = Path(root)
    labels = {field: defaultdict(list) for field in ('communities', 'entities')}
    errors, unlabelled = [], []
    for file in markdown_notes(root, include_journals):
        relative = file.relative_to(root).as_posix()
        text = file.read_text()
        if not text.startswith(('---\n', '---\r\n')):
            unlabelled.append(relative)
            continue
        try:
            metadata, _ = frontmatter(text)
        except (ValueError, yaml.YAMLError) as error:
            errors.append(f'{relative}: {error}')
            continue
        if not metadata:
            unlabelled.append(relative)
            continue
        for field, entries in labels.items():
            values = metadata.get(field, [])
            if not isinstance(values, list) or any(not isinstance(v, str) or not v.strip() for v in values):
                errors.append(f'{relative}: {field} must be a list of nonempty strings')
                continue
            for label in dict.fromkeys(values):
                entries[label].append(relative)
    return {
        'scope': 'including-journals' if include_journals else 'permanent-notes-and-indexes',
        **{field: {label: {'count': len(notes), 'notes': notes}
                   for label, notes in sorted(entries.items())} for field, entries in labels.items()},
        'unlabelled_notes': unlabelled, 'errors': errors,
    }


def normalization_plan(root):
    root = Path(root)
    catalogue = load_catalogue(root)
    if catalogue is None:
        raise ValueError(f'Missing {CATALOGUE_PATH}; review and adopt a catalogue before planning normalization')
    changes, unresolved, errors = [], [], []
    for file in markdown_notes(root):
        relative = file.relative_to(root).as_posix()
        content = file.read_bytes()
        if not content.startswith((b'---\n', b'---\r\n')):
            unresolved.append({'file_path': relative, 'reason': 'Missing YAML frontmatter'})
            continue
        try:
            metadata, _ = frontmatter(content.decode())
        except (ValueError, yaml.YAMLError) as error:
            errors.append(f'{relative}: {error}')
            continue
        before = metadata.get('communities')
        if not isinstance(before, list) or not before or any(not isinstance(v, str) or not v.strip() for v in before):
            unresolved.append({'file_path': relative, 'reason': 'Missing or invalid communities'})
            continue
        after = []
        for label in before:
            canonical = catalogue.resolve(label)
            if canonical is None:
                unresolved.append({'file_path': relative, 'label': label, 'reason': 'Unknown community; review its meaning'})
            value = canonical or label
            if value not in after:
                after.append(value)
        if after != before:
            changes.append({'file_path': relative,
                            'expected_sha256': hashlib.sha256(content).hexdigest(),
                            'before': {'communities': before}, 'after': {'communities': after}})
    return {'version': 1, 'vault_path': str(root.resolve()),
            'catalogue_sha256': hashlib.sha256((root / CATALOGUE_PATH).read_bytes()).hexdigest(),
            'changes': changes, 'unresolved': unresolved, 'errors': errors}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    for command in ('inventory', 'filters', 'plan'):
        child = commands.add_parser(command)
        child.add_argument('vault', type=Path)
        if command in ('inventory', 'filters'):
            child.add_argument('--include-journals', action='store_true', help='Also inspect journal metadata; never changes journals')
        if command == 'filters':
            child.add_argument('label', help='Community name or an explicit catalogue synonym')
    args = parser.parse_args()
    if not args.vault.is_dir():
        raise ValueError(f'Vault directory does not exist: {args.vault}')
    if args.command == 'inventory':
        result = inventory(args.vault, args.include_journals)
    elif args.command == 'plan':
        result = normalization_plan(args.vault)
    else:
        catalogue = load_catalogue(args.vault)
        observed = inventory(args.vault, args.include_journals)
        canonical = catalogue.resolve(args.label) if catalogue else None
        result = {'canonical': canonical,
                  'communities': catalogue.filter_labels(args.label, observed['communities']) if catalogue else [],
                  'errors': observed['errors']}
        if canonical is None:
            print('WARN: No catalogue match. Use an unfiltered query or labels verified in existing notes.', file=sys.stderr)
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return bool(result.get('errors'))


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, ValueError, TypeError, UnicodeError) as error:
        raise SystemExit(f'Metadata catalogue: {error}') from error
