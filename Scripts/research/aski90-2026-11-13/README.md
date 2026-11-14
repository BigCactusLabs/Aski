# ASKI-90 fixed-palette display reuse — rejected

The candidate did not meet its pre-registered end-to-end benefit rule. **One of
16 primary cases passed; all 44 regression guards passed.** No fixed-palette
reuse code is adopted from this study. This is a result for the recorded
synthetic workloads on one Mac, not proof that reuse can never help another
workload.

The complete study retains five adjacent, alternating control/candidate pairs
for each selection: 70 conversion workloads, 36 setup workloads and eight tile
guards. Every required cell exported ten histogram observations per arm. The
portable bundle contains 3,500 raw histogram exports and 1,750 paired rows.
The pair is the repetition unit; histogram observations are not independent
chronological runs. Preparation captures are recorded and excluded from the
paired result.

The rule required at least 5% median paired wall improvement in **every** primary,
with at least four of five pairs improving. ANSI16, sRGB, serial, 512 columns
passed at 5.43%; the other 15 cases did not meet the rule. The original rule and
all outcomes remain in [pre-registration.json](pre-registration.json) and
[summary.json](summary.json). No threshold was changed after measurement.

## Reproduce the numerical result

```bash
python3 -B reproduce.py --output-dir /path/to/new-readout
```

The output directory must be new. The script verifies retained file/sample
hashes, units, sample counts, medians and canonical comparison rows before it
evaluates the literal primary and guard rules. [paired-medians.csv](paired-medians.csv)
includes raw setup batch costs and costs divided by 1,000 per operation. Twelve
setup percentage cells have a zero control and stay undefined; their absolute
costs remain available. Setup is attribution, not an adoption criterion.

## Scope and provenance

The scalar and candidate revisions, original report/log/source hashes, host
conditions, allocator observations and excluded preparations are in
[provenance.json](provenance.json). Known local path prefixes use documented
portable labels. The original unredacted file hashes are retained.

The host was an M3 Max with 14 CPU cores and 36 GiB, macOS 27.0.1, Xcode 27.0 and
Apple Swift 6.4, on AC power. Desktop/system activity was present and varied;
this was not an idle-host study. No other batch builds, tests, benchmarks or
profiles ran concurrently, and the recorded checks found no thermal/performance
warning. All observations are retained. Base-unit exports still have the
benchmark framework's HDR histogram quantization.

Both exact arms passed the full local `just check`. The candidate passed 1,544
core tests, 177 media tests and both deadlock sentinels, plus format, build,
drift and DocC checks. The scalar passed 1,537 core tests, the same media and
sentinel counts, and the other gates. Candidate parity covers exact colors,
alpha, brightness, ties, glyphs and parallel use. A separate 11-workload
compatibility capture passed, as did the five unchanged color/animation
absolute budgets. [native-checks.json](native-checks.json) records their commands,
exits and evidence hashes. Capture validity and budget acceptance are separate checks.

[source-replay.json](source-replay.json) describes the two retained patches for
the scalar instrument and treatment. These preserve the experimental source
without introducing a production option. The original local candidate/control
branches also remain intact; no remote availability is implied.
