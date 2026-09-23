# Command-Line Guide

Turn an image into text or PNG, then inspect and record the result without writing an app.

## Requirements and first run

The `aski` executable runs on macOS 15+ and builds with a Swift 6.3+ toolchain selected
through full Xcode. The package uses Apple frameworks; this is not a Linux or Windows CLI.
The commands below run from a source checkout, including before a release tag exists.

```bash
git clone https://github.com/BigCactusLabs/Aski.git
cd Aski
xcrun swift --version
xcrun swift run aski --help
```

The first invocation resolves dependencies and builds the command. Use `xcrun swift`
consistently so a separate Swift installation on `PATH` does not share incompatible
build artifacts with the selected Xcode toolchain.

Try the bundled image:

```bash
mkdir -p /tmp/aski-demo
xcrun swift run -c release aski render \
  docs/Research/Corpus/nasa-occupancy-v1/assets/carina-cosmic-cliffs.jpg \
  --columns 120 \
  --output /tmp/aski-demo/carina.txt \
  --render-png /tmp/aski-demo/carina.png \
  --width 1600
open /tmp/aski-demo/carina.png
```

The remaining recipes use `photo.jpg` and `mask.png` as placeholders for your own files.
Quote paths that contain spaces and choose output paths distinct from your inputs.

## Text, PNG, or both

`render` is the default subcommand. These two commands are equivalent:

```bash
xcrun swift run aski photo.jpg --columns 80
xcrun swift run aski render photo.jpg --columns 80
```

Text goes to standard output unless `--output` names a file. It is a plain glyph grid,
not ANSI-colored terminal output. `--render-png` adds a color image; it does not suppress
the text output. Request both files explicitly:

```bash
xcrun swift run aski render photo.jpg \
  --columns 100 --output photo.txt --render-png photo-ascii.png
```

`--columns` controls grid detail, not output pixel width. The CLI preserves the source
aspect ratio in PNG output by default; `--no-preserve-aspect` requests the historical
glyph-cell aspect instead. Direct library rendering has a different default, so pass
`preserveSourceAspect: true` explicitly when matching a CLI render. See <doc:Rendering>.

## Blocks, transparent backgrounds, and exact sizes

```bash
xcrun swift run aski render photo.jpg \
  --charset blocks --background clear --render-png blocks.png --width 1600
```

`--background clear` (or `transparent`) creates an alpha-zero PNG ground; omitted,
the background is opaque black. It does not remove glyphs selected for the source's
background. Use a mask for a cutout.

`--width` requires `--render-png` and sets the exact PNG width. Height follows the grid
and aspect choice. It is independent of `--font-size`; without `--width`, the font size
sets the raster scale. Oversized widths or derived heights are rejected rather than
silently written as the library's 1×1 fallback image.

Use `xcrun swift run aski render --help` for accepted character sets, colors, and bounds.
The CLI does not expose every converter policy or effect; use the Swift API for those.

## Let a photograph dissolve into type

White mask regions keep the character art. Black regions reveal the fallback, and
intermediate grayscale values create soft coverage.

```bash
xcrun swift run aski render photo.jpg \
  --render-png dissolve.png \
  --mask mask.png \
  --mask-fallback original \
  --mask-fallback-sizing stretch \
  --mask-ground "#080808"
```

The dark ground sits behind active glyphs so source-colored characters do not disappear
into the same photograph. The mask is stretched to the grid; prepare any desired
aspect-fit placement in the mask image itself.

The default fallback is `transparent`, and original-image fallback sizing defaults to
`stretch`. `--mask-fallback solid` requires `--mask-fallback-color`; solid/original
fallbacks and `--mask-ground` also require `--render-png`. `--mask-hard-edges` thresholds
at 0.5, and `--mask-invert` flips coverage afterward. A mask alone works for text,
where coverage below 0.5 becomes spaces. Full semantics: <doc:Masking>.

## Inspect and record

`inspect` uses the same source-thumbnail and conversion path as `render`, without
writing render artifacts. Its default is a human-readable report:

```bash
xcrun swift run aski inspect photo.jpg --columns 80
xcrun swift run aski inspect photo.jpg --format json --output inspection.json
```

To retain a render's settings and artifact metadata:

```bash
xcrun swift run aski render photo.jpg \
  --output photo.txt --render-png photo-ascii.png --width 1600 \
  --write-manifest render.json
```

Inspection JSON and render manifests are versioned and deterministic for the same
checkout, invocation, and input. Consumers must tolerate additive fields. A render
manifest is an **unsigned record**, not proof of image authenticity. It includes input
and output paths as supplied; review it before sharing it publicly.

Schemas and field contracts live in the repository's
[command-line architecture reference](https://github.com/BigCactusLabs/Aski/blob/main/docs/architecture.md#command-line-product).
`--write-manifest` belongs to `render`, not `inspect`.

## Reuse a built executable

Build once, then call the executable in SwiftPM's reported binary directory:

```bash
xcrun swift build -c release --product aski
"$(xcrun swift build -c release --show-bin-path)/aski" --help
```

This does not install a global command. No Homebrew formula or prebuilt download is
required by these instructions. `--version` reports a checkout Git SHA, or `unknown`
when unavailable; it is not a semantic-version release string.

## Explore the lab

```bash
xcrun swift run aski lab --help
xcrun swift run aski lab video --help
xcrun swift run aski lab color --help
```

The lab groups `color`, `motion`, `video`, `accessibility`, `decolor`, `hdr`, and `preset`
research harnesses. Their availability does not make every experiment a supported
product option. Prefer `aski lab …` to the historical `Aski*Lab` compatibility products.
The [documentation hub](https://github.com/BigCactusLabs/Aski/blob/main/docs/README.md)
lists canonical invocations and evidence.

Shell completions come from the same command tree:

```bash
xcrun swift run aski --generate-completion-script zsh > /tmp/aski-completions.zsh
```

Bash and Fish are also accepted. Install the generated script using your shell's
completion setup; generating it alone does not enable completion.

## When a render does not work

| Symptom | Check |
| --- | --- |
| Toolchain or Apple-framework build error | Confirm full Xcode is selected with `xcode-select -p`, then check `xcrun swift --version`; contributors can run `just doctor`. |
| Missing or unreadable image | Check the path, quoting, permissions, and whether ImageIO can decode the file. |
| Plain-text output has no color | Expected: use `--render-png` or the library's attributed-string renderer. |
| PNG size is surprising | Use `--width` with `--render-png`; columns control the grid, not pixels. |
| Mask or width option is refused | Check the flag dependencies above and the command's `--help`. |
| Same code, different raster snapshot | Compare OS, Xcode, fonts, and render path before treating it as matcher drift. |

The render command uses exit `64` for invalid usage, `66` for unavailable input, and
`70` for runtime failure. Build failures from `swift run` happen before the command and
need not use those codes. Keep standard error when reporting a problem, but remove
private paths and image content before posting it.
