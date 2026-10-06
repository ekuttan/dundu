import Foundation
import Darwin
import IOKit.ps
import Observation

/// CPU, memory and battery for the overview page.
///
/// All three come from Mach and IOKit directly rather than by shelling out —
/// a sandboxed menu bar app cannot run `top`, and spawning anything every few
/// seconds for three numbers would cost more than the numbers are worth.
@Observable
@MainActor
final class SystemStats {
    static let shared = SystemStats()

    private(set) var cpu: Double = 0
    private(set) var memory: Double = 0
    /// 0…1, or nil on a Mac with no battery.
    private(set) var battery: Double?
    private(set) var isCharging = false

    private var ticker: Timer?
    private var subscribers = 0
    /// CPU load is a rate, so the first sample can only establish a baseline.
    private var previousTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?

    /// Sampling runs only while a page is actually showing the numbers.
    func subscribe() {
        subscribers += 1
        guard ticker == nil else { return }
        sample()
        // The singleton is referenced directly rather than captured: a
        // repeating timer holding the only strong reference to its own owner
        // is how menu bar apps end up sampling forever.
        ticker = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            Task { @MainActor in SystemStats.shared.sample() }
        }
    }

    func unsubscribe() {
        subscribers = max(0, subscribers - 1)
        guard subscribers == 0 else { return }
        ticker?.invalidate()
        ticker = nil
        previousTicks = nil
    }

    private func sample() {
        cpu = Self.cpuLoad(previous: &previousTicks) ?? cpu
        memory = Self.memoryUsed() ?? memory
        let power = Self.batteryLevel()
        battery = power?.level
        isCharging = power?.charging ?? false
    }

    // MARK: - Mach

    /// Aggregate ticks across all cores, differenced against the last read.
    nonisolated static func cpuLoad(
        previous: inout (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?
    ) -> Double? {
        // HOST_CPU_LOAD_INFO_COUNT is a C macro and does not cross into
        // Swift, so the struct's own size supplies it.
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        var info = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let now = (
            user: UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2),
            nice: UInt64(info.cpu_ticks.3)
        )
        defer { previous = now }
        guard let last = previous else { return nil }

        let busy = Double((now.user &- last.user) + (now.system &- last.system) + (now.nice &- last.nice))
        let idle = Double(now.idle &- last.idle)
        let total = busy + idle
        guard total > 0 else { return nil }
        return busy / total
    }

    /// "Used" here means what macOS itself calls memory pressure territory:
    /// anything not free or purgeable. File-backed pages that can be evicted
    /// without cost are deliberately not counted, or an idle Mac would read
    /// 95% and the number would mean nothing.
    nonisolated static func memoryUsed() -> Double? {
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        var stats = vm_statistics64_data_t()
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let pageSize = Double(vm_kernel_page_size)
        let used = (Double(stats.active_count) + Double(stats.wire_count)
            + Double(stats.compressor_page_count)) * pageSize
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        guard total > 0 else { return nil }
        return min(1, used / total)
    }

    nonisolated static func batteryLevel() -> (level: Double, charging: Bool)? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any],
                let current = description[kIOPSCurrentCapacityKey] as? Int,
                let max = description[kIOPSMaxCapacityKey] as? Int,
                max > 0
            else { continue }
            let state = description[kIOPSPowerSourceStateKey] as? String
            return (Double(current) / Double(max), state == kIOPSACPowerValue)
        }
        return nil
    }
}
