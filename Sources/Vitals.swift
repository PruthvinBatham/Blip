import Foundation
import CoreGraphics
import IOKit.ps

/// A snapshot of what the machine is doing right now. Blip's whole personality
/// is derived from this — nothing else.
struct Vitals {
    var cpu: Double = 0          // 0...1, whole-machine busy fraction
    var idle: Double = 0         // seconds since the last human input
    var typingRate: Double = 0   // 0...1, how hot the keyboard is running
    var battery: Double = 1      // 0...1
    var charging: Bool = true
}

final class VitalsMonitor {
    private var prevTotal: UInt64 = 0
    private var prevIdle: UInt64 = 0
    private var keystrokeHeat: Double = 0

    func read(dt: Double) -> Vitals {
        var v = Vitals()
        v.cpu = sampleCPU()
        v.idle = idleSeconds()

        // Keyboard "heat": a leaky bucket that fills while keys are landing
        // faster than ~3/sec and drains whenever they aren't.
        let sinceKey = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown)
        if sinceKey < 0.35 {
            keystrokeHeat = min(1, keystrokeHeat + dt * 1.6)
        } else {
            keystrokeHeat = max(0, keystrokeHeat - dt * 0.9)
        }
        v.typingRate = keystrokeHeat

        if let b = batteryState() {
            v.battery = b.level
            v.charging = b.charging
        }
        return v
    }

    /// Seconds since any human input. Deliberately built from a handful of
    /// concrete event types rather than the kCGAnyInputEventType sentinel,
    /// which doesn't survive the bridge into Swift's CGEventType enum.
    private func idleSeconds() -> Double {
        let types: [CGEventType] = [.keyDown, .flagsChanged, .leftMouseDown,
                                    .rightMouseDown, .mouseMoved, .scrollWheel]
        return types
            .map { CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: $0) }
            .min() ?? 0
    }

    private func sampleCPU() -> Double {
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        var cpuCount: natural_t = 0
        let err = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                      &cpuCount, &info, &infoCount)
        guard err == KERN_SUCCESS, let ticks = info else { return 0 }
        defer {
            vm_deallocate(mach_task_self_,
                          vm_address_t(bitPattern: ticks),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }

        var total: UInt64 = 0
        var idle: UInt64 = 0
        for i in 0..<Int(cpuCount) {
            let base = i * Int(CPU_STATE_MAX)
            let user = UInt64(ticks[base + Int(CPU_STATE_USER)])
            let sys  = UInt64(ticks[base + Int(CPU_STATE_SYSTEM)])
            let nice = UInt64(ticks[base + Int(CPU_STATE_NICE)])
            let idl  = UInt64(ticks[base + Int(CPU_STATE_IDLE)])
            total += user + sys + nice + idl
            idle  += idl
        }

        let dTotal = total &- prevTotal
        let dIdle  = idle  &- prevIdle
        let hadPrevious = prevTotal > 0
        prevTotal = total
        prevIdle = idle

        guard hadPrevious, dTotal > 0 else { return 0 }
        return max(0, min(1, 1 - Double(dIdle) / Double(dTotal)))
    }

    private func batteryState() -> (level: Double, charging: Bool)? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let d = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue()
                    as? [String: Any],
                  let current = d[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = d[kIOPSMaxCapacityKey] as? Int, maximum > 0
            else { continue }
            let charging = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            return (Double(current) / Double(maximum), charging)
        }
        return nil
    }
}
