# Character Sets

Built-in and custom character sets.

## Built-ins

Ten built-in sets, accessed as static properties on ``StandardCharacterSet``:

- `standard` — full ASCII printable range
- `minimal` — 10-character density ramp
- `blocks` — Unicode block elements
- `dots` — round dot density ramp
- `lines` — box-drawing line art
- `diagonal` — slashes and X
- `cross` — plus, X, and crosses
- `diamond` — geometric diamonds
- `mixed` — sampled blend across other style families
- `braille` — full U+2800–U+28FF range, programmatically rasterized

## Extending Aski with custom character sets

Implement ``ASCIICharacterSet`` directly, or use ``RasterizedCharacterSet``
to compute shape vectors at runtime from a custom font + character list:

```swift
import CoreText

let custom = RasterizedCharacterSet(
    characters: Array("☆★✦✧✨"),
    font: CTFontCreateWithName("Helvetica" as CFString, 32, nil)
)
let converter = ASCIIConverter(
    characterSet: custom,
    palette: BuiltInPalette.fullColor,
    algorithm: .dotMatrix
)
```

The example uses ``ASCIIAlgorithm/dotMatrix`` for the reason in the next
section.

`ASCIIConverter` takes one validated snapshot of a custom conformance's four
per-glyph arrays during initialization and whenever its public `characterSet`
property is assigned. If a reference-type conformance changes its arrays after
initialization, assign it to `characterSet` again to refresh that snapshot.

## Custom sets and logPolar

``ASCIIAlgorithm/logPolar`` ranks the brightness-nearest candidates by shape
distance, and at the default `oversample` a cell's shape query reaches only
2–3 of the 60 descriptor bins. A glyph with no ink in those bins shares
nothing with any query, so the distance ranks it by the size of its own
descriptor, and a space, whose descriptor is empty, beats it whenever both
are among the candidates. A small custom set (12 glyphs or fewer at the
default `density`, so every glyph is a candidate) in which no glyph other than
the space has ink in those bins therefore renders every cell as a space, and a
set in which only one or two glyphs do can repeat those glyphs across the
whole image.

If a custom set renders an all-blank or single-glyph grid under `logPolar`,
convert it with ``ASCIIAlgorithm/dotMatrix``, which picks on brightness. Five
built-in sets have the same limitation; see <doc:Algorithms> for the
recommended pairings.

## Blank glyphs

Every built-in set except ``StandardCharacterSet/braille`` includes a literal
" " as its first character. Braille uses U+2800 (zero dots) as its native
blank. Matching falls back to the lowest-brightness glyph when a custom set has
no literal space.
