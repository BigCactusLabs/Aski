# NASA Structure Corpus v1 Provenance

This corpus supports ASTSK-31 (Thread B follow-up: regime-appropriate structure oracle). It supplies three NASA-produced photographs chosen for structural diversity, so the new HaarPSI oracle, the training-free oracle consensus, and the 60D log-polar shape residual can be characterized against real continuous-tone content rather than only synthetic fixtures.

Unlike `nasa-occupancy-v1` (which commits `~medium.jpg` derivatives), the decisive shape-residual run needs source blocks that stay ≥ the 24×24 oracle footprint at native resolution across the full column sweep (44–80) on 2048px fixtures. Each asset is therefore sourced from the NASA Image and Video Library `~orig` derivative (≥2048px short side) and prepared deterministically to a 2048×2048 grayscale PNG. **The committed PNG bytes are canonical**; the prep recipe below is provenance, since `sips`/ColorSync resampling is not guaranteed byte-identical across macOS versions.

## LicenseRef-NASA-Media-PD

`LicenseRef-NASA-Media-PD` means NASA media that is generally not subject to U.S. copyright under NASA's Images and Media Usage Guidelines, with NASA acknowledged as source and with no implication of NASA endorsement. NASA's guidance also warns that third-party copyrighted material, NASA identifiers, and identifiable people require additional care.

Guideline: <https://www.nasa.gov/nasa-brand-center/images-and-media/>

## Selection Rules

- The corpus carries exactly one asset per structural stratum: `gradient-limb`, `concentric-texture`, `oriented-grid`. The strata correspond to the three regimes ASTSK-27 found the structure oracles diverging on (smooth gradients + a single hard edge; curved/concentric texture; oriented line structure).
- **NASA-produced imagery only.** NASA media is only *generally* free of U.S. copyright and the catalog can contain third-party-restricted material, so the selection rule rejects any asset whose catalog record marks third-party copyright, identifiable people, or restricted insignia.
- Per-asset rights verification (no `copyright` / `secondary_creator` field set in the API record; no third-party "courtesy"/"©"/agency credit in the description; no identifiable people; no logo/insignia as primary subject) is recorded in the table below.
- `assets.csv` is the machine-readable source of truth for stratum and asset metadata.

## Deterministic Preparation

Each asset was fetched from `images-assets.nasa.gov` as its `~orig` derivative on 2026-06-13, then prepared with macOS `sips` in three documented steps (all three originals are landscape, so the short side is the height):

```sh
sips --resampleHeight 2048 <orig> --out s1.png                                   # short-side resample to 2048
sips --matchTo "/System/Library/ColorSync/Profiles/Generic Gray Gamma 2.2 Profile.icc" s1.png --out s2.png   # grayscale (Generic Gray, 2.2 TRC)
sips --cropToHeightWidth 2048 2048 s2.png --out <stem>.png                        # 2048×2048 centered crop
```

Output verified single-channel (`samplesPerPixel: 1`, `space: Gray`) at exactly 2048×2048. All three prepared PNGs are < 2 MB, so they are committed directly (no Git LFS), matching the `nasa-occupancy-v1` precedent.

Canonical byte fingerprints (SHA-256) of the committed PNGs:

| prepared_file | sha256 |
| --- | --- |
| assets/earth-limb-sunrise.png | `84e9ce917f1c8e19bbfbf49196e6809b634322fa2fc46af9417b2909d814cdf9` |
| assets/vavilov-crater.png | `bb43bad81793dd52b906f72a17805293887b3aeccae2af2d9304681073b84019` |
| assets/phoenix-night-grid.png | `83ad0e79b1ac04025eeb24c38021dac0dcf3645e4bf6ff2534015167822ea0f9` |

## Asset Checks

Image credit: NASA (acknowledged as source; no implication of endorsement).

| stem | stratum | NASA ID | orig dims | credit | source | rejection checks |
| --- | --- | --- | --- | --- | --- | --- |
| earth-limb-sunrise | gradient-limb | iss028e007274 | 4288×2848 | NASA | https://images.nasa.gov/details/iss028e007274 | NASA ~orig derivative (JSC, Expedition 28); no `copyright`/`secondary_creator` in API record; smooth atmospheric gradient + hard limb edge; no identifiable people; no third-party credit |
| vavilov-crater | concentric-texture | art002e012093 | 5568×3712 | NASA | https://images.nasa.gov/details/art002e012093 | NASA ~orig derivative (JSC, Artemis II lunar flyby; description "Credit: NASA"); no `copyright`/`secondary_creator` in API record; concentric crater-rim texture; no people; no insignia |
| phoenix-night-grid | oriented-grid | iss035e005438 | 4256×2832 | NASA | https://images.nasa.gov/details/iss035e005438 | NASA ~orig derivative (JSC, Expedition 35); no `copyright`/`secondary_creator` in API record; near-nadir city street grid (oriented line structure); no identifiable people; no insignia |

### Per-asset notes

- **earth-limb-sunrise** (`iss028e007274`) — "This view of the sun peeking over the limb of the Earth was taken by the Expedition 28 crew members aboard the International Space Station … All of the layers of the Earth's atmosphere are depicted in a beautiful array of color lit by the sun." Center crop retains the full atmospheric gradient stack and the sun glint on the limb. Best-case smooth-gradient-plus-edge content.
- **vavilov-crater** (`art002e012093`) — "Hertzsprung Basin comes into view with its distinctive two concentric rings of mountains … Vavilov crater—identified by its central peak." Center crop retains the dense, curved crater field; the terminator shadow at lower-left is kept as natural dynamic range. Curved/concentric texture content.
- **phoenix-night-grid** (`iss035e005438`) — "The Phoenix metropolitan area is laid out along a regular grid of city blocks and streets. While visible during the day, this grid is most evident at night, when the pattern of street lighting is clearly visible from above." Center crop retains the orthogonal street grid filling the frame. Oriented line-structure content; the catalog record itself documents the grid.
