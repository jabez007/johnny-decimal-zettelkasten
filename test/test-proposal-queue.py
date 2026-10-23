#!/usr/bin/env python3
"""Check scripts/proposal-queue.mjs against small fixture vaults."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1]
TARGET = 'LIFE/10-Home/11-Maintenance/LIFE.11.01.md'
NOTE = """---
entities: [gutters]
communities: [LIFE.11]
status: distilled
---
[[LIFE.00.00]]

# Gutters need cleaning twice a year

Clean the gutters every spring and autumn.
"""
SOURCE_RECORD = """---
record_type: knowledge-source
source_id: S-20261023-8F3D
source_kind: article
source_url: 'https://example.org/gutters'
captured_at: '2026-10-23'
---
# Gutter guards

## Excerpts

> Guards keep most spring debris out of the gutter.

## Notes

Second paragraph of the article.
"""
TAIL = """
## Why

The guards changed the schedule.

## Evidence

Observed fact: S-20261023-8F3D.

## Conflicts

Not applicable.

## Sensitivity check

No private material.

## Links

Not applicable.

## Log entry

Not applicable.

## Open questions

Not applicable.

## Review

- 2026-10-23, revision 1: queued.
"""


def proposal(pid='P-20261023-A91B', state='pending', operation='update', change=None,
             sources='[S-20261023-8F3D]', extra='', target=TARGET):
    if change is None:
        change = """### Replace

~~~~markdown
Clean the gutters every spring and autumn.
~~~~

~~~~markdown
Clean the gutters every autumn.
~~~~
"""
    return f"""---
record_type: knowledge-proposal
proposal_id: {pid}
state: {state}
revision: 1
operation: {operation}
target_path: {target}
source_ids: {sources}
created_at: '2026-10-23'
updated_at: '2026-10-23'
{extra}---
# Gutter guards halve the cleaning schedule

## Change

{change}{TAIL}"""


class ProposalQueueTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix='proposal-queue-')
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        (self.root / 'scripts').mkdir()
        shutil.copyfile(SOURCE / 'scripts/proposal-queue.mjs', self.root / 'scripts/proposal-queue.mjs')
        self.vault = self.root / 'vaults/demo'
        self.write(TARGET, NOTE)
        self.write('.sources/S-20261023-8F3D.md', SOURCE_RECORD)
        self.env = {'PATH': os.environ['PATH'], 'HOME': str(self.root / 'home'),
                    'GIT_CEILING_DIRECTORIES': str(self.root.parent)}

    def write(self, relative, text):
        path = self.vault / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def queue(self, *args):
        result = subprocess.run(['node', 'scripts/proposal-queue.mjs', *args], cwd=self.root, env=self.env,
                                stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        return result.returncode, result.stdout

    def assert_problem(self, text):
        code, out = self.queue('check')
        self.assertEqual(code, 1, out)
        self.assertIn(text, out)

    def test_a_consistent_queue_passes_and_lists_only_open_proposals(self):
        self.write('.proposals/P-20261023-A91B.md', proposal())
        self.write('.proposals/P-20261023-0001.md', proposal(
            pid='P-20261023-0001', state='applied', extra="applied_at: '2026-10-23'\n"))
        code, out = self.queue('check')
        self.assertEqual(code, 0, out)
        self.assertIn('The proposal queue is consistent.', out)
        code, out = self.queue('list')
        self.assertEqual(code, 0, out)
        self.assertIn('vaults/demo: 1 open, 1 closed', out)
        self.assertIn(f'P-20261023-A91B  pending r1  update {TARGET}  ok', out)
        self.assertNotIn('P-20261023-0001', out)

    def test_frontmatter_rewritten_by_the_mcp_still_parses(self):
        # obsidian_update_frontmatter turns flow lists into block lists and
        # unquoted dates into timestamps.
        text = proposal(sources='').replace("source_ids: \n", 'source_ids:\n  - S-20261023-8F3D\n')
        text = text.replace("created_at: '2026-10-23'", 'created_at: 2026-10-23T00:00:00.000Z')
        self.write('.proposals/P-20261023-A91B.md', text)
        code, out = self.queue('check')
        self.assertEqual(code, 0, out)

    def test_a_changed_target_blocks_the_proposal(self):
        self.write('.proposals/P-20261023-A91B.md', proposal())
        self.write(TARGET, NOTE.replace('spring and autumn', 'spring, summer, and autumn'))
        self.assert_problem(f'Replace 1: the text to replace is no longer in {TARGET}')

    def test_text_to_replace_must_occur_once(self):
        self.write('.proposals/P-20261023-A91B.md', proposal())
        self.write(TARGET, NOTE + '\nClean the gutters every spring and autumn.\n')
        self.assert_problem('occurs 2 times')

    def test_an_interrupted_publication_reports_landed_edits(self):
        self.write('.proposals/P-20261023-A91B.md', proposal(state='approved'))
        self.write(TARGET, NOTE.replace('every spring and autumn', 'every autumn'))
        code, out = self.queue('check')
        self.assertEqual(code, 0, out)
        self.assertIn('1 edit(s) already landed', out)

    def test_a_create_refuses_an_existing_target(self):
        change = f"### New note\n\n~~~~markdown\n{NOTE}~~~~\n"
        self.write('.proposals/P-20261023-A91B.md', proposal(operation='create', change=change))
        self.assert_problem(f'{TARGET} already exists')

    def test_a_new_note_can_hold_its_own_headings(self):
        change = f"### New note\n\n~~~~markdown\n{NOTE}\n## Why it matters\n\nText.\n~~~~\n"
        target = 'LIFE/10-Home/11-Maintenance/LIFE.11.02.md'
        self.write('.proposals/P-20261023-A91B.md', proposal(operation='create', change=change, target=target))
        code, out = self.queue('check')
        self.assertEqual(code, 0, out)

    def test_missing_sources_and_bad_fields_are_reported(self):
        self.write('.proposals/P-20261023-A91B.md', proposal(
            pid='P-20261023-FFFF', state='done', sources='[S-20261023-0000]', target='../outside.md'))
        code, out = self.queue('check')
        self.assertEqual(code, 1, out)
        for text in ['proposal_id P-20261023-FFFF does not match the file name', 'state must be one of',
                     'source S-20261023-0000 has no record in .sources/', 'target_path must be a vault-relative']:
            self.assertIn(text, out)

    def test_closed_states_need_their_fields(self):
        self.write('.proposals/P-20261023-A91B.md', proposal(state='superseded'))
        self.write('.proposals/P-20261023-0001.md', proposal(pid='P-20261023-0001', state='applied'))
        code, out = self.queue('check')
        self.assertEqual(code, 1, out)
        self.assertIn('needs superseded_by', out)
        self.assertIn('needs applied_at', out)

    def test_every_section_is_required(self):
        self.write('.proposals/P-20261023-A91B.md', proposal().replace('## Conflicts\n', ''))
        self.assert_problem('missing section ## Conflicts')

    def test_a_replace_needs_two_blocks(self):
        change = "### Replace\n\n~~~~markdown\nClean the gutters every spring and autumn.\n~~~~\n"
        self.write('.proposals/P-20261023-A91B.md', proposal(change=change))
        self.assert_problem('each ### Replace needs two ~~~~ blocks')

    def test_a_source_needs_an_excerpt(self):
        self.write('.sources/S-20261023-8F3D.md', SOURCE_RECORD.replace(
            '> Guards keep most spring debris out of the gutter.', 'Guards help.'))
        self.assert_problem('## Excerpts needs at least one quoted passage')

    def test_check_can_name_one_proposal(self):
        self.write('.proposals/P-20261023-A91B.md', proposal())
        self.write('.proposals/P-20261023-0001.md', proposal(pid='P-20261023-0001', state='rejected', sources='[S-20261023-0000]'))
        code, out = self.queue('check', 'P-20261023-A91B')
        self.assertEqual(code, 0, out)
        code, out = self.queue('check', '--vault', 'vaults/demo', 'P-20261023-0002')
        self.assertEqual(code, 1, out)
        self.assertIn('no proposal P-20261023-0002', out)

    def test_bad_arguments_print_usage(self):
        code, out = self.queue('publish')
        self.assertEqual(code, 2, out)
        self.assertIn('Usage:', out)


if __name__ == '__main__':
    unittest.main()
