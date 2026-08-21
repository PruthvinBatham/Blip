import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?

    private let monitor = VitalsMonitor()
    private var engine = MoodEngine()
    private var vitals = Vitals()
    private var mood: Mood = .idle

    private let started = Date()
    private var lastVitalsRead = Date.distantPast
    private var currentFPS: Double = 0

    /// One rendered cycle per mood, keyed by mood and frame index. Blip's
    /// animation repeats exactly every `PetRenderer.loopPeriod`, so after the
    /// first pass through a mood there is nothing left to draw — we just hand
    /// the status item an image it has already seen.
    private var frames: [String: NSImage] = [:]
    private var lastFrameKey = ""

    private let defaults = UserDefaults.standard
    private var pets: Int {
        get { defaults.integer(forKey: "petCount") }
        set { defaults.set(newValue, forKey: "petCount") }
    }
    private var hatched: Date {
        if let d = defaults.object(forKey: "hatchDate") as? Date { return d }
        let now = Date()
        defaults.set(now, forKey: "hatchDate")
        return now
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = hatched

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = PetRenderer.image(Pose(mood: .idle, t: 0, energy: 0))

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        retime(to: fps(for: mood))
        tick()
    }

    /// Frame rate is per-mood rather than fixed: a sleeping Blip that only
    /// breathes doesn't need 12 wake-ups a second, and this app is running all
    /// day. Retiming happens on mood changes, which are rare.
    private func fps(for mood: Mood) -> Double {
        switch mood {
        case .frantic, .zoomies: return 12
        case .working, .happy:   return 6
        case .sleeping:          return 1.5
        default:                 return 3
        }
    }

    private func retime(to rate: Double) {
        guard rate != currentFPS else { return }
        currentFPS = rate
        timer?.invalidate()
        // .common keeps him animating while the menu is open — in the default
        // mode the run loop switches to event tracking and he freezes mid-pat.
        let t = Timer(timeInterval: 1.0 / rate, repeats: true) { [weak self] _ in
            self?.tick()
        }
        t.tolerance = 1.0 / (rate * 4)   // let the system coalesce our wake-ups
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let now = Date()

        if now.timeIntervalSince(lastVitalsRead) >= 1.0 {
            vitals = monitor.read(dt: now.timeIntervalSince(lastVitalsRead))
            lastVitalsRead = now
            mood = engine.mood(for: vitals, now: now)
            retime(to: fps(for: mood))
        }

        let phase = now.timeIntervalSince(started)
            .truncatingRemainder(dividingBy: PetRenderer.loopPeriod)
        let index = Int(phase * currentFPS)
        let key = "\(mood.rawValue)-\(index)"
        guard key != lastFrameKey else { return }
        lastFrameKey = key

        let image: NSImage
        if let cached = frames[key] {
            image = cached
        } else {
            // Quantise the time to the frame index so the cached image and its
            // key can never disagree.
            image = PetRenderer.image(Pose(mood: mood, t: Double(index) / currentFPS,
                                           energy: vitals.cpu))
            frames[key] = image
        }
        statusItem.button?.image = image
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(disabled("Blip · \(mood.blurb)", bold: true))

        let battery = Int((vitals.battery * 100).rounded())
        let plug = vitals.charging ? "⚡︎" : ""
        menu.addItem(disabled(String(format: "CPU %d%%   ·   idle %@   ·   battery %d%%%@",
                                     Int((vitals.cpu * 100).rounded()),
                                     short(vitals.idle), battery, plug)))

        menu.addItem(.separator())

        let pet = NSMenuItem(title: "Pet Blip", action: #selector(petBlip), keyEquivalent: "p")
        pet.target = self
        menu.addItem(pet)

        menu.addItem(.separator())

        let age = max(0, Int(Date().timeIntervalSince(hatched) / 86400))
        let ageText = age == 0 ? "hatched today" : "\(age) day\(age == 1 ? "" : "s") old"
        menu.addItem(disabled("\(ageText)  ·  petted \(pets) time\(pets == 1 ? "" : "s")"))

        menu.addItem(.separator())

        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin),
                               keyEquivalent: "")
        login.target = self
        login.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.addItem(login)

        let quit = NSMenuItem(title: "Quit Blip", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func petBlip() {
        pets += 1
        engine.lastPetted = Date()
        mood = engine.mood(for: vitals, now: Date())
        tick()
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let a = NSAlert()
            a.messageText = "Couldn't change the login setting"
            a.informativeText = "\(error.localizedDescription)\n\nThis usually works only once Blip.app is in /Applications."
            a.runModal()
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Small helpers

    private func disabled(_ text: String, bold: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        let font = bold ? NSFont.systemFont(ofSize: 13, weight: .semibold)
                        : NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        item.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: bold ? NSColor.labelColor : NSColor.secondaryLabelColor,
        ])
        return item
    }

    private func short(_ seconds: Double) -> String {
        if seconds < 60 { return "\(Int(seconds))s" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        return String(format: "%.1fh", seconds / 3600)
    }
}
