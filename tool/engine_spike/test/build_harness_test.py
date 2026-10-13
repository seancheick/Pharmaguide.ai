"""Exercise the real shell harness with synthetic runtimes, without compiling."""
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile
import unittest


BUILD = Path(__file__).resolve().parents[1] / "build.sh"


class BuildHarnessTest(unittest.TestCase):
    def run_build(self, mode="ok", golden=None, system=None):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            spike = root / "tool/engine_spike"
            (spike / "golden").mkdir(parents=True)
            original = json.dumps(golden or {"pre_add": []}, indent=2) + "\n"
            reviewed = spike / "golden/spike_findings.json"
            reviewed.write_text(original)
            bindir = root / "bin"
            bindir.mkdir()
            system = system or platform.system()
            # A whitelist isolates runtime discovery even on Linux hosts where
            # /usr/bin/node exists. Do not inherit any other executable paths.
            for command in ["grep", "head", "ls", "awk", "gzip", "wc", "cmp", "tr"]:
                (bindir / command).symlink_to(shutil.which(command))

            def executable(name, source):
                path = bindir / name
                path.write_text(source)
                path.chmod(0o755)

            executable("uname", f"#!/bin/sh\nprintf '%s\\n' {system}\n")
            executable("time", f"""#!{sys.executable}
import subprocess,sys
expected = '-l' if {system!r} == 'Darwin' else '-v'
if sys.argv[1] != expected:
    sys.exit('wrong timing flag for ' + {system!r} + ': ' + sys.argv[1])
result = subprocess.run(sys.argv[2:])
if {system!r} == 'Darwin':
    print('0.01 real 0.00 user 0.00 sys\\n1024 maximum resident set size', file=sys.stderr)
else:
    print('Elapsed (wall clock) time (h:mm:ss or m:ss): 0:00.01\\nMaximum resident set size (kbytes): 1024', file=sys.stderr)
sys.exit(result.returncode)
""")
            executable("python3", f"""#!{sys.executable}
import os,sys
if sys.argv[1].endswith('make_overlay.py'):
    os.makedirs('tool/engine_spike/.build', exist_ok=True)
else:
    os.execv({sys.executable!r}, [{sys.executable!r}] + sys.argv[1:])
""")
            runtime = "#!/bin/sh\nprintf '%s\\n' '{\"pre_add\":[]}' 'TIMING {}'\n"
            executable("dart", f"""#!{sys.executable}
import os,sys
from pathlib import Path
args=sys.argv[1:]
mode=os.environ['SPIKE_TEST_MODE']
if args[0]=='run':
    print('{{"pre_add":[]}}'); print('TIMING {{}}')
else:
    if any('closure_probe' in a for a in args) and mode=='closure_'+args[1]:
        sys.exit(7)
    output=Path(args[args.index('-o')+1])
    output.write_text({runtime!r})
    output.chmod(0o755)
""")
            for name in ["deno", "node"]:
                if mode == "missing_" + name:
                    continue
                executable(name, f"""#!{sys.executable}
import os,sys
if '--version' in sys.argv:
    print('synthetic-runtime'); sys.exit(0)
print('{{"pre_add":' + ('["changed"]' if os.environ['SPIKE_TEST_MODE']=='different_{name}' else '[]') + '}}')
print('TIMING {{}}')
""")
            # Substitute only the measurement executable to exercise both
            # platforms' flags/output while preserving the real shell control flow.
            script = root / "build.sh"
            script.write_text(BUILD.read_text().replace('/usr/bin/time', str(bindir / 'time')))
            result = subprocess.run(["/bin/bash", str(script)], cwd=root,
                env={**os.environ, "PATH": str(bindir),
                     "DART": str(bindir / "dart"), "SPIKE_TEST_MODE": mode},
                capture_output=True, text=True)
            return result, reviewed.read_text(), original

    def test_matching_outputs_pass_without_rewriting_reviewed_golden(self):
        for system in ["Darwin", "Linux"]:
            with self.subTest(system=system):
                result, after, before = self.run_build(system=system)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(after, before)
                self.assertIn('maximum resident', result.stdout.lower())
                self.assertIn('real' if system == 'Darwin' else 'elapsed', result.stdout.lower())

    def test_changed_vm_cannot_replace_reviewed_golden(self):
        result, after, before = self.run_build(golden={"pre_add": ["reviewed"]})
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('VM differs from reviewed golden', result.stderr)
        self.assertEqual(after, before)

    def test_runtime_difference_is_failure(self):
        for runtime in ["deno", "node"]:
            with self.subTest(runtime=runtime):
                result, _, _ = self.run_build("different_" + runtime)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn(runtime + ' DIFFERS from vm', result.stderr)

    def test_missing_runtime_is_failure(self):
        for runtime in ["deno", "node"]:
            with self.subTest(runtime=runtime):
                result, _, _ = self.run_build("missing_" + runtime)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn('Required runtime missing: ' + runtime, result.stderr)

    def test_closure_compile_failure_is_failure(self):
        for target in ["js", "exe"]:
            with self.subTest(target=target):
                result, _, _ = self.run_build("closure_" + target)
                self.assertEqual(result.returncode, 7, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
