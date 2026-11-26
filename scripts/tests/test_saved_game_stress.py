import os
import signal
import subprocess
import time
import plistlib
import sys
import tempfile
import unittest
from pathlib import Path

from scripts.run_saved_game_stress import StressCampaign


class SavedGameStressTests(unittest.TestCase):
    def test_variant_preserves_testroot_and_other_targets(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            base = root / 'base.xctestrun'
            ui = {'BlueprintName': 'ChessTutorUITests', 'TestBundlePath': '__TESTROOT__/UI.xctest',
                  'EnvironmentVariables': {'KEEP': 'yes'}}
            unit = {'BlueprintName': 'ChessTutorTests', 'EnvironmentVariables': {'UNIT': 'yes'}}
            base.write_bytes(plistlib.dumps({'TestConfigurations': [{'TestTargets': [ui, unit]}]}))
            variant = {'name': 'off-immediate-idle', 'trace': False, 'timing': 'immediate', 'load': False}
            output = StressCampaign.configured_run(base, variant)
            self.assertEqual(output.parent, base.parent)
            targets = plistlib.loads(output.read_bytes())['TestConfigurations'][0]['TestTargets']
            self.assertEqual(targets[1], unit)
            self.assertEqual(targets[0]['TestBundlePath'], ui['TestBundlePath'])
            self.assertEqual(targets[0]['EnvironmentVariables'], {
                'KEEP': 'yes', 'CHESS_SAVED_CARD_STRESS_TRACE': 'off',
                'CHESS_SAVED_CARD_STRESS_TIMING': 'immediate',
            })

    def test_timeout_interrupts_real_process_and_reports_timeout(self):
        with tempfile.TemporaryDirectory() as directory:
            campaign = StressCampaign(Path(directory), Path(directory) / 'build', 'unused', 30)
            code = "import signal,time,sys; signal.signal(signal.SIGINT, lambda *a: sys.exit(0)); print('ready', flush=True); time.sleep(60)"
            result = campaign.command([sys.executable, '-c', code], 'timeout', 0.5)
            self.assertTrue(result['timed_out'])
            self.assertEqual(result['exit_code'], 124)
            self.assertIn('ready', (Path(directory) / 'timeout.log').read_text())

    def test_nonzero_command_is_preserved_without_retry(self):
        with tempfile.TemporaryDirectory() as directory:
            campaign = StressCampaign(Path(directory), Path(directory) / 'build', 'unused', 30)
            result = campaign.command([sys.executable, '-c', "print('one attempt'); raise SystemExit(65)"], 'failure', 5)
            self.assertEqual(result['exit_code'], 65)
            self.assertFalse(result['timed_out'])
            self.assertEqual((Path(directory) / 'failure.log').read_text().splitlines().count('one attempt'), 1)

    def test_legacy_xctestrun_uses_named_target_and_preserves_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory) / 'base.xctestrun'
            original = {'ChessTutorUITests': {'EnvironmentVariables': {'KEEP': 'yes'}},
                        'ChessTutorTests': {'TestBundlePath': '__TESTROOT__/Unit.xctest'},
                        '__xctestrun_metadata__': {'FormatVersion': 1}}
            base.write_bytes(plistlib.dumps(original))
            output = StressCampaign.configured_run(base, {'name': 'legacy', 'trace': True, 'timing': 'settled'})
            result = plistlib.loads(output.read_bytes())
            self.assertEqual(result['__xctestrun_metadata__'], original['__xctestrun_metadata__'])
            self.assertEqual(result['ChessTutorTests'], original['ChessTutorTests'])
            self.assertEqual(result['ChessTutorUITests']['EnvironmentVariables']['CHESS_SAVED_CARD_STRESS_TRACE'], 'on')

    def test_timeout_kills_descendant_even_after_parent_exits(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            pid_file = root / 'child.pid'
            child_code = "import os,signal,time; from pathlib import Path; signal.signal(signal.SIGINT, signal.SIG_IGN); Path(%r).write_text(str(os.getpid())); time.sleep(60)" % str(pid_file)
            parent_code = "import signal,subprocess,sys,time; subprocess.Popen([sys.executable,'-c',%r]); signal.signal(signal.SIGINT, lambda *a: sys.exit(0)); time.sleep(60)" % child_code
            campaign = StressCampaign(root, root / 'build', 'unused', 30)
            child_pid = None
            try:
                result = campaign.command([sys.executable, '-c', parent_code], 'descendant', 1)
                self.assertTrue(pid_file.exists(), 'Child must start before timeout')
                child_pid = int(pid_file.read_text())
                self.assertTrue(result['timed_out'])
                for _ in range(20):
                    state = subprocess.run(['ps', '-o', 'stat=', '-p', str(child_pid)], capture_output=True, text=True).stdout.strip()
                    if not state or state.startswith('Z'):
                        break
                    time.sleep(0.05)
                self.assertTrue(not state or state.startswith('Z'), 'Timed-out command left a running descendant')
            finally:
                if child_pid:
                    try:
                        os.kill(child_pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
