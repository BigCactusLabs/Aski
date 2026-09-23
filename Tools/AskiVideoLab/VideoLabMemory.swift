import Darwin
import Foundation

/// Resident-memory sampler via `task_info(TASK_VM_INFO)` → `phys_footprint`.
enum MemoryProbe {
    /// Current physical footprint in bytes, or 0 if the call fails.
    static func footprintBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<natural_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.phys_footprint) : 0
    }
}

/// Tracks peak `phys_footprint` across a run. `start()` spawns a polling task;
/// `finish()` cancels it and returns the max observed (including a final sample).
actor PeakMemoryTracker {
    private var peak: UInt64 = 0
    private var poller: Task<Void, Never>?

    /// Begins polling every ~10ms. Cheap; does not perturb throughput timing.
    func start() {
        peak = max(peak, MemoryProbe.footprintBytes())
        poller = Task { [weak self] in
            while !Task.isCancelled {
                await self?.sample()
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    /// Stops polling and returns the peak (with one last sample folded in).
    func finish() -> UInt64 {
        poller?.cancel()
        poller = nil
        peak = max(peak, MemoryProbe.footprintBytes())
        return peak
    }

    private func sample() {
        peak = max(peak, MemoryProbe.footprintBytes())
    }
}
