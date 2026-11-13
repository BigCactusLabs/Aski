"""Reproduce ASKI-87 paired rows and the preregistered rule from retained exports."""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import statistics

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--input-dir', type=Path, default=Path(__file__).resolve().parent)
parser.add_argument('--output-dir', type=Path, required=True)
args = parser.parse_args()
comparison = json.loads((args.input_dir / 'comparison.json').read_text())
raw = json.loads((args.input_dir / 'histogram-samples.json').read_text())
assert comparison['status'] == 'ready_for_review' and not comparison['errors']
assert len(comparison['pairs']) == 5 and len(raw) == 1560
workloads = set(comparison['pairs'][0]['control']['measurements'])
assert len(workloads) == 52
metrics = ['wallClock', 'cpuTotal', 'mallocCountTotal']
primaries = {f'aski87-convert-{cols}cols-os{oversample}-{mode}'
             for cols in [80, 120] for oversample in [4, 8]
             for mode in ['serial', 'parallel']}
e2e = {name for name in workloads if not name.startswith('aski87-histogram-')}
assert len(e2e) == 36 and primaries <= e2e
rows = []
for pair in comparison['pairs']:
    for role in ['control', 'candidate']:
        run = pair[role]
        assert run['status'] == 'valid' and not run['errors']
        assert set(run['measurements']) == workloads
        for workload, values in run['measurements'].items():
            assert set(values) == set(metrics)
            for metric, value in values.items():
                assert value['unit'] == ('#' if metric == 'mallocCountTotal' else 'ns')
                key = f"pair-{pair['pair']}/{role}/{workload}/{metric}"
                blob = raw[key].encode()
                assert hashlib.sha256(blob).hexdigest() == value['sha256'], key
                lines = blob.decode().splitlines()
                assert lines[0].strip() == {'wallClock': 'Time (wall clock) (ns)',
                                    'cpuTotal': 'Time (total CPU) (ns)',
                                    'mallocCountTotal': 'Malloc (total)'}[metric], key
                samples = [int(s) for s in lines[1:]]
                assert len(samples) == value['sample_count'], key
                assert statistics.median(samples) == value['exported_sample_median'], key
    for workload in sorted(workloads):
        for metric in metrics:
            a = pair['control']['measurements'][workload][metric]
            b = pair['candidate']['measurements'][workload][metric]
            control = a['exported_sample_median']
            candidate = b['exported_sample_median']
            # All exports use base units: normalize(Int(value) / 1) preserves the
            # integer exactly, so exporter rounding adds no uncertainty. HDR
            # quantization and host noise remain separate. Zero ratios are undefined.
            row = {'workload': workload, 'metric': metric, 'pair': pair['pair'],
                   'unit': a['unit'], 'control_samples': a['sample_count'],
                   'candidate_samples': b['sample_count'],
                   'control_median': control, 'candidate_median': candidate,
                   'paired_change_percent': 100 * (candidate / control - 1) if control > 0 else None,
                   'export_lower_percent': 100 * (candidate / control - 1) if control > 0 else None,
                   'export_upper_percent': 100 * (candidate / control - 1) if control > 0 else None}
            rows.append(row)
summary = {}
primary_results = {}
guard_results = {}
for workload in sorted(workloads):
    summary[workload] = {}
    for metric in metrics:
        group = [r for r in rows if r['workload'] == workload and r['metric'] == metric]
        assert len(group) == 5
        def median(field):
            values = [r[field] for r in group]
            return statistics.median(values) if all(v is not None for v in values) else None
        upper = [r['export_upper_percent'] for r in group]
        lower = [r['export_lower_percent'] for r in group]
        defined = all(v is not None for v in upper)
        possible_regressions = sum(v is None or v > 3 for v in upper)
        certain_regressions = sum(v is not None and v > 3 for v in lower)
        v = {'median_percent': median('paired_change_percent'),
             'median_export_lower_percent': median('export_lower_percent'),
             'median_export_upper_percent': median('export_upper_percent'),
             'improving_pairs_at_upper_bound': sum(v is not None and v < 0 for v in upper),
             'certain_pairs_over_3_percent': certain_regressions,
             'possible_pairs_over_3_percent': possible_regressions,
             'control_sample_counts': [r['control_samples'] for r in group],
             'candidate_sample_counts': [r['candidate_samples'] for r in group]}
        summary[workload][metric] = v
        if workload in e2e:
            state = 'pass' if defined and possible_regressions < 4 else ('fail' if certain_regressions >= 4 else 'undetermined')
            guard_results[f'{workload}/{metric}'] = state
        if workload in primaries and metric == 'wallClock':
            state = 'pass' if (defined and v['median_export_upper_percent'] <= -5
                               and v['improving_pairs_at_upper_bound'] >= 4) else 'not_established'
            primary_results[workload] = state
outcome = 'supported' if all(v == 'pass' for v in primary_results.values()) and all(v == 'pass' for v in guard_results.values()) else 'not_supported'
result = {'numeric_rule_outcome': outcome,
          'adoption_verdict': 'requires_native_gate_independent_review_and_lead_ruling',
          'primary_results': primary_results, 'guard_results': guard_results,
          'limitations': ['Synthetic gradient on one Mac; not a general product speedup.',
                         'Export bounds do not cover HDR three-significant-digit quantization or host noise.',
                         'HDR exports are distributions, not chronological independent iterations; the pair is the repetition unit.',
                         'Per-arm sample counts can differ under the original duration limit.',
                         'Logical map bytes are not a process RSS bound. Tile and temporal paths have no paired workload here.'],
          'workloads': summary}
args.output_dir.mkdir(parents=True, exist_ok=True)
with (args.output_dir / 'paired-medians.csv').open('w', newline='') as stream:
    writer = csv.DictWriter(stream, fieldnames=rows[0], lineterminator='\n')
    writer.writeheader()
    writer.writerows(rows)
(args.output_dir / 'summary.json').write_text(json.dumps(result, indent=2) + '\n')
print(f'{len(rows)} paired rows; numeric rule: {outcome}')
for name, state in primary_results.items():
    print(name, state, summary[name]['wallClock']['median_percent'])
for name, state in guard_results.items():
    if state != 'pass':
        print('Guard', state, name)
