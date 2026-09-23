import Foundation

public typealias CAM16Color = Cam16
public typealias HCTColor = Hct
public typealias CAM16ViewingConditions = ViewingConditions

public extension Cam16 {
    static func fromInt(_ argb: UInt32) -> Cam16 {
        fromInt(Int(argb))
    }
}

public extension Hct {
    static func fromInt(_ argb: UInt32) -> Hct {
        fromInt(Int(argb))
    }

    static func from(hue: Double, chroma: Double, tone: Double) -> Hct {
        from(hue, chroma, tone)
    }

    var argb: UInt32 {
        UInt32(toInt())
    }
}

enum CAM16HCTProvenance {
    static let materialColorUtilitiesSHA = "6fd88eb3e95ba1d457842e2a2bf847d06b3a018a"
}
