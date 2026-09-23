# Research methodology — standing rules

Rules that individual research notes learned the hard way, collected in one place so the next battery does not re-learn them. Each rule names the note or task that established it; read that note for the evidence. Add a rule here when a verdict note, a review, or a blotter cut produces one — a rule that lives only inside the note that learned it is not a rule.

## Before the run

- **Pre-register the decision rule, then read numbers.** Commit the rule note (bar, oracles, veto clauses, corpus, regime) before any measurement is read. A rule written after the number is a rationalization. Every decisive note since `docs/Research/2026-08-24-aski-30-28-decisive-rule.md` follows this; ASKI-31 and ASKI-63 re-registered mid-unit when an instrument was found invalid, and changed no threshold.
- **Verify the SPI surface at `file:line` while writing the brief.** A brief that asserts an `@_spi(AskiResearch)` entry point exists must cite it against the current checkout and name the access level. A 2026-08-24 prereq brief asserted per-cell query lanes and `stats.adjustedL` were reachable; both were private, and every arm was unfeedable until an escalation round trip (v1 blotter cut `bl_b0db8c3f50b3`, retired at d412667, `git show d412667:.blotter.jsonl`; the corrected brief is `docs/Research/2026-08-24-aski-30-28-decisive-rule.md` §3).
- **Re-measure the environment before porting an environment fix.** A perf fix that was right in a sibling repo can be a pessimization here; the condition it fixed may be gone. ASKI-54 (build-dir relocation) was reverted on paired measurements.
- **Generate arbiter stimuli from a release build.** `swift run -c release aski lab color arbiter stimuli` at the protocol regime takes about a minute; the same run under a debug build did not finish in 20 minutes (ASKI-56, `docs/Research/2026-08-25-aski56-arbiter-protocol.md` §2.1). The historical `AskiColorLab` replay product remains valid for committed provenance.

## The instrument

- **Measure through an exact lattice, at native resolution.** A verdict measured through the sampling lattice inherits the lattice's defects. Three verdicts have fallen to this: the shape-residual PASS (downscaling blur, ASTSK-27), the regime-oracle line-art claim (ASTSK-31), and the isoluminant dose-response PASS (ASKI-65, 19 rows silently dropped). `SamplingLatticeContractTests` guard the shipping lattice, and lab oracles read the resolved converter lattice through `SampledSource`; ASKI-66 completed the archived-verdict audit.
- **Supersample instrument rasters above the decision resolution.** Rendering glyphs directly at block resolution injects font-hinting artifacts that fake oracle failures; a GMSD gate claim had to be withdrawn once the raster was re-staged as 4x supersample plus integer box downsample (`docs/Research/2026-08-23-aski32-calibrated-recovery.md` §3c; guarded by `AskiColorLabReferenceRecoveryTests`).
- **Cross-check with an agreeing oracle.** MAE is the house oracle (`docs/Research/2026-08-19-house-oracle-audit.md`); GMSD is the convention-independent guard. A verdict one oracle supports and the other contradicts is INCONCLUSIVE, not a narrow PASS.
- **An instrument that can measure its own bin widths is invalid.** The ASKI-63 banding probe binned device columns by `floor(x / advance)` and reported 0.000 at the one integer advance, identical across arms. Validate the probe on a known-difference pair before reading the arms.
- **Single-variable claims are where measurement units die.** Three cross-model review rounds on ASKI-52/26 found three real instrument confounds (un-inverted luma, a 2x font-scale baseline, a PNG-only loader) while the compound delta never moved a byte. A measurement unit gets a cross-model review of its instrument before its numbers are read as a verdict.

## Reading the result

- **A mechanism story that merely fits the numbers is a hypothesis, not a finding.** Label it as such until an independent check has run. The ASKI-54 "portal exclusion already landed" explanation was falsified the same day by the device's own policy files.
- **Build the instrument before arguing the metric.** The ASKI-56 arbiter settled in one sitting what three weeks of reconstruction metrics could only argue about; when two oracles disagree on a promotion, the next step is a blinded sitting, not a third metric.
- **A golden re-record proves determinism, not quality.** A change that moves goldens on the frozen preset carries its selection-ceiling before/after CSV in the same PR (AGENTS.md hard rule; ASKI-31 had to rebuild the pre-change commit to recover the measurement).

## Closing the task

- **Read every acceptance criterion before claiming DONE.** A change that satisfies the first clause of AC #1 says nothing about AC #3. The 2026-09-02 docs audit wrote a wrong DONE recommendation into the backlog on that basis (v1 blotter cut `bl_97e2f915fea1`, retired at d412667).
- **A retraction reaches the front matter, not just the body.** `docs/Research/README.md` and `index.json` are generated from the `summary` field; `research-check` cannot see a body that contradicts its own front matter. Edit the front matter and regenerate.
- **An audit covers the generated artifacts and the sibling task records, not only the files it edited.** The research README, `index.json`, `docs/repo-map.generated.md`, CHANGELOG, and every backlog task the change re-adjudicates are in scope.
