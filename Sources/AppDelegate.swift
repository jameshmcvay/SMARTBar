import AppKit
import ServiceManagement

private let pollChoices = [5, 15, 30, 60]  // minutes

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let monitor = Monitor()
    private let queue = DispatchQueue(label: "smartbar.poll")
    private let defaults = UserDefaults.standard
    private var snapshot = Snapshot()
    private var refreshing = false
    private var timer: Timer?

    private var pollMinutes: Int {
        let v = defaults.integer(forKey: "pollMinutes")
        return v > 0 ? v : 15
    }
    private var skipIdle: Bool { defaults.object(forKey: "skipIdle") as? Bool ?? true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem.button?.image = NSImage(systemSymbolName: "internaldrive", accessibilityDescription: "SMARTBar")
        statusItem.button?.imagePosition = .imageLeading
        render()
        refresh(force: false)
        scheduleTimer()
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            nc.addObserver(self, selector: #selector(poll), name: name, object: nil)
        }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: TimeInterval(pollMinutes * 60), repeats: true) { [weak self] _ in self?.poll() }
        t.tolerance = 30
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func refresh(force: Bool) {
        guard !refreshing else { return }
        refreshing = true
        let skipIdle = self.skipIdle
        queue.async {
            let snap = self.monitor.refresh(force: force, skipIdle: skipIdle)
            DispatchQueue.main.async {
                self.snapshot = snap
                self.refreshing = false
                self.render()
            }
        }
    }

    // MARK: Rendering

    private func render() {
        let hottest = snapshot.rows.compactMap { $0.reading.temperature }.max()
        var attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        ]
        if snapshot.severity != .ok { attrs[.foregroundColor] = severityColor(snapshot.severity) }
        statusItem.button?.attributedTitle = NSAttributedString(
            string: hottest.map { " \($0)°" } ?? " –", attributes: attrs)

        let menu = NSMenu()
        if smartctlPath == nil {
            menu.addItem(info("smartctl not found — brew install smartmontools"))
        } else if snapshot.rows.isEmpty {
            menu.addItem(info(snapshot.updated == nil ? "Reading drives…" : "No external drives with SMART"))
        }
        let columns = columnStops(snapshot.rows)
        for row in snapshot.rows { menu.addItem(driveItem(row, columns)) }
        if !snapshot.raids.isEmpty { menu.addItem(.separator()) }
        for raid in snapshot.raids {
            let members = raid.memberStatuses.filter { $0 == "Online" }.count
            let text = "\(raid.name) \(raid.level.lowercased()): \(raid.status), \(members)/\(raid.memberStatuses.count) members online"
            menu.addItem(info(text, color: raid.healthy ? nil : severityColor(.crit)))
        }
        menu.addItem(.separator())
        if let updated = snapshot.updated { menu.addItem(info("Checked \(timeText(updated))")) }
        menu.addItem(action("Refresh Now (wakes idle drives)", #selector(refreshNow), key: "r"))

        let interval = NSMenuItem(title: "Check Every", action: nil, keyEquivalent: "")
        interval.submenu = NSMenu()
        for m in pollChoices {
            let item = action(m < 60 ? "\(m) minutes" : "\(m / 60) hour", #selector(setInterval(_:)))
            item.tag = m
            item.state = m == pollMinutes ? .on : .off
            interval.submenu?.addItem(item)
        }
        menu.addItem(interval)

        let idle = action("Leave Idle Drives Asleep", #selector(toggleSkipIdle))
        idle.state = skipIdle ? .on : .off
        menu.addItem(idle)
        let login = action("Launch at Login", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit SMARTBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func driveItem(_ row: Row, _ columns: NSParagraphStyle) -> NSMenuItem {
        let r = row.reading
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.attributedTitle = driveTitle(row, columns)
        let sub = NSMenu()
        let detail = NSMenuItem()
        detail.view = detailPanel(row)
        sub.addItem(detail)
        sub.addItem(.separator())
        let copy = action("Copy Serial Number", #selector(copySerial(_:)))
        copy.representedObject = r.serial
        sub.addItem(copy)
        item.submenu = sub
        return item
    }

    private func info(_ text: String, color: NSColor? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        if let color = color {
            item.attributedTitle = NSAttributedString(
                string: text, attributes: [.foregroundColor: color, .font: NSFont.menuFont(ofSize: 13)])
        }
        return item
    }

    private func action(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: Actions

    @objc private func poll() { refresh(force: false) }

    @objc private func refreshNow() { refresh(force: true) }

    @objc private func setInterval(_ sender: NSMenuItem) {
        defaults.set(sender.tag, forKey: "pollMinutes")
        scheduleTimer()
        render()
    }

    @objc private func toggleSkipIdle() {
        defaults.set(!skipIdle, forKey: "skipIdle")
        render()
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
        render()
    }

    @objc private func copySerial(_ sender: NSMenuItem) {
        guard let serial = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(serial, forType: .string)
    }
}
