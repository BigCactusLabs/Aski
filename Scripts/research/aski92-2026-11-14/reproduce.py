#!/usr/bin/env python3
"""Replay retained ASKI-92 measurements and source patches without native jobs."""
import hashlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def require(condition, message):
    if not condition:
        raise ValueError(message)


def read(path):
    return json.loads(path.read_text())


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + "\n")


def digest(blob):
    return hashlib.sha256(blob).hexdigest()


def run(argv, cwd=None):
    return subprocess.run(argv, cwd=cwd, check=True, capture_output=True, text=True).stdout


def main():
    for name, expected in read(HERE / 'artifact-hashes.json').items():
        require(digest((HERE / name).read_bytes()) == expected, 'artifact hash: ' + name)
    reports = read(HERE / 'capture-reports.json')
    histograms = read(HERE / 'histogram-samples.json')
    rule = read(HERE / 'pre-registration.json')
    profiles = read(HERE / 'allocation-profiles.json')
    with tempfile.TemporaryDirectory(prefix='aski92-reproduce-') as directory:
        work = Path(directory)
        used = set()
        for capture, report in reports.items():
            require(report['status'] == 'valid' and report['complete'] and not report['errors'], capture)
            write(work / capture / 'report.json', report)
            for result in report['results'].values():
                for metric in result['metrics'].values():
                    key = capture + '/' + metric['file']
                    require(key not in used, 'duplicate histogram: ' + key)
                    used.add(key)
                    blob = histograms[key].encode()
                    require(digest(blob) == metric['sha256'], 'sample hash: ' + key)
                    rows = blob.decode().splitlines()
                    require(rows[0] == metric['header'] and len(rows) - 1 == metric['sample_count'], 'sample shape: ' + key)
                    require(all(row.isdigit() for row in rows[1:]), 'noninteger sample: ' + key)
                    path = work / key
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_bytes(blob)
        require(used == set(histograms), 'unused histogram exports')
        require(len(reports['phase-candidate']['results']) == 120, 'phase inventory')
        require(set(reports['phase-candidate']['results']) == set(rule['selections']['phase']['workloads']), 'phase registration')
        require(len(reports['existing-tiles']['results']) == 27, 'support inventory')
        for name in ['paired-manifest.json', 'pre-registration.json']:
            (work / name).write_bytes((HERE / name).read_bytes())
        run([sys.executable, '-B', str(ROOT / 'Scripts/research/compare-benchmarks.py'), '--manifest', str(work / 'paired-manifest.json'), '--output-dir', str(work / 'comparison')])
        actual = read(work / 'comparison/comparison.json')
        expected = read(HERE / 'comparison/comparison.json')
        for key in ['workloads', 'capture_order', 'complete_pairs', 'decision_ready', 'status', 'errors', 'compatible_identity', 'decision_rule']:
            require(actual[key] == expected[key], 'canonical comparison differs: ' + key)
        require((work / 'comparison/paired-medians.csv').read_bytes() == (HERE / 'comparison/paired-medians.csv').read_bytes(), 'paired CSV differs')
        run([sys.executable, '-B', str(HERE / 'evaluate.py'), str(work)])
        require(read(work / 'numerical-verdict.json') == read(HERE / 'numerical-verdict.json'), 'numerical verdict differs')
        for name, profile in profiles.items():
            stacks = profile['stacks']
            def expand(event):
                event = dict(event)
                for key in ['stack', 'free_stack']:
                    if key + '_id' in event:
                        identity = event.pop(key + '_id')
                        value = stacks[identity]
                        require(digest(json.dumps(value).encode()) == identity, 'stack hash')
                        event[key] = value
                return event
            parsed = profile['parsed']
            parsed['selected_allocations'] = [expand(event) for event in parsed['selected_allocations']]
            write(work / name / 'parsed.json', parsed)
            run([sys.executable, '-B', str(HERE / 'analyze-lifetimes.py'), str(work / name / 'parsed.json'), str(work / name / 'lifetimes.json'), profile['manifest']['arm']])
            lifetime = profile['lifetimes']
            lifetime['intervals'] = [expand(event) for event in lifetime['intervals']]
            require(read(work / name / 'lifetimes.json') == lifetime, 'lifetime result differs: ' + name)
        # Two generations at one reused address must retain distinct matching frees.
        run([sys.executable, '-B', str(HERE / 'parse-history.py'), str(HERE / 'history-reader-regression.txt'), str(work / 'reader-regression.json')])
        parsed = read(work / 'reader-regression.json')
        require(not parsed['errors'] and not parsed['unknown_event_types'], 'event reader errors')
        require([(e['event'], e['free_event'], e['bytes']) for e in parsed['selected_allocations']] == [(1, 2, 64), (3, 6, 128), (4, 5, 16)], 'generation/free matching')
        # Source replay reconstructs only the declared paths, never the live checkout.
        source = read(HERE / 'source-replay.json')
        archive = subprocess.check_output(['git', 'archive', source['base'], '--', *source['pathspecs']], cwd=ROOT)
        replay = work / 'source'
        replay.mkdir()
        with tarfile.open(fileobj=io.BytesIO(archive)) as stream:
            stream.extractall(replay, filter='data')
        for arm, patch in [('control', 'control-source.patch'), ('candidate', 'candidate-treatment.patch')]:
            require(digest((HERE / patch).read_bytes()) == source['patches'][patch]['sha256'], 'patch hash')
            run(['git', 'apply', '--check', str(HERE / patch)], cwd=replay)
            run(['git', 'apply', str(HERE / patch)], cwd=replay)
            files = {str(p.relative_to(replay)): digest(p.read_bytes()) for p in replay.rglob('*') if p.is_file()}
            require(files == source['sha256_by_arm'][arm], 'source replay differs: ' + arm)
    print(f'PASS: {len(used)} histograms; five pairs; exact verdict/CSV; four lifetime profiles; reader generations; both source replays.')


if __name__ == '__main__':
    main()
