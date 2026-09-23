import Foundation
import Testing
@testable import Aski

/// Bit-exact freeze of the animation surface for valid inputs (ASKI-18 AC#5,
/// ASKI-19 AC#4).
///
/// Unlike the rendering subsystem, the animation surface has NO snapshot or
/// golden fixtures, so a green behavioural suite is not evidence that output is
/// unchanged. These values were captured from the pre-change code at 6f21f81
/// and must stay bit-identical: `grid(at:)` over a participating multi-candidate
/// cycling grid, a wave and a pulse overlay, and a realistic 2 s / 12 fps
/// `materialize(frameRate:)`. No ε — `Float.bitPattern` equality, following
/// `DefaultPathExactGoldenTests`.
@Suite struct AnimationByteIdenticalGoldenTests {

    @Test func cyclingAndOngoingPatternGridsAreBitIdenticalToPreChangeCapture() {
        let animated = AnimationGoldenFixtures.cyclingGrid()

        for (index, time) in AnimationGoldenFixtures.sampleTimes.enumerated() {
            let frame = animated.grid(at: time)
            #expect(frame.rows == AnimationGoldenFixtures.rows)
            #expect(frame.columns == AnimationGoldenFixtures.columns)

            let flat = frame.cells.flatMap { $0 }.map { "\($0.character)|\($0.alpha.bitPattern)" }
            #expect(flat == Self.cyclingSamples[index], "cycling frame at t=\(time)")
        }
    }

    @Test func waveOverlayIsBitIdenticalToPreChangeCapture() {
        let out = AnimationGoldenFixtures.baseGrid()
            .applyingOngoingPattern(.wave(amplitude: 0.35, frequency: 1.5, direction: .diagonal), at: 0.37)

        #expect(out.cells.flatMap { $0 }.map(\.alpha.bitPattern) == Self.waveAlphas)
    }

    @Test func pulseOverlayIsBitIdenticalToPreChangeCapture() {
        let out = AnimationGoldenFixtures.baseGrid()
            .applyingOngoingPattern(.pulse(period: 0.75, depth: 0.8), at: 0.37)

        #expect(out.cells.flatMap { $0 }.map(\.alpha.bitPattern) == Self.pulseAlphas)
    }

    @Test func materializeCadenceAndFrameContentsAreBitIdenticalToPreChangeCapture() {
        let frames = AnimationGoldenFixtures.materializeGrid().materialize(frameRate: 12)

        #expect(frames.count == Self.materializeFrameCount)
        let encoded = frames.map { frame in
            frame.cells.flatMap { $0 }.map { "\($0.character)|\($0.alpha.bitPattern)" }.joined(separator: ",")
        }
        #expect(encoded == Self.materializeFrames)
    }

    // MARK: captured at 6f21f81, before the ASKI-6 / 18 / 19 changes

    static let cyclingSamples: [[String]] = [
        ["A|1045220557", "B|1050253722", "C|1053609165", "D|1056964608", "A|1058642330", "D|1060320051"],
        ["A|1044391053", "C|1049631594", "C|1052779661", "D|1055927728", "A|1058020202", "C|1059594235"],
        ["C|1035685593", "D|1041005347", "D|1044074201", "A|1047143055", "C|1049393955", "B|1050928382"],
        ["A|1039520442", "B|1043881484", "A|1047909050", "B|1050256308", "D|1052270092", "D|1054283874"],
        ["A|1042438292", "B|1047758047", "A|1050826900", "D|1053486777", "A|1056146655", "D|1057885569"],
        ["C|1045220557", "D|1050253722", "D|1053609165", "A|1056964608", "C|1058642330", "B|1060320051"],
    ]
    static let waveAlphas: [UInt32] = [1033649425, 1047432886, 1050783589, 1053215810, 1056081688, 1049637903]
    static let pulseAlphas: [UInt32] = [1025777823, 1031155951, 1034166431, 1036855495, 1039544559, 1041210507]
    static let materializeFrameCount = 25
    static let materializeFrames: [String] = [
        "A|1036831949,B|1041865114,C|1045220557,D|1048576000,A|1050253722,D|1051931443",
        "A|1043159109,B|1048707636,C|1051547717,D|1033717416,A|1035778864,D|1037840312",
        "A|1043159109,C|1048707636,C|1051547717,D|1033717416,A|1035778864,C|1037840312",
        "B|1036831949,C|1041865114,C|1045220557,D|1048576000,C|1050253722,C|1051931443",
        "B|1023124544,C|1027390256,D|1031513152,A|1054387798,C|1057096244,C|1058516284",
        "B|1023124544,C|1027390256,D|1031513152,A|1054387798,C|1057096244,C|1058516284",
        "C|1036831949,D|1041865114,D|1045220557,A|1048576000,C|1050253722,B|1051931443",
        "C|1043159109,D|1048707636,D|1051547717,A|1033717416,D|1035778864,B|1037840312",
        "C|1043159109,D|1048707636,D|1051547717,B|1033717416,D|1035778864,B|1037840312",
        "C|1036831949,D|1041865114,A|1045220557,B|1048576000,D|1050253722,B|1051931443",
        "A|1023124544,B|1027390256,A|1031513152,B|1054387798,D|1057096244,D|1058516284",
        "A|1023124544,B|1027390256,A|1031513152,B|1054387798,A|1057096244,D|1058516284",
        "A|1036831949,B|1041865114,A|1045220557,D|1048576000,A|1050253722,D|1051931443",
        "A|1043159109,B|1048707636,C|1051547717,D|1033717416,A|1035778864,C|1037840312",
        "B|1043159109,C|1048707636,C|1051547717,D|1033717416,A|1035778864,C|1037840312",
        "B|1036831949,C|1041865114,C|1045220557,D|1048576000,A|1050253722,C|1051931443",
        "B|1023124544,C|1027390256,C|1031513152,A|1054387798,C|1057096244,C|1058516284",
        "C|1023124544,C|1027390256,D|1031513152,A|1054387798,C|1057096244,B|1058516284",
        "C|1036831949,D|1041865114,D|1045220557,A|1048576000,C|1050253722,B|1051931443",
        "C|1043159109,D|1048707636,D|1051547717,A|1033717416,C|1035778864,B|1037840312",
        "C|1043159109,D|1048707636,D|1051547717,B|1033717416,D|1035778864,B|1037840312",
        "A|1036831949,D|1041865114,D|1045220557,B|1048576000,D|1050253722,D|1051931443",
        "A|1023124544,B|1027390256,A|1031513152,B|1054387798,D|1057096244,D|1058516284",
        "A|1023124544,B|1027390256,A|1031513152,B|1054387798,D|1057096244,D|1058516284",
        "B|1036831949,B|1041865114,A|1045220557,D|1048576000,A|1050253722,D|1051931443",
    ]
}
