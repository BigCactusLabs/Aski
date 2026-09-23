# NASA Occupancy Corpus v1 Provenance

This corpus supports ASTSK-7 Phase 2 occupancy-aware glyph matching characterization. It uses NASA Image and Video Library medium JPEG derivatives so the assets are deterministic, small enough to commit without Git LFS, and sourced from a stable public catalog.

## LicenseRef-NASA-Media-PD

`LicenseRef-NASA-Media-PD` means NASA media that is generally not subject to U.S. copyright under NASA's Images and Media Usage Guidelines, with NASA acknowledged as source and with no implication of NASA endorsement. NASA's guidance also warns that third-party copyrighted material, NASA identifiers, and identifiable people require additional care.

Guideline: <https://www.nasa.gov/nasa-brand-center/images-and-media/>

## Selection Rules

- Decision strata are `portrait`, `texture`, `line-art`, `dark-scene`, and `colorful`.
- `diagnostic-false-color` assets are included only to reproduce scientific/false-color failure modes; they cannot promote the default.
- Assets marked as third-party copyright are excluded.
- Assets whose primary subject is a NASA logo, insignia, or identifier are excluded.
- Portraits are deliberately included for ASTSK-7 because faces and spacesuits stress occupancy and glyph-detail selection. This differs from ASTSK-37's "no identifiable people" corpus rule. Portrait rows are NASA astronaut portraits from the NASA catalog; their presence does not imply endorsement and they must not be used outside this research corpus without rechecking likeness/endorsement constraints.
- `assets.csv` is the machine-readable source of truth for stratum and asset metadata.

## Asset Checks

Every asset below was fetched from `images-assets.nasa.gov` as the `~medium.jpg` derivative on 2026-06-12. Local verification found 24 JPEG files, all below 2 MB.

| stem | stratum | NASA ID | credit | source | rejection checks |
| --- | --- | --- | --- | --- | --- |
| cernan-portrait | portrait | s64-31845 | NASA | https://images.nasa.gov/details/s64-31845 | NASA medium derivative; portrait exception documented; no third-party copyright notice in API metadata |
| mark-lee-portrait | portrait | S84-40242 | NASA | https://images.nasa.gov/details/S84-40242 | NASA medium derivative; portrait exception documented; no third-party copyright notice in API metadata |
| marsha-ivins-portrait | portrait | s84-37915 | NASA | https://images.nasa.gov/details/s84-37915 | NASA medium derivative; portrait exception documented; no third-party copyright notice in API metadata |
| james-lovell-portrait | portrait | S70-34268 | NASA | https://images.nasa.gov/details/S70-34268 | NASA medium derivative; portrait exception documented; no third-party copyright notice in API metadata |
| apollo11-bootprint | texture | as11-40-5877 | NASA | https://images.nasa.gov/details/as11-40-5877 | NASA medium derivative; lunar regolith texture; no third-party copyright notice in API metadata |
| apollo12-lunar-mound | texture | AS12-46-6832 | NASA | https://images.nasa.gov/details/AS12-46-6832 | NASA medium derivative; lunar surface texture; no third-party copyright notice in API metadata |
| daedalia-planum | texture | PIA15705 | NASA/JPL-Caltech/University of Arizona | https://images.nasa.gov/details/PIA15705 | NASA medium derivative; planetary surface texture; no third-party copyright notice in API metadata |
| iani-chaos | texture | PIA17686 | NASA/JPL-Caltech/University of Arizona | https://images.nasa.gov/details/PIA17686 | NASA medium derivative; planetary surface texture; no third-party copyright notice in API metadata |
| spacecraft-attitude-diagram | line-art | s64-03507 | NASA | https://images.nasa.gov/details/s64-03507 | NASA medium derivative; diagram line structure; no third-party copyright notice in API metadata |
| rcs-function-diagram | line-art | s64-03506 | NASA | https://images.nasa.gov/details/s64-03506 | NASA medium derivative; diagram line structure; no third-party copyright notice in API metadata |
| rocket-systems-diagram | line-art | s64-05966 | NASA | https://images.nasa.gov/details/s64-05966 | NASA medium derivative; diagram line structure; no third-party copyright notice in API metadata |
| reentry-communications-diagram | line-art | s64-04925 | NASA | https://images.nasa.gov/details/s64-04925 | NASA medium derivative; diagram line structure; no third-party copyright notice in API metadata |
| new-york-night | dark-scene | s36-39-014 | NASA | https://images.nasa.gov/details/s36-39-014 | NASA medium derivative; low-light city structure; no third-party copyright notice in API metadata |
| earth-night-iss-090323 | dark-scene | iss040e090323 | NASA | https://images.nasa.gov/details/iss040e090323 | NASA medium derivative; low-light Earth observation; no third-party copyright notice in API metadata |
| earth-night-iss-091208 | dark-scene | iss040e091208 | NASA | https://images.nasa.gov/details/iss040e091208 | NASA medium derivative; low-light Earth observation; no third-party copyright notice in API metadata |
| san-francisco-night | dark-scene | iss040e090835 | NASA | https://images.nasa.gov/details/iss040e090835 | NASA medium derivative; low-light Earth observation; no third-party copyright notice in API metadata |
| aurora-expedition23 | colorful | iss023e058455 | NASA | https://images.nasa.gov/details/iss023e058455 | NASA medium derivative; camera-visible aurora color; no third-party copyright notice in API metadata |
| aurora-sts62 | colorful | sts062-58-025 | NASA | https://images.nasa.gov/details/sts062-58-025 | NASA medium derivative; camera-visible aurora color; no third-party copyright notice in API metadata |
| multicolor-aurora | colorful | iss074e0150531 | NASA | https://images.nasa.gov/details/iss074e0150531 | NASA medium derivative; camera-visible aurora color; no third-party copyright notice in API metadata |
| calbuco-plume | colorful | calbucos-plume-over-chile_17126018810_o | NASA | https://images.nasa.gov/details/calbucos-plume-over-chile_17126018810_o | NASA medium derivative; colorful Earth/cloud contrast; no third-party copyright notice in API metadata |
| tarantula-spitzer-3color | diagnostic-false-color | PIA23647 | NASA/JPL-Caltech | https://images.nasa.gov/details/PIA23647 | NASA medium derivative; false-color diagnostic only; excluded from decision strata |
| infrared-color-explosion | diagnostic-false-color | PIA13449 | NASA/JPL-Caltech | https://images.nasa.gov/details/PIA13449 | NASA medium derivative; infrared false-color diagnostic only; excluded from decision strata |
| saturn-infrared | diagnostic-false-color | PIA13405 | NASA/JPL-Caltech/SSI | https://images.nasa.gov/details/PIA13405 | NASA medium derivative; infrared false-color diagnostic only; excluded from decision strata |
| carina-cosmic-cliffs | diagnostic-false-color | carina_nebula | NASA/ESA/CSA/STScI | https://images.nasa.gov/details/carina_nebula | NASA medium derivative; false-color diagnostic only; excluded from decision strata |
