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
    private var lastVitalsRead: Date?
    private var currentFPS: Double = 0

    /// One rendered cycle per mood, keyed by mood, frame index and colour
    /// style. Blip's animation repeats exactly every `PetRenderer.loopPeriod`,
    /// so after the first pass through a mood there is nothing left to draw —
    /// we just hand the status item an image it has already seen.
    private var frames: [String: NSImage] = [:]
    private var lastFrameKey = ""

    private let defaults = UserDefaults.standard
    private var pets: Int {
        get { defaults.integer(forKey: "petCount") }
        set { defaults.set(newValue, forKey: "petCount") }
    }
    /// Colour is on by default; the monochrome template is still one menu
    /// item away, and it is the only version that tints itself to match an
    /// unusual menu bar.
    private var colorful: Bool {
        get { defaults.bool(forKey: "colorful") }
        set { defaults.set(newValue, forKey: "colorful") }
    }
    /// The CPU readout beside him. On by default — he is a better status item
    /// than he is an ornament.
    private var showsCPU: Bool {
        get { defaults.bool(forKey: "showsCPU") }
        set { defaults.set(newValue, forKey: "showsCPU") }
    }
    private var hatched: Date {
        if let d = defaults.object(forKey: "hatchDate") as? Date { return d }
        let now = Date()
        defaults.set(now, forKey: "hatchDate")
        return now
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        defaults.register(defaults: ["colorful": true, "showsCPU": true])
        _ = hatched

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = PetRenderer.image(Pose(mood: .idle, t: 0, energy: 0),
                                                     skin: skin(for: .idle))
        updateReadout()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        retime(to: fps(for: mood))
        tick()
    }

    /// The colours to draw a mood in right now. The bar's own appearance is
    /// read off the status item's button rather than the app's: the menu bar
    /// can be dark while the rest of the system is light, and it is the bar he
    /// has to stay legible against.
    private func skin(for mood: Mood) -> Skin {
        colorful ? mood.skin(dark: barIsDark) : .mono(.black)
    }

    private var barIsDark: Bool {
        let appearance = statusItem?.button?.effectiveAppearance ?? NSApp.effectiveAppearance
        return appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
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

        let elapsed = lastVitalsRead.map { now.timeIntervalSince($0) } ?? .infinity
        if elapsed >= 1.0 {
            // The first sample has no previous reading to measure against, and
            // after a sleep/wake `elapsed` is the length of the nap — either way
            // the monitor gets a sane tick rather than an interval it would
            // integrate every leaky bucket to saturation over.
            vitals = monitor.read(dt: min(elapsed, 2.0))
            lastVitalsRead = now
            mood = engine.mood(for: vitals, now: now)
            retime(to: fps(for: mood))
            updateReadout()
        }

        let phase = now.timeIntervalSince(started)
            .truncatingRemainder(dividingBy: PetRenderer.loopPeriod)
        let index = Int(phase * currentFPS)
        let dressed = skin(for: mood)
        // The style belongs in the key: flipping the toggle, or dragging him to
        // a screen whose menu bar is the other appearance, has to miss the
        // cache rather than hand back the frame in the old colours.
        let style = colorful ? (barIsDark ? "dark" : "light") : "mono"
        let key = "\(mood.rawValue)-\(index)-\(style)"
        guard key != lastFrameKey else { return }
        lastFrameKey = key

        let image: NSImage
        if let cached = frames[key] {
            image = cached
        } else {
            // Quantise the time to the frame index so the cached image and its
            // key can never disagree.
            image = PetRenderer.image(Pose(mood: mood, t: Double(index) / currentFPS,
                                           energy: vitals.cpu),
                                      skin: dressed)
            frames[key] = image
        }
        statusItem.button?.image = image
    }

    // MARK: - CPU readout

    /// Menu bar text is sized by the user, so the readout is derived from the
    /// menu bar font rather than pinned to a point size, and set in monospaced
    /// digits so the number doesn't wobble as it counts.
    private static let readoutFont = NSFont.monospacedDigitSystemFont(
        ofSize: max(10, NSFont.menuBarFont(ofSize: 0).pointSize - 2), weight: .regular)

    private var lastReadout = ""

    private func updateReadout() {
        guard let button = statusItem?.button else { return }

        // Switching the readout off is just the empty string, so one code path
        // and one change-guard cover both the per-second update and the toggle.
        let text = showsCPU ? readout(for: vitals.cpu) : ""
        guard text != lastReadout else { return }
        lastReadout = text

        button.imagePosition = text.isEmpty ? .imageOnly : .imageLeading
        // labelColor rather than the mood colour: this one is meant to be read
        // at a glance, and it has to stay legible over a translucent bar.
        button.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: AppDelegate.readoutFont,
            .foregroundColor: NSColor.labelColor,
        ])
    }

    /// Padded to a fixed three columns with figure spaces — U+2007 is a
    /// digit-width space, so 7%, 42% and 100% all occupy the same width and the
    /// menu bar stops shuffling every item to Blip's left once a second.
    private func readout(for cpu: Double) -> String {
        let digits = String(Int((cpu * 100).rounded()))
        return String(repeating: "\u{2007}", count: max(0, 3 - digits.count)) + digits + "%"
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

        let cpu = NSMenuItem(title: "Show CPU %", action: #selector(toggleCPU), keyEquivalent: "")
        cpu.target = self
        cpu.state = showsCPU ? .on : .off
        menu.addItem(cpu)

        let colour = NSMenuItem(title: "Colorful", action: #selector(toggleColor),
                                keyEquivalent: "")
        colour.target = self
        colour.state = colorful ? .on : .off
        menu.addItem(colour)

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

    @objc private func toggleCPU() {
        showsCPU.toggle()
        updateReadout()
    }

    @objc private func toggleColor() {
        colorful.toggle()
        // Every cached frame is in the old style now.
        frames.removeAll()
        lastFrameKey = ""
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
