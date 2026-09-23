# NASA Isoluminant Corpus v1 Provenance

This corpus supports ASTSK-37. It uses NASA Image and Video Library medium derivatives so the assets are small enough to commit without Git LFS and are deterministic across runs.

## LicenseRef-NASA-Media-PD

`LicenseRef-NASA-Media-PD` means NASA media that is generally not subject to U.S. copyright under NASA's Images and Media Usage Guidelines, with NASA acknowledged as source and with no implication of NASA endorsement. NASA's guidance also warns that third-party copyrighted material, NASA identifiers, and identifiable people require additional care. Assets in this corpus were screened against those restrictions before commit.

Guideline: <https://www.nasa.gov/nasa-brand-center/images-and-media/>

## Selection Rules

- Decision stratum assets are natural or camera-visible imagery.
- Diagnostic assets are false-color or scientific composites and cannot promote the default.
- Assets marked as third-party copyright are excluded.
- Images whose primary subject is a NASA logo, insignia, identifier, employee, astronaut, or recognizable person are excluded.
- `assets.csv` is the machine-readable source of truth for stratum and asset metadata.

## Assets

| stem | stratum | NASA ID | credit | source |
| --- | --- | --- | --- | --- |
| earthrise-artemis | natural | art002e009280b | NASA | https://images.nasa.gov/details/art002e009280b |
| noctilucent-clouds | natural | iss071e364425 | NASA | https://images.nasa.gov/details/iss071e364425 |
| aurora-moscow | natural | iss039e009160 | NASA | https://images.nasa.gov/details/iss039e009160 |
| san-francisco-night | natural | iss040e090835 | NASA | https://images.nasa.gov/details/iss040e090835 |
| apollo8-moon | natural | as08-14-2506 | NASA | https://images.nasa.gov/details/as08-14-2506 |
| mars-dingo-gap | natural | PIA17930 | NASA/JPL-Caltech | https://images.nasa.gov/details/PIA17930 |
| carina-cosmic-cliffs | diagnostic-false-color | carina_nebula | NASA/ESA/CSA/STScI | https://images.nasa.gov/details/carina_nebula |
| wise-eagle-nebula | diagnostic-false-color | PIA25433 | NASA/JPL-Caltech | https://images.nasa.gov/details/PIA25433 |
