import Foundation
import Testing
@testable import Aski

@Suite struct AskiResampleReportingTests {
    @Test func boundsConstantsMatchSpec() {
        #expect(maxTargetFPS == 240)
        #expect(maxResampledFrames == 36_000)
    }

    @Test func statsCommitIsReadableAfterCommit() async {
        let stats = ResampleStats()
        #expect(await stats.sourceFrameCount == 0)
        await stats.commit(source: 9, output: 4, dropped: 5, duplicated: 0)
        #expect(await stats.sourceFrameCount == 9)
        #expect(await stats.outputFrameCount == 4)
        #expect(await stats.droppedCount == 5)
        #expect(await stats.duplicatedCount == 0)
    }

    @Test func errorDescriptionsAreInformative() {
        #expect(ResampleError.invalidTargetFPS(0).description.contains("0"))
        #expect(ResampleError.invalidTargetFPS(0).description.contains("\(maxTargetFPS)"))
        #expect(!ResampleError.invalidSourceDuration(.nan).description.isEmpty)
        let exceeded = ResampleError.resampledFrameCountExceeded(projected: 99_999, limit: maxResampledFrames)
        #expect(exceeded.description.contains("99999"))
    }

    @Test func reportHoldsItsFields() {
        let report = ResampleReport(
            requestedFPS: 24, achievedFPS: 25.0,
            sourceFrameCount: 30, outputFrameCount: 25, droppedCount: 5, duplicatedCount: 0
        )
        #expect(report.requestedFPS == 24)
        #expect(report.achievedFPS == 25.0)
        #expect(report.droppedCount == 5)
    }
}

// MARK: - Pure selection core

/// Synthetic frame for the pure core suite. `id` tracks which source frame
/// survives; `start` is its absolute start seconds; `slot` is the output slot the
/// stamper writes, so tests assert the exact slot→token mapping.
private struct Tok: Sendable {
    let id: Int
    let start: Double
    var slot: Int = -1
}

/// Drives `ResampleSession<Tok>` end to end over an eager in-memory stream and
/// returns the emitted tokens plus the committed stats.
private func runCore(
    starts: [Double],
    targetFPS: Int,
    sourceDuration: Double
) async throws -> (out: [Tok], stats: ResampleStats) {
    let source = AsyncThrowingStream<Tok, Error> { continuation in
        for (index, start) in starts.enumerated() {
            continuation.yield(Tok(id: index, start: start))
        }
        continuation.finish()
    }
    let endSlot = try resamplePreflight(targetFPS: targetFPS, sourceDuration: sourceDuration)
    let stats = ResampleStats()
    let session = ResampleSession<Tok>(
        source: source,
        timing: .absolute { $0.start },
        retime: { tok, k in Tok(id: tok.id, start: tok.start, slot: k) },
        targetFPS: targetFPS,
        endSlot: endSlot,
        stats: stats
    )
    var out: [Tok] = []
    while let frame = try await session.next() { out.append(frame) }
    return (out, stats)
}

@Suite struct AskiResampleCoreTests {
    @Test func downsampleKeepsLastOnCollision() async throws {
        // 30 fps source -> 12 fps. start_i = i/30. slot_i = round(i*0.4).
        let starts = (0..<6).map { Double($0) / 30.0 }  // slots: 0,0,1,1,2,2
        let (out, stats) = try await runCore(starts: starts, targetFPS: 12, sourceDuration: 6.0 / 30.0)
        #expect(out.map(\.slot) == [0, 1, 2])
        #expect(out.map(\.id) == [1, 3, 5])  // last of each collision group kept
        #expect(await stats.droppedCount == 3)  // ids 0,2,4 dropped
        #expect(await stats.duplicatedCount == 0)
        #expect(await stats.outputFrameCount == 3)
    }

    @Test func upsampleRepeatsPreviousOnGap() async throws {
        // 2 frames at 0.0 and 1.0; t=4 -> slots 0 and 4; endSlot = round(2.0*4)=8.
        let (out, stats) = try await runCore(starts: [0.0, 1.0], targetFPS: 4, sourceDuration: 2.0)
        #expect(out.map(\.slot) == [0, 1, 2, 3, 4, 5, 6, 7])
        #expect(out.map(\.id) == [0, 0, 0, 0, 1, 1, 1, 1])
        #expect(await stats.duplicatedCount == 6)
        #expect(await stats.droppedCount == 0)
    }

    @Test func equalRateSnapsOneToOne() async throws {
        let starts = (0..<4).map { Double($0) / 30.0 }
        let (out, stats) = try await runCore(starts: starts, targetFPS: 30, sourceDuration: 4.0 / 30.0)
        #expect(out.map(\.id) == [0, 1, 2, 3])
        #expect(out.map(\.slot) == [0, 1, 2, 3])
        #expect(await stats.droppedCount == 0)
        #expect(await stats.duplicatedCount == 0)
    }

    @Test func roundNearUsesAwayFromZeroMidpoint() async throws {
        // t=2: start 0.25 -> 0.5 -> rounds to 1 (away from 0), NOT 0. endSlot=round(1.0*2)=2.
        let (out, _) = try await runCore(starts: [0.0, 0.25, 0.75], targetFPS: 2, sourceDuration: 1.0)
        #expect(out.map(\.id) == [0, 1])  // slot0<-f0, slot1<-f1 (0.25 lands on slot 1)
        #expect(out.map(\.slot) == [0, 1])
    }

    @Test func terminationPreservesFinalFrameDuration() async throws {
        // 2-frame 10 fps "GIF" (starts 0.0, 0.1; sourceDuration 0.2) -> 30 fps.
        // endSlot = ceil(0.2*30) = 6; last frame duplicates to fill its display span.
        let (out, stats) = try await runCore(starts: [0.0, 0.1], targetFPS: 30, sourceDuration: 0.2)
        #expect(out.count == 6)
        #expect(out.map(\.id) == [0, 0, 0, 1, 1, 1])
        #expect(await stats.duplicatedCount == 4)
    }

    @Test func singleFrameSourceEmitsOneFrameViaFloor() async throws {
        // sourceDuration 0 exercises the max(1, ...) endSlot floor: never 0 frames.
        let (out, stats) = try await runCore(starts: [0.0], targetFPS: 30, sourceDuration: 0.0)
        #expect(out.count == 1)
        #expect(out[0].id == 0)
        #expect(await stats.outputFrameCount == 1)
        #expect(await stats.duplicatedCount == 0)
    }

    @Test func preflightRejectsOutOfRangeTargetFPS() {
        #expect(throws: ResampleError.self) { _ = try resamplePreflight(targetFPS: 0, sourceDuration: 1.0) }
        #expect(throws: ResampleError.self) { _ = try resamplePreflight(targetFPS: -5, sourceDuration: 1.0) }
        #expect(throws: ResampleError.self) { _ = try resamplePreflight(targetFPS: maxTargetFPS + 1, sourceDuration: 1.0) }
    }

    @Test func preflightRejectsExplodingFrameCountBeforeAllocation() {
        // tiny rate is fine; a long duration * high rate overflows the cap.
        #expect(throws: ResampleError.self) {
            _ = try resamplePreflight(targetFPS: 240, sourceDuration: 1_000_000.0)
        }
        #expect(throws: Never.self) {
            _ = try resamplePreflight(targetFPS: 60, sourceDuration: 1.0)
        }
    }

    @Test func preflightRejectsNonFiniteOrNegativeDurationInsteadOfTrapping() {
        // A NaN/∞/negative duration must throw, NOT trap the Int(_:) conversion.
        #expect(throws: ResampleError.self) {
            _ = try resamplePreflight(targetFPS: 30, sourceDuration: .nan)
        }
        #expect(throws: ResampleError.self) {
            _ = try resamplePreflight(targetFPS: 30, sourceDuration: .infinity)
        }
        #expect(throws: ResampleError.self) {
            _ = try resamplePreflight(targetFPS: 30, sourceDuration: -1.0)
        }
    }

    @Test func preflightRejectsHugeFiniteDurationWithoutTrapping() {
        // A huge FINITE duration makes sourceDuration * targetFPS exceed Int.max;
        // the Double bound check must throw resampledFrameCountExceeded rather than
        // trap in Int(_:). (.greatestFiniteMagnitude * t overflows to ∞; 1e300 stays
        // finite-but-enormous — both must throw, neither may trap.)
        #expect(throws: ResampleError.self) {
            _ = try resamplePreflight(targetFPS: 60, sourceDuration: .greatestFiniteMagnitude)
        }
        #expect(throws: ResampleError.self) {
            _ = try resamplePreflight(targetFPS: 240, sourceDuration: 1e300)
        }
    }

    @Test func endSlotUsesCeilNotRoundForFractionalProducts() throws {
        // 0.2s clip at 12 fps -> 2.4 -> 3 slots (ceil), not 2 (round) — guards
        // against truncating the clip's tail.
        #expect(try resamplePreflight(targetFPS: 12, sourceDuration: 0.2) == 3)
        // Integer products are unaffected (ceil == round).
        #expect(try resamplePreflight(targetFPS: 30, sourceDuration: 0.2) == 6)
        #expect(try resamplePreflight(targetFPS: 30, sourceDuration: 0.1) == 3)
    }

    @Test func intervalTimingAccumulatesGifDelays() async throws {
        // .interval mode: starts are the running sum of delays. 3x0.1s delays,
        // t=20 -> uniform 0.05s slots; sourceDuration 0.3 -> endSlot ceil(6.0)=6.
        let source = AsyncThrowingStream<Tok, Error> { c in
            for i in 0..<3 { c.yield(Tok(id: i, start: 0.1)) }  // start field reused as "delay"
            c.finish()
        }
        let endSlot = try resamplePreflight(targetFPS: 20, sourceDuration: 0.3)
        let stats = ResampleStats()
        let session = ResampleSession<Tok>(
            source: source,
            timing: .interval { $0.start },  // each frame's interval
            retime: { tok, k in Tok(id: tok.id, start: tok.start, slot: k) },
            targetFPS: 20, endSlot: endSlot, stats: stats
        )
        var out: [Tok] = []
        while let f = try await session.next() { out.append(f) }
        #expect(out.count == 6)
        #expect(out.map(\.id) == [0, 0, 1, 1, 2, 2])  // each source frame held for 2 slots
    }
}
