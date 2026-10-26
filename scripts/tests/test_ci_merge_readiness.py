"""Run the actual required app-job shell against successful and failed outcomes."""
import os
from pathlib import Path
import re
import subprocess
import textwrap
import unittest


class MergeReadinessTest(unittest.TestCase):
    def test_required_job_and_failure_outcomes(self):
        workflow = (Path(__file__).resolve().parents[2] / '.github/workflows/ci.yml').read_text()
        job = workflow.split('  merge-ready:\n', 1)[1]
        self.assertIn('if: always()', job)
        self.assertIn('needs: [scope, analyze-and-test]', job)
        self.assertIn('needs.analyze-and-test.result', job)
        script = textwrap.dedent(job.split('        run: |\n', 1)[1])
        for scope, kind, tests, allowed in [
            ('success', 'docs', 'skipped', True),
            ('success', 'full', 'success', True),
            ('success', 'full', 'failure', False),
            ('success', 'full', 'skipped', False),
            ('success', 'full', 'cancelled', False),
            ('failure', 'docs', 'skipped', False),
            ('success', '', 'success', False),
        ]:
            with self.subTest(scope=scope, kind=kind, tests=tests):
                result = subprocess.run(['bash', '-e', '-c', script], env={**os.environ,
                    'SCOPE_RESULT': scope, 'KIND': kind, 'TEST_RESULT': tests})
                self.assertEqual(result.returncode == 0, allowed)
        self.assertRegex(workflow, r'ref: [a-f0-9]{40}\n          path: pipeline-policy')
        self.assertIn('pipeline-policy/scripts/ci_change_scope.py', workflow)
        self.assertIn('bash scripts/test_submission_identity.sh', workflow)


if __name__ == '__main__':
    unittest.main()
