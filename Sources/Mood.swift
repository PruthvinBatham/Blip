import Foundation

enum Mood: String, CaseIterable {
    case sleeping
    case idle
    case curious
    case zoomies
    case working
    case frantic
    case hungry
    case happy

    var blurb: String {
        switch self {
        case .sleeping: return "Asleep. You've been gone a while."
        case .idle:     return "Just vibing."
        case .curious:  return "Watching you work."
        case .zoomies:  return "ZOOMIES — you're typing fast."
        case .working:  return "Locked in. Something's compiling."
        case .frantic:  return "Panicking. Your CPU is on fire."
        case .hungry:   return "Hungry. Plug the laptop in."
        case .happy:    return "Very pleased with you."
        }
    }
}

/// Maps raw machine vitals onto a mood. Order matters: the first rule that
/// matches wins, so this reads top-down as a priority list.
struct MoodEngine {
    /// Timestamp of the last head-pat, so affection outranks everything briefly.
    var lastPetted: Date = .distantPast
    private var current: Mood = .idle
    private var heldSince: Date = Date()

    /// Moods flip-flop badly right at a threshold, so a mood has to survive a
    /// minimum dwell time before another one can take over.
    private let dwell: TimeInterval = 1.2

    mutating func mood(for v: Vitals, now: Date = Date()) -> Mood {
        let wanted = rawMood(for: v, now: now)
        if wanted != current && now.timeIntervalSince(heldSince) >= dwell {
            current = wanted
            heldSince = now
        } else if wanted == current {
            heldSince = max(heldSince, heldSince)
        }
        return current
    }

    private func rawMood(for v: Vitals, now: Date) -> Mood {
        if now.timeIntervalSince(lastPetted) < 4      { return .happy }
        if v.idle > 300                                { return .sleeping }
        if v.battery < 0.20 && !v.charging             { return .hungry }
        if v.cpu > 0.75                                { return .frantic }
        if v.typingRate > 0.55                         { return .zoomies }
        if v.cpu > 0.30                                { return .working }
        if v.idle < 8                                  { return .curious }
        return .idle
    }
}
