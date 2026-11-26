#!/usr/bin/env python3
"""Bounded, manual CI experiment for #29; never retries a failed contact/run."""
import argparse
import hashlib
import json
import os
import plistlib
import signal
import subprocess
import sys
import time
from pathlib import Path


class StressCampaign:
    target = 'ChessTutorUITests/ManagedGamesCoachingUITests/'
    # Interleave factors so a partial campaign still compares trace/timing/load.
    variants = [
        {'name': 'baseline', 'trace': True, 'timing': 'settled', 'load': False,
         'test': 'testCoachingWorksAcrossNewReopenedAndRelaunchedGames'},
    ] + [
        {'name': '%s-%s-%s' % ('on' if trace else 'off', timing, 'loaded' if load else 'idle'),
         'trace': trace, 'timing': timing, 'load': load,
         'test': 'testShortSavedCardTapsOpenTheSelectedGameAcrossRackTransitions'}
        for trace, timing, load in [
            (False, 'immediate', False), (True, 'immediate', True),
            (False, 'settled', True), (True, 'settled', False),
            (False, 'immediate', True), (True, 'immediate', False),
            (False, 'settled', False), (True, 'settled', True),
        ]
    ]

    def __init__(self, results, derived_data, destination, budget_seconds):
        self.results = results.resolve()
        self.results.mkdir(parents=True, exist_ok=True)
        self.derived_data = derived_data.resolve()
        self.destination = destination
        self.started = time.monotonic()
        self.deadline = self.started + budget_seconds
        self.summary = {'outcome': 'running', 'budget_seconds': budget_seconds, 'runs': []}

    @property
    def remaining(self):
        return max(0, self.deadline - time.monotonic())

    def command(self, args, name, timeout):
        started = time.monotonic()
        timed_out = False
        with (self.results / (name + '.log')).open('w') as output:
            output.write(json.dumps(args) + '\n')
            output.flush()
            process = subprocess.Popen(args, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
            try:
                code = process.wait(timeout=max(0.01, min(timeout, self.remaining)))
            except subprocess.TimeoutExpired:
                timed_out = True
                try:
                    os.killpg(process.pid, signal.SIGINT)
                except ProcessLookupError:
                    pass
                try:
                    process.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    pass
                # The leader can exit while descendants ignore SIGINT.
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait()
                code = 124
        return {'exit_code': code, 'timed_out': timed_out,
                'elapsed_seconds': round(time.monotonic() - started, 2)}

    @staticmethod
    def configured_run(base, variant):
        data = plistlib.loads(base.read_bytes())
        if 'TestConfigurations' in data:
            targets = [target for config in data['TestConfigurations'] for target in config['TestTargets']
                       if target['BlueprintName'] == 'ChessTutorUITests']
        else:
            targets = [data['ChessTutorUITests']] if 'ChessTutorUITests' in data else []
        if len(targets) != 1:
            raise ValueError('Expected exactly one ChessTutorUITests test host')
        targets[0].setdefault('EnvironmentVariables', {}).update({
            'CHESS_SAVED_CARD_STRESS_TRACE': 'on' if variant['trace'] else 'off',
            'CHESS_SAVED_CARD_STRESS_TIMING': variant['timing'],
        })
        # __TESTROOT__ is relative to this file: keep it beside the original.
        output = base.with_name('SavedTap-' + variant['name'] + '.xctestrun')
        output.write_bytes(plistlib.dumps(data))
        return output

    def save(self):
        self.summary['elapsed_seconds'] = round(time.monotonic() - self.started, 2)
        (self.results / 'summary.json').write_text(json.dumps(self.summary, indent=2) + '\n')
        print(json.dumps(self.summary), flush=True)

    def run(self):
        try:
            self.summary['build'] = self.command([
                'xcodebuild', 'build-for-testing', '-project', 'ChessTutor.xcodeproj',
                '-scheme', 'ChessTutor', '-destination', self.destination,
                '-derivedDataPath', str(self.derived_data),
            ], 'build', max(1, self.remaining - 90))
            if self.summary['build']['exit_code']:
                self.summary['outcome'] = 'build_failed'
                return 1
            bases = list((self.derived_data / 'Build/Products').glob('*.xctestrun'))
            if len(bases) != 1:
                raise ValueError('Expected one freshly generated xctestrun file')
            for variant in self.variants:
                if self.remaining < 150:
                    self.summary['outcome'] = 'budget_exhausted_before_next_variant'
                    return 0
                run_file = self.configured_run(bases[0], variant)
                workers = []
                try:
                    if variant['load']:
                        for _ in range(min(2, max(1, (os.cpu_count() or 2) - 1))):
                            workers.append(subprocess.Popen(
                                [sys.executable, str(Path(__file__).resolve()), '--load-worker'],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                            ))
                    print('Starting ' + variant['name'], flush=True)
                    result = self.command([
                        'xcodebuild', 'test-without-building', '-xctestrun', str(run_file),
                        '-destination', self.destination, '-parallel-testing-enabled', 'NO',
                        '-only-testing:' + self.target + variant['test'],
                        '-resultBundlePath', str(self.results / (variant['name'] + '.xcresult')),
                    ], variant['name'], self.remaining - 90)
                finally:
                    for worker in workers:
                        worker.terminate()
                    for worker in workers:
                        worker.wait(timeout=5)
                if result['exit_code'] == 0 and variant['name'] != 'baseline':
                    marker = 'SAVED_CARD_STRESS_CONFIG trace=%s timing=%s' % (
                        'on' if variant['trace'] else 'off', variant['timing'])
                    result['configuration_verified'] = marker in (self.results / (variant['name'] + '.log')).read_text()
                    if not result['configuration_verified']:
                        self.summary['outcome'] = 'configuration_not_applied'
                        self.summary['runs'].append(dict(variant, **result))
                        return 1
                self.summary['runs'].append(dict(variant, **result))
                self.save()
                if result['exit_code']:
                    self.summary['outcome'] = 'variant_timeout' if result['timed_out'] else 'variant_failed'
                    return 1
            self.summary['outcome'] = 'all_variants_passed'
            return 0
        except Exception as error:
            self.summary['outcome'] = 'harness_error'
            self.summary['error'] = str(error)
            return 1
        finally:
            self.save()

    @staticmethod
    def main():
        if sys.argv[1:] == ['--load-worker']:
            block = b'x' * (1024 * 1024)
            while True:
                hashlib.sha256(block).digest()
        parser = argparse.ArgumentParser(description=__doc__)
        parser.add_argument('--results', type=Path, default=Path('saved-game-stress-results'))
        parser.add_argument('--derived-data', type=Path, required=True)
        parser.add_argument('--destination', default='platform=iOS Simulator,name=iPad (A16)')
        parser.add_argument('--budget-seconds', type=int, default=1440)
        args = parser.parse_args()
        if not 1 <= args.budget_seconds <= 1440:
            parser.error('Execution budget must be between 1 and 1440 seconds; CI hard cap is 30 minutes')
        return StressCampaign(args.results, args.derived_data, args.destination, args.budget_seconds).run()


if __name__ == '__main__':
    raise SystemExit(StressCampaign.main())
