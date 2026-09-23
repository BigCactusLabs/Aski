# NASA Steerable Corpus v1 Provenance

This corpus supports ASTSK-42 (steerable oriented-energy descriptor channel — attempt #3 on the wall that KILLED ASTSK-35). It supplies three NASA-produced photographs chosen for structural diversity, so the decisive steerable-channel gate (`AskiColorLab steerable-channel`) can characterize native-footprint GMSD pick-quality against real continuous-tone content rather than only the synthetic oriented battery.

The decisive run needs source blocks that stay ≥ the 24×24 oracle footprint at native resolution across the **full** frozen column sweep `{48, 64, 80, 96, 120}`. The binding column is 120: `120 × 24 = 2880`, so every fixture's short side must be ≥ 2880; the corpus is prepared to a square **3072 px** short side (3072/120 = 25.6 px/cell ≥ 24). This is why `nasa-structure-v1` (2048 px) is insufficient here (2048/96 = 21, 2048/120 = 17, both < 24) and a new corpus was sourced. Each asset is taken from the NASA Image and Video Library `~orig` derivative (≥3712 px short side) and prepared deterministically to a 3072×3072 grayscale PNG. **The committed PNG bytes are canonical**; the prep recipe below is provenance, since `sips`/ColorSync resampling is not guaranteed byte-identical across macOS versions.

## LicenseRef-NASA-Media-PD

`LicenseRef-NASA-Media-PD` means NASA media that is generally not subject to U.S. copyright under NASA's Images and Media Usage Guidelines, with NASA acknowledged as source and with no implication of NASA endorsement. NASA's guidance also warns that third-party copyrighted material, NASA identifiers, and identifiable people require additional care.

Guideline: <https://www.nasa.gov/nasa-brand-center/images-and-media/>

## Selection Rules

- The corpus carries exactly one asset per structural stratum: `gradient-limb`, `concentric-texture`, `oriented-ridges`. The strata span the three regimes the steerable channel is meant to be exercised on (smooth gradient + a single hard edge; curved/concentric texture; oriented linear structure). `oriented-ridges` (Saharan dune ridges) replaces `nasa-structure-v1`'s `oriented-grid` (a city-light grid) because no ≥3072 px short-side night-grid original was available in the catalog — the older city-grid frames were shot at 4256×2832 (short side < 3072); dune ridges supply equivalent oriented line structure at the required resolution.
- **NASA-produced imagery only.** NASA media is only *generally* free of U.S. copyright and the catalog can contain third-party-restricted material, so the selection rule rejects any asset whose catalog record marks third-party copyright, identifiable people, or restricted insignia.
- Per-asset rights verification (no `copyright` / `secondary_creator` field set in the API record; no third-party "courtesy"/"©"/agency credit in the description; no identifiable people; no logo/insignia as primary subject) is recorded in the table below.
- `assets.csv` is the machine-readable source of truth for stratum and asset metadata.

## Deterministic Preparation

Each asset was fetched from `images-assets.nasa.gov` as its `~orig` derivative on 2026-06-27, then prepared with macOS `sips` in three documented steps (all three originals are landscape 5568×3712, so the short side is the height):

```sh
sips --resampleHeight 3072 <orig> --out s1.png                                   # short-side resample to 3072
sips --matchTo "/System/Library/ColorSync/Profiles/Generic Gray Gamma 2.2 Profile.icc" s1.png --out s2.png   # grayscale (Generic Gray, 2.2 TRC)
sips --cropToHeightWidth 3072 3072 s2.png --out <stem>.png                        # 3072×3072 centered crop
```

Output verified single-channel (`samplesPerPixel: 1`, `space: Gray`) at exactly 3072×3072. All three prepared PNGs are < 2 MB (258 KB / 1.68 MB / 1.71 MB; corpus total ≈ 3.6 MB), so they are committed directly — **no Git LFS** — matching the `nasa-structure-v1` / `nasa-occupancy-v1` precedent and the corpus governance threshold (track only assets > ~2 MB or corpora > ~50 MB).

Canonical byte fingerprints (SHA-256) of the committed PNGs:

| prepared_file | sha256 |
| --- | --- |
| assets/earth-limb-sunrise.png | `2eba66f29cf2db6444c480987fa2a4c84333d52c4bcee993b8d5cb21ecfeb297` |
| assets/vavilov-crater.png | `73aa37505497cc4020f2d71688fe942ab2265f1f0853602632d3ce2f3f6049ec` |
| assets/sahara-dunes.png | `b784230ce38c90634f38c9d11b94a72bddcf87fa354455d5b1ca6fa8ead55a56` |

## Asset Checks

Image credit: NASA (acknowledged as source; no implication of endorsement).

| stem | stratum | NASA ID | orig dims | credit | source | rejection checks |
| --- | --- | --- | --- | --- | --- | --- |
| earth-limb-sunrise | gradient-limb | iss059e027932 | 5568×3712 | NASA | https://images.nasa.gov/details/iss059e027932 | NASA ~orig derivative (JSC, Expedition 59, 2019-04-21); no `copyright`/`secondary_creator` in API record; smooth atmospheric gradient + hard limb edge; no identifiable people; no third-party credit |
| vavilov-crater | concentric-texture | art002e012093 | 5568×3712 | NASA | https://images.nasa.gov/details/art002e012093 | NASA ~orig derivative (JSC, Artemis II lunar flyby; description "Credit: NASA"); no `copyright`/`secondary_creator` in API record; concentric crater-rim texture; no people; no insignia |
| sahara-dunes | oriented-ridges | iss066e137375 | 5568×3712 | NASA | https://images.nasa.gov/details/iss066e137375 | NASA ~orig derivative (JSC, Expedition 66, 2022-02-07); no `copyright`/`secondary_creator` in API record; oriented Saharan dune ridges + sandstone plateaus; no identifiable people; no insignia |

### Per-asset notes

- **earth-limb-sunrise** (`iss059e027932`) — "The sun's first rays peek above Earth's limb highlighting the thin blue atmosphere during an orbital sunrise as the International Space Station orbited 255 miles above Indonesia." Center crop retains the atmospheric gradient stack and the limb edge. Best-case smooth-gradient-plus-edge content.
- **vavilov-crater** (`art002e012093`) — "Hertzsprung Basin comes into view with its distinctive two concentric rings of mountains … Vavilov crater—identified by its central peak." Center crop retains the dense, curved crater field. Curved/concentric texture content. (Reused from `nasa-structure-v1`, re-prepared at 3072 px; the orig short side 3712 ≥ 3072.)
- **sahara-dunes** (`iss066e137375`) — "A portion of the Sahara Desert in Algeria, with sand dunes, rocky platforms and sandstone plateaus, is pictured from the International Space Station as it orbited 259 miles above the African nation." Center crop retains parallel dune ridges and plateau edges — oriented linear-structure content at the required resolution.
