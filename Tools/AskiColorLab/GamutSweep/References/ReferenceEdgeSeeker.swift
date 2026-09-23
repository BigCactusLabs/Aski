import Aski
import simd

/// Pinned Swift reference port of Color.js apps `makeEdgeSeeker`.
///
/// Upstream:
/// - https://github.com/color-js/apps/blob/9d4b9883a2ad4a6f73875f666d2d531c6b4248f6/gamut-mapping/edge-seeker/makeEdgeSeeker.js
/// - https://github.com/color-js/apps/tree/9d4b9883a2ad4a6f73875f666d2d531c6b4248f6/gamut-mapping/edge-seeker/lut
///
/// This file exists only as a regression oracle for Aski's lab-local
/// `EdgeSeekerMapping`. It intentionally ports Color.js's cusp + curvature LUT
/// shape instead of reusing Aski's dense-L table.
public enum ReferenceEdgeSeeker {
    public static func map(
        oklab: SIMD3<Float>,
        target: GamutSweepTarget
    ) -> SIMD3<Float> {
        switch target {
        case .sRGB:
            return sRGB.map(oklab: oklab)
        case .displayP3:
            return displayP3.map(oklab: oklab)
        }
    }

    private static let sRGB = ReferenceEdgeSeekerInstance(target: .sRGB)
    private static let displayP3 = ReferenceEdgeSeekerInstance(target: .displayP3)
}

private struct ReferenceEdgeSeekerInstance: Sendable {
    private static let slices = 400

    let target: GamutSweepTarget
    let lut: [ReferenceLUTItem]

    init(target: GamutSweepTarget) {
        self.target = target
        self.lut = ReferenceEdgeSeekerLUT.make(target: target, steps: Self.slices)
    }

    func map(oklab: SIMD3<Float>) -> SIMD3<Float> {
        var lch = ReferenceOKLCh.fromOKLab(oklab)

        if lch.l <= 0 {
            return SIMD3<Float>(0, 0, 0)
        }
        if lch.l >= 1 {
            return SIMD3<Float>(1, 1, 1)
        }

        let maxChroma = maxChroma(lightness: lch.l, hue: lch.h)
        if lch.c > maxChroma {
            lch.c = maxChroma
        }

        return simd_clamp(
            target.oklabToLinearRGB(lch.oklab),
            SIMD3<Float>(0, 0, 0),
            SIMD3<Float>(1, 1, 1)
        )
    }

    private func maxChroma(lightness: Float, hue: Float) -> Float {
        if lightness <= 0 || lightness >= 1 {
            return 0
        }

        let normalizedHue = ReferenceEdgeSeekerMath.normalizeHue(hue)
        let lutItem = ReferenceEdgeSeekerLUT.getLutItem(hue: normalizedHue, lut: lut)

        if lightness <= lutItem.l {
            return (lightness / lutItem.l) * lutItem.c
        }

        let x = (1 - lightness) / (1 - lutItem.l)
        return lutItem.c
            * ReferenceEdgeSeekerMath.intersectionWithArc(
                x: x,
                curvature: lutItem.curvature
            )
    }
}

private enum ReferenceEdgeSeekerLUT {
    static func make(target: GamutSweepTarget, steps: Int) -> [ReferenceLUTItem] {
        let edgeColors = makeColorList(target: target, lightness: 0.5, steps: steps)
        let curveColors = makeColorList(target: target, lightness: 0.75, steps: steps)

        return edgeColors.map { peakColor in
            let curveColor = getColor(hue: peakColor.h, lut: curveColors)
            return ReferenceLUTItem(
                l: peakColor.l,
                c: peakColor.c,
                h: peakColor.h,
                curvature: ReferenceEdgeSeekerMath.calculateCurvature(
                    peakColor: peakColor,
                    curveColor: curveColor
                )
            )
        }
    }

    private static func makeColorList(
        target: GamutSweepTarget,
        lightness: Float,
        steps: Int
    ) -> [ReferenceOKLCh] {
        let hueRegions: [(Float, Float)] = [
            (0, 60),
            (60, 120),
            (120, 180),
            (180, 240),
            (240, 300),
            (300, 360),
        ]

        let colorList =
            hueRegions
            .map { hueStart, hueEnd in
                (0..<steps).map { index in
                    let hue = ReferenceEdgeSeekerMath.lerp(
                        start: hueStart,
                        end: hueEnd,
                        t: Float(index) / Float(steps - 1)
                    )
                    let rgb = ReferenceEdgeSeekerMath.hslToRGB(
                        hue: hue,
                        saturation: 1,
                        lightness: lightness
                    )
                    return rgbToOKLCh(rgb, target: target)
                }
            }
            .map(fixColorSection)
            .map { filterInterpolatableColors($0) }
            .reduce(into: [ReferenceOKLCh]()) { result, segment in
                result.append(contentsOf: segment.dropLast())
            }
            .sorted { $0.h < $1.h }

        return completeList(colorList)
    }

    private static func rgbToOKLCh(
        _ encodedRGB: SIMD3<Float>,
        target: GamutSweepTarget
    ) -> ReferenceOKLCh {
        let linearRGB = SIMD3<Float>(
            ColorConversion.sRGBDecode(encodedRGB.x),
            ColorConversion.sRGBDecode(encodedRGB.y),
            ColorConversion.sRGBDecode(encodedRGB.z)
        )
        return ReferenceOKLCh.fromOKLab(target.linearRGBToOKLab(linearRGB))
    }

    private static func fixColorSection(_ section: [ReferenceOKLCh]) -> [ReferenceOKLCh] {
        var result: [ReferenceOKLCh] = []
        var hasError = false

        for (index, color) in section.enumerated() {
            if index == 0 {
                result.append(color)
                continue
            }

            let willGoClockwise =
                index == section.count - 1
                || ReferenceEdgeSeekerMath.isClockwise(section[index].h, section[index + 1].h)

            if willGoClockwise {
                if hasError {
                    guard
                        let firstFaultyIndex = result.firstIndex(where: {
                            !ReferenceEdgeSeekerMath.isClockwise($0.h, color.h)
                        }), firstFaultyIndex > 0
                    else {
                        result.append(color)
                        hasError = false
                        continue
                    }

                    let replacementColor = ReferenceEdgeSeekerMath.lerpColorByHue(
                        start: result[firstFaultyIndex - 1],
                        end: result[firstFaultyIndex],
                        hue: color.h - 0.0001
                    )
                    result = Array(result[..<firstFaultyIndex])
                    result.append(replacementColor)
                    result.append(color)
                    hasError = false
                } else {
                    result.append(color)
                }
            } else if !hasError {
                hasError = true
                result.append(color)
            }
        }

        return result
    }

    private static func filterInterpolatableColors(
        _ colors: [ReferenceOKLCh],
        threshold: Float = 0.00001
    ) -> [ReferenceOKLCh] {
        let squaredThreshold = threshold * threshold
        var result = colors
        var changed = true

        while changed {
            let filtered = result.enumerated().filter { index, color in
                if index == 0 || index == result.count - 1 || index.isMultiple(of: 2) {
                    return true
                }
                let interpolated = ReferenceEdgeSeekerMath.lerpColorByHue(
                    start: result[index - 1],
                    end: result[index + 1],
                    hue: color.h
                )
                let squaredDistance =
                    (color.l - interpolated.l) * (color.l - interpolated.l)
                    + (color.c - interpolated.c) * (color.c - interpolated.c)
                return squaredDistance > squaredThreshold
            }.map(\.element)

            if filtered.count == result.count {
                changed = false
            } else {
                result = filtered
            }
        }

        return result
    }

    private static func completeList(_ list: [ReferenceOKLCh]) -> [ReferenceOKLCh] {
        guard let first = list.first, let last = list.last else { return list }
        let endColor = ReferenceEdgeSeekerMath.lerpColorByHue(
            start: last,
            end: ReferenceOKLCh(l: first.l, c: first.c, h: first.h + 360),
            hue: 360
        )
        return [ReferenceOKLCh(l: endColor.l, c: endColor.c, h: 0)]
            + list
            + [endColor]
    }

    private static func getColor(
        hue: Float,
        lut: [ReferenceOKLCh]
    ) -> ReferenceOKLCh {
        let closest = findClosest(hue: hue, lut: lut)
        return ReferenceEdgeSeekerMath.lerpColorByHue(
            start: closest.lower,
            end: closest.upper,
            hue: hue
        )
    }

    static func getLutItem(
        hue: Float,
        lut: [ReferenceLUTItem]
    ) -> ReferenceLUTItem {
        let closest = findClosest(hue: hue, lut: lut)
        return ReferenceEdgeSeekerMath.lerpLutItemsByHue(
            start: closest.lower,
            end: closest.upper,
            hue: hue
        )
    }

    private static func findClosest<T: ReferenceHueValue>(
        hue: Float,
        lut: [T]
    ) -> (lower: T, upper: T) {
        precondition(!lut.isEmpty)
        if hue <= lut[0].h {
            return (lut[0], lut[0])
        }
        if hue >= lut[lut.count - 1].h {
            return (lut[lut.count - 1], lut[lut.count - 1])
        }

        var start = 0
        var end = lut.count - 1

        while start <= end {
            let mid = (start + end) / 2
            if lut[mid].h == hue {
                return (lut[mid], lut[mid])
            } else if lut[mid].h < hue {
                start = mid + 1
            } else {
                end = mid - 1
            }
        }

        return (lut[max(0, end)], lut[min(lut.count - 1, start)])
    }
}

private enum ReferenceEdgeSeekerMath {
    static func lerp(start: Float, end: Float, t: Float) -> Float {
        if t <= 0 { return start }
        if t >= 1 { return end }
        return start * (1 - t) + end * t
    }

    static func lerpColorByHue(
        start: ReferenceOKLCh,
        end: ReferenceOKLCh,
        hue: Float
    ) -> ReferenceOKLCh {
        if hue == start.h { return start }
        if hue == end.h { return end }
        let t = (hue - start.h) / (end.h - start.h)
        return ReferenceOKLCh(
            l: lerp(start: start.l, end: end.l, t: t),
            c: lerp(start: start.c, end: end.c, t: t),
            h: hue
        )
    }

    static func lerpLutItemsByHue(
        start: ReferenceLUTItem,
        end: ReferenceLUTItem,
        hue: Float
    ) -> ReferenceLUTItem {
        if hue == start.h { return start }
        if hue == end.h { return end }
        let t = (hue - start.h) / (end.h - start.h)
        return ReferenceLUTItem(
            l: lerp(start: start.l, end: end.l, t: t),
            c: lerp(start: start.c, end: end.c, t: t),
            h: hue,
            curvature: lerp(start: start.curvature, end: end.curvature, t: t)
        )
    }

    static func hslToRGB(
        hue: Float,
        saturation: Float,
        lightness: Float
    ) -> SIMD3<Float> {
        let normalizedHue = normalizeHue(hue)
        let m1 = lightness + saturation * (lightness < 0.5 ? lightness : 1 - lightness)
        let hueSegment = (normalizedHue / 60).truncatingRemainder(dividingBy: 2)
        let m2 = m1 - (m1 - lightness) * 2 * abs(hueSegment - 1)
        let low = 2 * lightness - m1

        if normalizedHue < 60 {
            return SIMD3<Float>(m1, m2, low)
        }
        if normalizedHue < 120 {
            return SIMD3<Float>(m2, m1, low)
        }
        if normalizedHue < 180 {
            return SIMD3<Float>(low, m1, m2)
        }
        if normalizedHue < 240 {
            return SIMD3<Float>(low, m2, m1)
        }
        if normalizedHue < 300 {
            return SIMD3<Float>(m2, low, m1)
        }
        return SIMD3<Float>(m1, low, m2)
    }

    static func calculateCurvature(
        peakColor: ReferenceOKLCh,
        curveColor: ReferenceOKLCh
    ) -> Float {
        let x = (1 - curveColor.l) / (1 - peakColor.l)
        let y = curveColor.c / peakColor.c

        if x == y {
            return 0
        }

        let origin = ReferencePoint(x: 0, y: 0)
        let fixedPoint = ReferencePoint(x: 1, y: 1)
        let curvePoint = ReferencePoint(x: x, y: y)
        let bisector1 = perpendicularBisector(origin, curvePoint)
        let bisector2 = perpendicularBisector(origin, fixedPoint)
        let center = intersection(bisector1, bisector2)
        let radius = sqrt(center.x * center.x + center.y * center.y)
        let curvature = 1 / radius
        return center.x < center.y ? -curvature : curvature
    }

    static func intersectionWithArc(x: Float, curvature: Float) -> Float {
        if curvature == 0 {
            return x
        }

        let radius = abs(1 / curvature)
        let midpoint = ReferencePoint(x: 0.5, y: 0.5)
        let halfDiagonal = sqrt(midpoint.x * midpoint.x + midpoint.y * midpoint.y)
        let distanceToCenter = sqrt(radius * radius - halfDiagonal * halfDiagonal)
        let offset = distanceToCenter / sqrt(2)
        let centerX = (curvature > 0 ? offset : -offset) + midpoint.x
        let centerY = (curvature > 0 ? -offset : offset) + midpoint.y
        let underRoot = radius * radius - (x - centerX) * (x - centerX)

        if underRoot < 0 {
            return 0
        }

        let sqrtValue = sqrt(underRoot)
        let result1 = centerY + sqrtValue
        if result1 >= 0 && result1 <= 1 {
            return result1
        }
        return centerY - sqrtValue
    }

    static func isClockwise(_ h1: Float, _ h2: Float) -> Bool {
        let start = normalizeHue(h1)
        let end = normalizeHue(h2)
        var diff = end - start
        if diff < 0 {
            diff += 360
        }
        return diff >= 0 && diff <= 180
    }

    static func normalizeHue(_ hue: Float) -> Float {
        let remainder = hue.truncatingRemainder(dividingBy: 360)
        return remainder < 0 ? remainder + 360 : remainder
    }

    private static func perpendicularBisector(
        _ p1: ReferencePoint,
        _ p2: ReferencePoint
    ) -> ReferenceLine {
        ReferenceLine(
            slope: -1 / ((p2.y - p1.y) / (p2.x - p1.x)),
            point: ReferencePoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
        )
    }

    private static func intersection(
        _ line1: ReferenceLine,
        _ line2: ReferenceLine
    ) -> ReferencePoint {
        let x =
            (line1.slope * line1.point.x
                - line2.slope * line2.point.x
                + line2.point.y
                - line1.point.y)
            / (line1.slope - line2.slope)
        let y = line1.slope * (x - line1.point.x) + line1.point.y
        return ReferencePoint(x: x, y: y)
    }
}

private protocol ReferenceHueValue {
    var h: Float { get }
}

private struct ReferenceOKLCh: ReferenceHueValue, Sendable {
    var l: Float
    var c: Float
    var h: Float

    var oklab: SIMD3<Float> {
        let hueRadians = h * .pi / 180
        return SIMD3<Float>(l, c * cos(hueRadians), c * sin(hueRadians))
    }

    static func fromOKLab(_ oklab: SIMD3<Float>) -> ReferenceOKLCh {
        let chroma = sqrt(oklab.y * oklab.y + oklab.z * oklab.z)
        let hue = ReferenceEdgeSeekerMath.normalizeHue(atan2(oklab.z, oklab.y) * 180 / .pi)
        return ReferenceOKLCh(l: oklab.x, c: chroma, h: hue)
    }
}

private struct ReferenceLUTItem: ReferenceHueValue, Sendable {
    var l: Float
    var c: Float
    var h: Float
    var curvature: Float
}

private struct ReferencePoint: Sendable {
    var x: Float
    var y: Float
}

private struct ReferenceLine: Sendable {
    var slope: Float
    var point: ReferencePoint
}
