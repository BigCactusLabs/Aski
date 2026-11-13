import simd

/// Wu's color quantization in OKLAB.
///
/// **Pre-processing per spec §4:**
/// - Skip pixels with `alpha == 0` entirely (no color signal).
/// - Unpremultiply RGB before sRGB→linear→OKLAB conversion.
/// - Weight each surviving pixel's contribution to histograms by `alpha` so
///   semi-transparent edges don't skew cluster centers.
///
/// **Histogram & moment tables:**
/// - 32³ logical bins; axis ranges `L∈[0,1]`, `a∈[-0.5,0.5]`, `b∈[-0.5,0.5]`.
/// - Out-of-range pixels clamp to the nearest in-range bin index (no silent drop).
/// - 33³ padded summed-area tables (index 0 along each axis is a zero-padded
///   plane) so box-sum queries are an unconditional 8-corner read.
///
/// **Subdivision:**
/// - Pick the splittable box with highest α-weighted variance; cut on the axis
///   and position that maximize variance reduction. Repeat until either
///   `maxColors` boxes exist or no box is splittable. Splittable = (weightSum>0)
///   ∧ (not terminal) ∧ (≥1 axis with `max-bin > min-bin`).
///
/// **Output:** α-weighted centroids `(sumL, suma, sumb) / weightSum` per box.
/// Boxes with `weightSum == 0` are dropped. Output count is at most
/// `clamp(maxColors, 2, 256)` — the internal API mirrors the public
/// `TilePalette.adaptive` clamp so direct test callers get the same
/// behavior as production. Pass-through callers (e.g. `TilePalette.resolved`)
/// are already clamped at the public layer.
internal struct WuQuantizer {

    static let bins: Int = 32  // logical histogram bins per axis
    static let padded: Int = 33  // 33³ padded SAT (index 0 = zero plane)

    private let weightSum: [Float]
    private let sumL: [Float]
    private let sumA: [Float]
    private let sumB: [Float]
    private let sumLL: [Float]
    private let sumAA: [Float]
    private let sumBB: [Float]

    /// Build moment tables from premultiplied RGBA pixels. `colorSpace`
    /// determines which OKLAB conversion path is used.
    init(pixels: [UInt8], width: Int, height: Int, colorSpace: RenderColorSpace) {
        var weightSum = [Float](repeating: 0, count: Self.padded * Self.padded * Self.padded)
        var sumL = weightSum
        var sumA = weightSum
        var sumB = weightSum
        var sumLL = weightSum
        var sumAA = weightSum
        var sumBB = weightSum

        let pixelCount = width * height
        for i in 0..<pixelCount {
            let offset = i * 4
            let alpha = Float(pixels[offset + 3]) / 255
            if alpha == 0 { continue }
            let r = Float(pixels[offset]) / 255
            let g = Float(pixels[offset + 1]) / 255
            let b = Float(pixels[offset + 2]) / 255
            let rUn = min(r / alpha, 1)
            let gUn = min(g / alpha, 1)
            let bUn = min(b / alpha, 1)
            let linear = SIMD3<Float>(
                ColorConversion.sRGBDecode(rUn),
                ColorConversion.sRGBDecode(gUn),
                ColorConversion.sRGBDecode(bUn)
            )
            let oklab: SIMD3<Float>
            switch colorSpace {
            case .sRGB: oklab = ColorConversion.linearSRGBToOKLAB(linear)
            case .displayP3: oklab = ColorConversion.linearP3ToOKLAB(linear)
            }

            // Bin indices in [1...32] (index 0 reserved for the zero-padded plane).
            let li = Self.binIndex(oklab.x, axisLo: 0, axisHi: 1)
            let ai = Self.binIndex(oklab.y, axisLo: -0.5, axisHi: 0.5)
            let bi = Self.binIndex(oklab.z, axisLo: -0.5, axisHi: 0.5)
            let idx = (li * Self.padded + ai) * Self.padded + bi

            weightSum[idx] += alpha
            sumL[idx] += alpha * oklab.x
            sumA[idx] += alpha * oklab.y
            sumB[idx] += alpha * oklab.z
            sumLL[idx] += alpha * oklab.x * oklab.x
            sumAA[idx] += alpha * oklab.y * oklab.y
            sumBB[idx] += alpha * oklab.z * oklab.z
        }

        Self.integrate(&weightSum)
        Self.integrate(&sumL)
        Self.integrate(&sumA)
        Self.integrate(&sumB)
        Self.integrate(&sumLL)
        Self.integrate(&sumAA)
        Self.integrate(&sumBB)

        self.weightSum = weightSum
        self.sumL = sumL
        self.sumA = sumA
        self.sumB = sumB
        self.sumLL = sumLL
        self.sumAA = sumAA
        self.sumBB = sumBB
    }

    /// Run Wu subdivision and return α-weighted centroids in OKLAB.
    ///
    /// `maxColors` is clamped to `2...256` internally — passing `1` returns up
    /// to 2 colors, not 1. This mirrors `TilePalette.adaptive(maxColors:)`'s
    /// clamp so test callers and production callers see identical behavior.
    /// Output count is at most `clamp(maxColors, 2, 256)`; fewer if the source
    /// has fewer distinct colors than the target.
    func palette(maxColors: Int) -> [SIMD3<Float>] {
        let target = max(2, min(256, maxColors))
        // The cache only recoups its bookkeeping cost once a palette is large
        // enough to drive enough subdivisions. The default 16-colour path
        // keeps its established direct scoring loop.
        let usesSplitCache = target >= 64

        var boxes: [Box] = [
            Box(
                lLo: 0, lHi: Self.bins,
                aLo: 0, aHi: Self.bins,
                bLo: 0, bHi: Self.bins,
                terminal: false)
        ]

        while boxes.count < target {
            // Find best splittable box (one with the highest reducible variance).
            var bestIdx = -1
            var bestReduction: Float = 0
            var selectedCut: Cut? = nil
            for i in boxes.indices where !boxes[i].terminal {
                let cut: Cut?
                if usesSplitCache {
                    if !boxes[i].hasCachedCut {
                        cacheBestCut(in: &boxes[i])
                    }
                    cut = boxes[i].cachedCut
                } else {
                    cut = bestCut(for: boxes[i])
                }
                guard let cut else {
                    boxes[i].terminal = true
                    continue
                }
                if cut.variance > bestReduction {
                    bestReduction = cut.variance
                    bestIdx = i
                    selectedCut = cut
                }
            }
            guard bestIdx >= 0, let cut = selectedCut else { break }

            let original = boxes[bestIdx]
            var (left, right) = split(box: original, cut: cut)
            if usesSplitCache {
                cacheBestCut(in: &left)
                cacheBestCut(in: &right)
            }
            boxes[bestIdx] = left
            boxes.append(right)
        }

        var palette: [SIMD3<Float>] = []
        palette.reserveCapacity(boxes.count)
        for box in boxes {
            let w = volume(weightSum, box: box)
            guard w > 0 else { continue }
            let l = volume(sumL, box: box) / w
            let a = volume(sumA, box: box) / w
            let b = volume(sumB, box: box) / w
            palette.append(SIMD3<Float>(l, a, b))
        }
        return palette
    }

    // MARK: - Internals

    private struct Box {
        var lLo: Int; var lHi: Int
        var aLo: Int; var aHi: Int
        var bLo: Int; var bHi: Int
        var terminal: Bool
        var cachedCut: Cut? = nil
        var hasCachedCut: Bool = false
    }

    private struct Cut {
        let axis: Int  // 0 = L, 1 = a, 2 = b
        let position: Int
        let variance: Float
    }

    private func cacheBestCut(in box: inout Box) {
        box.cachedCut = bestCut(for: box)
        box.hasCachedCut = true
        if box.cachedCut == nil {
            box.terminal = true
        }
    }

    /// Inclusive-exclusive 8-corner volume read for any moment table.
    /// `[lLo+1...lHi] × [aLo+1...aHi] × [bLo+1...bHi]` in padded coordinates,
    /// which corresponds to logical bin range `[lLo+1, lHi]` etc.
    private func volume(_ table: [Float], box: Box) -> Float {
        let p = Self.padded
        // Negative-corner trick: subtract three faces, add three edges, subtract one corner.
        let v111 = table[(box.lHi * p + box.aHi) * p + box.bHi]
        let v110 = table[(box.lHi * p + box.aHi) * p + box.bLo]
        let v101 = table[(box.lHi * p + box.aLo) * p + box.bHi]
        let v100 = table[(box.lHi * p + box.aLo) * p + box.bLo]
        let v011 = table[(box.lLo * p + box.aHi) * p + box.bHi]
        let v010 = table[(box.lLo * p + box.aHi) * p + box.bLo]
        let v001 = table[(box.lLo * p + box.aLo) * p + box.bHi]
        let v000 = table[(box.lLo * p + box.aLo) * p + box.bLo]
        return v111 - v110 - v101 + v100 - v011 + v010 + v001 - v000
    }

    /// α-weighted variance of `box` (sum of squared deviations × α).
    private func variance(of box: Box) -> Float {
        let w = volume(weightSum, box: box)
        guard w > 0 else { return 0 }
        let l = volume(sumL, box: box)
        let a = volume(sumA, box: box)
        let b = volume(sumB, box: box)
        let ll = volume(sumLL, box: box)
        let aa = volume(sumAA, box: box)
        let bb = volume(sumBB, box: box)
        return (ll + aa + bb) - (l * l + a * a + b * b) / w
    }

    /// Find the cut that maximizes variance reduction across all axes.
    /// Returns `nil` if no axis has `max-bin > min-bin` (box is single-bin).
    private func bestCut(for box: Box) -> Cut? {
        let parentVariance = variance(of: box)
        var best: Cut? = nil

        if box.lHi - box.lLo > 1 {
            for cut in (box.lLo + 1)..<box.lHi {
                var left = box; left.lHi = cut
                var right = box; right.lLo = cut
                let reduction = parentVariance - variance(of: left) - variance(of: right)
                if reduction > (best?.variance ?? 0) {
                    best = Cut(axis: 0, position: cut, variance: reduction)
                }
            }
        }
        if box.aHi - box.aLo > 1 {
            for cut in (box.aLo + 1)..<box.aHi {
                var left = box; left.aHi = cut
                var right = box; right.aLo = cut
                let reduction = parentVariance - variance(of: left) - variance(of: right)
                if reduction > (best?.variance ?? 0) {
                    best = Cut(axis: 1, position: cut, variance: reduction)
                }
            }
        }
        if box.bHi - box.bLo > 1 {
            for cut in (box.bLo + 1)..<box.bHi {
                var left = box; left.bHi = cut
                var right = box; right.bLo = cut
                let reduction = parentVariance - variance(of: left) - variance(of: right)
                if reduction > (best?.variance ?? 0) {
                    best = Cut(axis: 2, position: cut, variance: reduction)
                }
            }
        }
        return best
    }

    private func split(box: Box, cut: Cut) -> (Box, Box) {
        var left = box, right = box
        switch cut.axis {
        case 0: left.lHi = cut.position; right.lLo = cut.position
        case 1: left.aHi = cut.position; right.aLo = cut.position
        case 2: left.bHi = cut.position; right.bLo = cut.position
        default: break
        }
        return (left, right)
    }

    /// Bin index in `[1, bins]` for `value` along an axis from `axisLo` to `axisHi`.
    /// Index 0 is reserved for the zero-padded plane and is never assigned data.
    static func binIndex(_ value: Float, axisLo: Float, axisHi: Float) -> Int {
        let normalized = (value - axisLo) / (axisHi - axisLo)
        // Production values come from finite RGBA8-to-OKLAB conversion over
        // these fixed, non-zero color axes. That named color-lattice bound keeps
        // the scaled bin coordinate representable before conversion.
        let raw = Int(normalized * Float(bins))
        return max(1, min(bins, raw + 1))
    }

    /// In-place 3D summed-area-table conversion of a `padded³` flat array.
    /// After integration, `table[(li*p + ai)*p + bi]` is the inclusive sum of all
    /// raw values at coordinates ≤ (li, ai, bi).
    private static func integrate(_ table: inout [Float]) {
        let p = padded
        // L-axis prefix
        for ai in 0..<p {
            for bi in 0..<p {
                for li in 1..<p {
                    table[(li * p + ai) * p + bi] += table[((li - 1) * p + ai) * p + bi]
                }
            }
        }
        // a-axis prefix
        for li in 0..<p {
            for bi in 0..<p {
                for ai in 1..<p {
                    table[(li * p + ai) * p + bi] += table[(li * p + (ai - 1)) * p + bi]
                }
            }
        }
        // b-axis prefix
        for li in 0..<p {
            for ai in 0..<p {
                for bi in 1..<p {
                    table[(li * p + ai) * p + bi] += table[(li * p + ai) * p + (bi - 1)]
                }
            }
        }
    }
}
