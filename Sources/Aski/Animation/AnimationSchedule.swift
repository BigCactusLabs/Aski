import Foundation

internal struct AnimationSchedule: Sendable, Equatable {
    let candidates: ContiguousArray<UInt16>
    let candidateStride: Int
    let phases: ContiguousArray<Float>
    let periods: ContiguousArray<Float>
    let participates: BitSet
    let entrance: EntrancePattern?
    let ongoing: OngoingPattern?
    let cycling: CyclingOptions?
    let duration: TimeInterval
    let seed: UInt64
    let columns: Int
    let rows: Int
}
