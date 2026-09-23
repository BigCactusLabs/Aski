import Aski
import simd

/// Pinned Swift reference port of Color.js apps `methods.raytrace.trace`.
///
/// Upstream:
/// https://github.com/color-js/apps/blob/9d4b9883a2ad4a6f73875f666d2d531c6b4248f6/gamut-mapping/methods.js
///
/// This file exists only as a regression oracle for Aski's production Ray Trace
/// mapper. Keep it structurally independent from `GamutMapping` helpers so the
/// cross-check tests can catch accidental production drift.
public enum ReferenceRayTrace {
    public static func map(
        oklab: SIMD3<Float>,
        target: GamutSweepTarget
    ) -> SIMD3<Float> {
        let initialLinearRGB = target.oklabToLinearRGB(oklab)
        if isStrictlyInUnitCube(initialLinearRGB) {
            return initialLinearRGB
        }
        if oklab.x >= 1 { return SIMD3<Float>(1, 1, 1) }
        if oklab.x <= 0 { return SIMD3<Float>(0, 0, 0) }

        return trace(oklab: oklab, target: target)
    }

    private static func trace(
        oklab: SIMD3<Float>,
        target: GamutSweepTarget
    ) -> SIMD3<Float> {
        let originalLCH = okLCh(from: oklab)
        let lightness = originalLCH.x
        let hue = originalLCH.z

        var anchor = linearRGB(fromOKLCh: SIMD3<Float>(lightness, 0, hue), target: target)
        var mapColor = linearRGB(fromOKLCh: originalLCH, target: target)
        var last = mapColor

        let low: Float = 1e-6
        let high: Float = 1 - low

        for iteration in 0..<4 {
            if iteration > 0 {
                var correctedLCH = okLCh(fromLinearRGB: mapColor, target: target)
                correctedLCH.x = lightness
                correctedLCH.z = hue
                mapColor = linearRGB(fromOKLCh: correctedLCH, target: target)
            }

            guard let intersection = rayTraceBoxIntersection(from: anchor, through: mapColor) else {
                mapColor = last
                break
            }

            if iteration > 0
                && mapColor.x > low && mapColor.x < high
                && mapColor.y > low && mapColor.y < high
                && mapColor.z > low && mapColor.z < high
            {
                anchor = mapColor
            }

            mapColor = intersection
            last = intersection
        }

        return simd_clamp(mapColor, SIMD3<Float>(0, 0, 0), SIMD3<Float>(1, 1, 1))
    }

    private static func rayTraceBoxIntersection(
        from start: SIMD3<Float>,
        through end: SIMD3<Float>
    ) -> SIMD3<Float>? {
        let boundsMin = SIMD3<Float>(0, 0, 0)
        let boundsMax = SIMD3<Float>(1, 1, 1)
        var tFar = Float.infinity
        var tNear = -Float.infinity
        let direction = end - start

        for axis in 0..<3 {
            let a = component(start, axis)
            let bMin = component(boundsMin, axis)
            let bMax = component(boundsMax, axis)
            let d = component(direction, axis)

            if abs(d) > 1e-15 {
                let inverseD = 1 / d
                let t1 = (bMin - a) * inverseD
                let t2 = (bMax - a) * inverseD
                tNear = max(min(t1, t2), tNear)
                tFar = min(max(t1, t2), tFar)
            } else if a < bMin || a > bMax {
                return nil
            }
        }

        if tNear > tFar || tFar < 0 {
            return nil
        }
        if tNear < 0 {
            tNear = tFar
        }
        if !tNear.isFinite {
            return nil
        }

        return start + direction * tNear
    }

    private static func linearRGB(
        fromOKLCh lch: SIMD3<Float>,
        target: GamutSweepTarget
    ) -> SIMD3<Float> {
        target.oklabToLinearRGB(oklab(fromOKLCh: lch))
    }

    private static func okLCh(
        fromLinearRGB rgb: SIMD3<Float>,
        target: GamutSweepTarget
    ) -> SIMD3<Float> {
        okLCh(from: target.linearRGBToOKLab(rgb))
    }

    private static func oklab(fromOKLCh lch: SIMD3<Float>) -> SIMD3<Float> {
        let hueRadians = lch.z * .pi / 180
        return SIMD3<Float>(
            lch.x,
            lch.y * cos(hueRadians),
            lch.y * sin(hueRadians)
        )
    }

    private static func okLCh(from oklab: SIMD3<Float>) -> SIMD3<Float> {
        let chroma = sqrt(oklab.y * oklab.y + oklab.z * oklab.z)
        let hue = constrainedHueDegrees(atan2(oklab.z, oklab.y) * 180 / .pi)
        return SIMD3<Float>(oklab.x, chroma, hue)
    }

    private static func constrainedHueDegrees(_ hue: Float) -> Float {
        let remainder = hue.truncatingRemainder(dividingBy: 360)
        return remainder < 0 ? remainder + 360 : remainder
    }

    private static func isStrictlyInUnitCube(_ rgb: SIMD3<Float>) -> Bool {
        rgb.x >= 0 && rgb.x <= 1
            && rgb.y >= 0 && rgb.y <= 1
            && rgb.z >= 0 && rgb.z <= 1
    }

    private static func component(_ value: SIMD3<Float>, _ axis: Int) -> Float {
        switch axis {
        case 0: value.x
        case 1: value.y
        default: value.z
        }
    }
}
