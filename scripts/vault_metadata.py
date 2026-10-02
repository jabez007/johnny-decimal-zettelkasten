"""Shared YAML and note readers for read-only vault checks."""
from pathlib import Path
import re

try:
    import yaml
except ImportError:
    raise SystemExit('Vault validation requires PyYAML. Install python3-yaml or PyYAML in this Python environment.')


class UniqueKeysLoader(yaml.SafeLoader):
    pass


def unique_mapping(loader, node, deep=False):
    values = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        try:
            if key in values:
                raise ValueError(f'Duplicate YAML key: {key}')
            values[key] = loader.construct_object(value_node, deep=deep)
        except TypeError as error:
            raise ValueError('YAML mapping keys must be scalar values') from error
    return values


UniqueKeysLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, unique_mapping)


def frontmatter(text):
    match = re.match(r'\A---\r?\n(.*?)^---(?:\r?\n|$)', text, re.S | re.M)
    if not match:
        raise ValueError('Missing YAML frontmatter')
    data = yaml.load(match[1], Loader=UniqueKeysLoader)
    if data is None:
        data = {}
    if not isinstance(data, dict):
        raise ValueError('Frontmatter must be a mapping')
    return data, text[match.end():].lstrip()


def markdown_notes(root, include_journals=False):
    root = Path(root)
    if not root.is_dir():
        raise ValueError(f'Vault directory does not exist: {root}')
    for file in sorted(root.rglob('*')):
        relative = file.relative_to(root)
        if any(part.startswith('.') for part in relative.parts):
            continue
        if relative.parts[0] == '_SYS' or (relative.parts[0] == 'JRNL' and not include_journals):
            continue
        if file.is_symlink():
            raise ValueError(f'{relative}: Symlinks are unsupported in a metadata inventory')
        if file.is_file() and file.suffix == '.md':
            yield file
