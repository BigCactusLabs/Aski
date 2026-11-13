"""Descriptive readout only; does not override the official comparator verdict."""
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
root = args.output_dir
root.mkdir(parents=True, exist_ok=True)
comparison = json.loads((args.input_dir / 'comparison.json').read_text())
raw_samples = json.loads((args.input_dir / 'histogram-samples.json').read_text())
assert comparison['errors'] == ['aski93-video-60to12-10s-720p-80cols/mallocCountTotal: units differ between captures']
assert len(comparison['pairs']) == 5
assert all(pair[role]['status'] == 'valid' for pair in comparison['pairs'] for role in ['control', 'candidate'])
# The generic comparator exits at its first mismatch. Check every cell here.
assert len(raw_samples) == 360
assert len(comparison['pairs'][0]['control']['measurements']) == 9
for pair in comparison['pairs']:
    for role in ['control', 'candidate']:
        for workload, metrics in pair[role]['measurements'].items():
            assert set(metrics) == {'wallClock', 'cpuTotal', 'mallocCountTotal', 'peakMemoryResident'}
            for metric, value in metrics.items():
                expected_unit = 'ns' if metric in ['wallClock', 'cpuTotal'] else 'K'
                if metric == 'peakMemoryResident' or (
                    metric == 'mallocCountTotal'
                    and workload == 'aski93-video-60to12-10s-720p-80cols'
                    and role == 'control'
                ):
                    expected_unit = 'M'
                assert value['unit'] == expected_unit, (workload, metric, role, value['unit'])
                key = f"pair-{pair['pair']}/{role}/{workload}/{metric}"
                blob = raw_samples[key].encode()
                assert hashlib.sha256(blob).hexdigest() == value['sha256'], key
                lines = blob.decode().splitlines()
                assert lines[0].endswith(f"({expected_unit})"), key
                samples = [int(s) for s in lines[1:]]
                assert len(samples) == value['sample_count'], key
                assert statistics.median(samples) == value['exported_sample_median'], key
# Pinned BenchmarkResult.swift: BenchmarkUnits uses decimal factors;
# normalize rounds value / factor to nearest-even integer. Preserve +/- half
# an exported unit as an export-rounding interval, not recovered precision.
factors = {'#': 1, 'K': 1000, 'M': 1000000, 'G': 1000000000, 'T': 1000000000000, 'P': 1000000000000000, 'ns': 1}
rows = []
summary = {}
for workload in comparison['pairs'][0]['control']['measurements']:
    summary[workload] = {}
    for metric in ['wallClock', 'cpuTotal', 'mallocCountTotal', 'peakMemoryResident']:
        current = []
        for pair in comparison['pairs']:
            control = pair['control']['measurements'][workload][metric]
            candidate = pair['candidate']['measurements'][workload][metric]
            if metric in ['wallClock', 'cpuTotal']:
                assert control['unit'] == candidate['unit'] == 'ns'
            a = control['exported_sample_median'] * factors[control['unit']]
            b = candidate['exported_sample_median'] * factors[candidate['unit']]
            da = factors[control['unit']] / 2
            db = factors[candidate['unit']] / 2
            assert a > da
            row = {'workload': workload, 'metric': metric, 'pair': pair['pair'],
                   'control_export_median': control['exported_sample_median'], 'control_unit': control['unit'],
                   'candidate_export_median': candidate['exported_sample_median'], 'candidate_unit': candidate['unit'],
                   'control_base_units': a, 'candidate_base_units': b,
                   'paired_change_percent': 100 * (b - a) / a,
                   'export_rounding_lower_percent': 100 * ((b-db)/(a+da)-1),
                   'export_rounding_upper_percent': 100 * ((b+db)/(a-da)-1)}
            current.append(row)
            rows.append(row)
        summary[workload][metric] = {
            'median_percent': statistics.median(r['paired_change_percent'] for r in current),
            'median_export_rounding_lower_percent': statistics.median(r['export_rounding_lower_percent'] for r in current),
            'median_export_rounding_upper_percent': statistics.median(r['export_rounding_upper_percent'] for r in current),
            'pairs_improving_even_at_upper_bound': sum(r['export_rounding_upper_percent'] < 0 for r in current),
            'pairs_over_3_even_at_lower_bound': sum(r['export_rounding_lower_percent'] > 3 for r in current),
            'pairs_possibly_over_3_at_upper_bound': sum(r['export_rounding_upper_percent'] > 3 for r in current),
        }
with (root / 'paired-medians.csv').open('w') as stream:
    writer = csv.DictWriter(stream, fieldnames=rows[0].keys()); writer.writeheader(); writer.writerows(rows)
result = {'status':'descriptive_only', 'adoption_verdict':'see_video_frame_selection_note_for_human_adoption_verdict',
          'official_comparison_status':'invalid_mismatched_allocation_units',
          'normalization_source':'package-benchmark 1.35.0, BenchmarkResult.swift BenchmarkUnits and normalize, BenchmarkTool+Export.swift histogramSamples',
          'limitations':['Scaling does not recover precision lost in integer export.', 'Bounds cover export rounding only, not HDR histogram quantization or host noise.', 'Independent Opus review accepted the instrument and unit-aware method; the human adoption ruling is in the canonical note.', 'HDR histograms use three significant digits; +/-0.25 percentage-point sensitivity around export bounds does not change aggregate rule outcomes.', 'Host was not idle. RSS samples are cumulative process maxima during the measured loop, not independent samples or setup/warmup peaks.'],
          'workloads':summary}
(root / 'summary.json').write_text(json.dumps(result,indent=2)+'\n')
print('Saved 180 paired rows; official comparison remains invalid. Adoption is recorded in the canonical note.')
for name, values in summary.items():
    print(name, {metric:round(value['median_percent'],2) for metric,value in values.items()})
    for metric,value in values.items():
        if value['pairs_possibly_over_3_at_upper_bound'] >= 4:
            print('Unresolved rounding/control concern:', metric, value)
