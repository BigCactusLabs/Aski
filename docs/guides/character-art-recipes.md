# ASCII art recipes for Swift and macOS

Start with a bundled image, then change its characters, color, or background. These
recipes use Aski's macOS CLI; the same conversion engine is available as a Swift library.

## From image to characters

| Source image | Existing Aski render |
| --- | --- |
| ![The Cosmic Cliffs in the Carina Nebula, before conversion](../Research/Corpus/nasa-occupancy-v1/assets/carina-cosmic-cliffs.jpg) | ![The Cosmic Cliffs rendered by Aski as colored character art](../assets/hero-carina-512.png) |

The render is the existing README artwork: **512 columns × 133 rows of characters**.
Open the image to see the glyphs at full size. The recipes below use smaller grids;
they do not reproduce that image byte for byte.

Image credit: NASA/ESA/CSA/STScI. [Source catalog](https://images.nasa.gov/details/carina_nebula)
and [corpus provenance](../Research/Corpus/nasa-occupancy-v1/PROVENANCE.md) record the
input and its terms. This scientific false-color image is a visual example, not
evidence that one matcher is best for other images.

## Set up once

Use a Mac running macOS 15+ with full Xcode selected and a Swift 6.3+ toolchain.
These commands start from the current `main` source checkout:

```bash
git clone --branch main https://github.com/BigCactusLabs/Aski.git
cd Aski
xcrun swift --version
mkdir -p /tmp/aski-recipes
```

The first render resolves dependencies and builds the executable. Run all recipes
from the repository root. They use the bundled Carina image, so no extra download
or personal photograph is needed.

**Version note:** `--algorithm`, `--coverage`, and `--palette` were added after
`v0.7.0`. The monochrome recipe needs the current source checkout; those flags are
not available in the `v0.7.0` CLI.

## 1. Color character art

Keep the default printable-ASCII set and source-colored glyphs. Save both the text
grid and a PNG with an exact width of 1600 pixels:

```bash
xcrun swift run -c release aski render \
  docs/Research/Corpus/nasa-occupancy-v1/assets/carina-cosmic-cliffs.jpg \
  --columns 120 \
  --output /tmp/aski-recipes/carina-color.txt \
  --render-png /tmp/aski-recipes/carina-color.png \
  --width 1600

open /tmp/aski-recipes/carina-color.png
```

The PNG uses an opaque black background and preserves the source aspect ratio.
The `.txt` file contains characters and line breaks, without color. Columns control
the character grid's detail; `--width` controls the PNG's pixel width.

## 2. A monochrome, dithered treatment

Use the small `minimal` character set with `dotMatrix`, full dither strength, and
white glyph ink on the default black background:

```bash
xcrun swift run -c release aski render \
  docs/Research/Corpus/nasa-occupancy-v1/assets/carina-cosmic-cliffs.jpg \
  --columns 100 \
  --charset minimal \
  --algorithm dotMatrix \
  --coverage 1 \
  --palette monochrome \
  --output /tmp/aski-recipes/carina-monochrome.txt \
  --render-png /tmp/aski-recipes/carina-monochrome.png \
  --width 1600

open /tmp/aski-recipes/carina-monochrome.png
```

Keep `--algorithm dotMatrix` with this recipe: the default `logPolar` matcher
currently produces an all-space grid with `minimal`. `--coverage` controls
Floyd–Steinberg dither strength for `dotMatrix`; setting it to `0` disables dithering.
See the [algorithm guide](../../Sources/Aski/Aski.docc/Algorithms.md) for other pairings
and measured limitations.

## 3. Colored blocks on transparent ground

Choose Unicode block characters and an alpha-zero PNG background:

```bash
xcrun swift run -c release aski render \
  docs/Research/Corpus/nasa-occupancy-v1/assets/carina-cosmic-cliffs.jpg \
  --columns 100 \
  --charset blocks \
  --background clear \
  --output /tmp/aski-recipes/carina-blocks.txt \
  --render-png /tmp/aski-recipes/carina-blocks.png \
  --width 1600

open /tmp/aski-recipes/carina-blocks.png
```

This makes the ground transparent; it does not remove glyphs selected for the
source image's background. Use a raster mask when you want a cutout. A viewer may
display transparent pixels over a checkerboard, white, or another canvas color.

## Use your own image or integrate in Swift

Replace the bundled input path with your image's path, quoting paths that contain
spaces. Keep input and output paths distinct. The
[command-line guide](../../Sources/Aski/Aski.docc/CommandLine.md) covers masks,
manifests, reusable builds, option dependencies, and troubleshooting.

For a Swift app, [Getting Started](../../Sources/Aski/Aski.docc/GettingStarted.md)
shows how to load a `CGImage`, convert it once, and choose text or image output.
[Masking](../../Sources/Aski/Aski.docc/Masking.md) explains photo-to-type dissolves;
[Vesper](../../Sources/Aski/Aski.docc/Vesper.md) describes the fixed duotone library preset.

## Reproduction notes

These commands were checked against the CLI source at
[`06adfdb`](https://github.com/BigCactusLabs/Aski/tree/06adfdb78cfb9af122f23903d05e529364d281f4).
They have not been executed on a Mac for this guide, and the gallery above reuses
existing committed artwork rather than newly generated recipe outputs. Raster output
can vary with OS, fonts, and toolchain; the
[contributor guide](../../CONTRIBUTING.md#toolchain-and-snapshot-baseline) records
the snapshot baseline.
