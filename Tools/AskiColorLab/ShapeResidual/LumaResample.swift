// MARK: - Fixed-resolution luma resampler (PIXELS ONLY)

/// Resamples a row-major `[Float]` luma buffer from `(srcWidth, srcHeight)` to a
/// fixed `(dstWidth, dstHeight)`. The point (load-bearing for B5) is to run the
/// structure-focused oracles at a **column-independent** resolution: the existing
/// per-cell oracle degenerates to noisy 2×2 blocks at high column counts, whereas
/// resampling every source cell (and its glyph raster) to e.g. 16×16 first gives
/// the oracle a stable, comparable footprint across the whole fixture battery.
///
/// **Approach:** area-average (box) downsampling per axis when shrinking, and
/// bilinear interpolation when growing, decided independently for each axis. Both
/// are pure functions of the pixel buffer — no residual, no shape distance.
enum LumaResample {
    /// Resample `src` (length `srcWidth*srcHeight`) to `dstWidth*dstHeight`.
    /// Returns a buffer of length `dstWidth*dstHeight`. Degenerate inputs
    /// (mismatched length or non-positive dims) yield an all-zero destination.
    static func resample(
        _ src: [Float],
        srcWidth: Int,
        srcHeight: Int,
        dstWidth: Int,
        dstHeight: Int
    ) -> [Float] {
        guard srcWidth > 0, srcHeight > 0, dstWidth > 0, dstHeight > 0,
            src.count == srcWidth * srcHeight
        else { return [Float](repeating: 0, count: max(0, dstWidth * dstHeight)) }

        // Same size on both axes → identity copy (avoids any interpolation drift).
        if srcWidth == dstWidth && srcHeight == dstHeight { return src }

        // Resample horizontally (src → dstWidth), then vertically (→ dstHeight).
        // Separable, so each axis independently picks box-average (shrink) or
        // bilinear (grow). Intermediate buffer is dstWidth × srcHeight.
        let horizontal = resampleAxis(
            src, width: srcWidth, height: srcHeight,
            dstWidth: dstWidth, dstHeight: srcHeight, horizontal: true
        )
        return resampleAxis(
            horizontal, width: dstWidth, height: srcHeight,
            dstWidth: dstWidth, dstHeight: dstHeight, horizontal: false
        )
    }

    // MARK: - Internals

    /// Resamples a single axis. When `horizontal`, the column count changes from
    /// `width` to `dstWidth` (rows untouched, `height == dstHeight`); otherwise
    /// the row count changes from `height` to `dstHeight` (cols untouched).
    private static func resampleAxis(
        _ src: [Float],
        width: Int, height: Int,
        dstWidth: Int, dstHeight: Int,
        horizontal: Bool
    ) -> [Float] {
        let srcLen = horizontal ? width : height
        let dstLen = horizontal ? dstWidth : dstHeight
        var out = [Float](repeating: 0, count: dstWidth * dstHeight)

        @inline(__always) func sample(line: Int, pos: Int) -> Float {
            // `line` = the fixed index on the untouched axis; `pos` = index along
            // the resampled axis into `src`.
            if horizontal {
                return src[line * width + pos]
            } else {
                return src[pos * width + line]
            }
        }
        @inline(__always) func store(line: Int, pos: Int, _ v: Float) {
            if horizontal {
                out[line * dstWidth + pos] = v
            } else {
                out[pos * dstWidth + line] = v
            }
        }

        let lineCount = horizontal ? height : dstWidth

        if dstLen < srcLen {
            // Box (area-average) downsampling: dst sample `d` averages the source
            // samples whose [d, d+1)·scale interval it covers, weighted by overlap.
            let scale = Double(srcLen) / Double(dstLen)
            for d in 0..<dstLen {
                let start = Double(d) * scale
                let end = Double(d + 1) * scale
                var weights = [(idx: Int, w: Double)]()
                var s = Int(start)
                while Double(s) < end && s < srcLen {
                    let lo = max(start, Double(s))
                    let hi = min(end, Double(s + 1))
                    let w = hi - lo
                    if w > 0 { weights.append((s, w)) }
                    s += 1
                }
                let total = weights.reduce(0.0) { $0 + $1.w }
                for line in 0..<lineCount {
                    var acc = 0.0
                    for (idx, w) in weights { acc += Double(sample(line: line, pos: idx)) * w }
                    store(line: line, pos: d, Float(acc / total))
                }
            }
        } else {
            // Bilinear (1-D linear) upsampling. Map dst centers to src coordinate
            // space; `align_corners`-free center mapping keeps a constant buffer
            // exactly constant.
            let scale = Double(srcLen) / Double(dstLen)
            for d in 0..<dstLen {
                let srcPos = (Double(d) + 0.5) * scale - 0.5
                let lo = Int(srcPos.rounded(.down))
                let frac = srcPos - Double(lo)
                let i0 = min(max(lo, 0), srcLen - 1)
                let i1 = min(max(lo + 1, 0), srcLen - 1)
                for line in 0..<lineCount {
                    let a = Double(sample(line: line, pos: i0))
                    let b = Double(sample(line: line, pos: i1))
                    store(line: line, pos: d, Float(a + (b - a) * frac))
                }
            }
        }
        return out
    }
}
