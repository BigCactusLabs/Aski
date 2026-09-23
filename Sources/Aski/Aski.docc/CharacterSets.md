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
    palette: BuiltInPalette.fullColor
)
```

`ASCIIConverter` takes one validated snapshot of a custom conformance's four
per-glyph arrays during initialization and whenever its public `characterSet`
property is assigned. If a reference-type conformance changes its arrays after
initialization, assign it to `characterSet` again to refresh that snapshot.

## Blank glyphs

Every built-in set except ``StandardCharacterSet/braille`` includes a literal
" " as its first character. Braille uses U+2800 (zero dots) as its native
blank. Matching falls back to the lowest-brightness glyph when a custom set has
no literal space.
