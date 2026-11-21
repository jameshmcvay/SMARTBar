import AppKit

// Draws mock screenshots of the menu from made-up drives, so the README images contain
// no real serial numbers and can be regenerated after layout changes.

private let font = NSFont.menuFont(ofSize: 0)
private let rowHeight: CGFloat = 22
private let separatorHeight: CGFloat = 11
private let menuPadding: CGFloat = 5
private let rightInset: CGFloat = 14
private let scale: CGFloat = 2

private enum Item {
    case drive(Row, open: Bool)
    case command(String, key: String = "", checked: Bool = false, submenu: Bool = false)
    case note(String)
    case separator
    case panel(NSImage)
}

private let sampleDate = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 14, hour: 15, minute: 45))!

private func sample(_ serial: String, _ device: String, _ temperature: Int, peak: Int, hours: Int,
                    kind: String, volumes: [String], pending: Int = 0, idle: Bool = false) -> Row {
    Row(disk: Disk(device: device, kind: kind, volumes: volumes),
        reading: DriveReading(
            model: "ST16000NM001G-2KK103", serial: serial, firmware: "SN03", capacityBytes: 16_000_900_608_000,
            passed: true, temperature: temperature, hottestRecorded: peak, powerOnHours: hours,
            powerCycles: 212, startStops: 3_870, loadCycles: 6_420, reallocated: 0, pending: pending,
            uncorrectable: 0, crcErrors: 0, readAt: sampleDate),
        idle: idle)
}

private func sampleRows(problems: Bool) -> [Row] {
    [sample("ZX41B7KD", "disk6", 38, peak: 49, hours: 18_204, kind: "RAID1", volumes: ["Media", "Projects"]),
     sample("ZX41C02M", "disk7", problems ? 47 : 41, peak: 52, hours: 18_197, kind: "RAID1", volumes: ["Media", "Projects"]),
     sample("ZX43A9PT", "disk8", 39, peak: 50, hours: 11_930, kind: "RAID1", volumes: ["Media", "Projects"]),
     sample("ZR5E2K7Q", "disk9", 35, peak: 47, hours: 21_466, kind: "Single", volumes: ["Time Machine"]),
     sample("ZR5F8T3V", "disk10", 33, peak: 46, hours: 21_502, kind: "Single", volumes: ["Scratch"],
            pending: problems ? 8 : 0, idle: !problems)]
}

private func symbol(_ name: String, _ color: NSColor, size: CGFloat) -> NSImage? {
    let config = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
}

private func draw(_ image: NSImage?, centeredAt point: NSPoint) {
    guard let image = image else { return }
    let rect = NSRect(x: point.x - image.size.width / 2, y: point.y - image.size.height / 2,
                      width: image.size.width, height: image.size.height)
    image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
}

private func bitmap(_ size: NSSize) -> NSBitmapImageRep? {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    rep?.size = size
    return rep
}

private func image(of view: NSView, _ appearance: NSAppearance) -> NSImage {
    view.appearance = appearance
    view.layoutSubtreeIfNeeded()
    let image = NSImage(size: view.bounds.size)
    if let rep = bitmap(view.bounds.size), let context = NSGraphicsContext(bitmapImageRep: rep) {
        view.displayIgnoringOpacity(view.bounds, in: context)
        image.addRepresentation(rep)
    }
    return image
}

private func text(_ string: String, _ color: NSColor) -> NSAttributedString {
    NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color])
}

private struct MockMenu {
    let items: [Item]
    let columns: NSParagraphStyle
    let textInset: CGFloat  // wider when the menu has a checkmark column

    private func height(_ item: Item) -> CGFloat {
        switch item {
        case .separator: return separatorHeight
        case .panel(let image): return image.size.height
        default: return rowHeight
        }
    }

    private func width(_ item: Item) -> CGFloat {
        switch item {
        case .drive(let row, _): return textInset + driveTitle(row, columns).size().width + 34
        case .command(let title, let key, _, let submenu):
            return textInset + text(title, .labelColor).size().width + (key.isEmpty ? 0 : 50) + (submenu ? 24 : 0) + rightInset
        case .note(let string): return textInset + text(string, .labelColor).size().width + rightInset
        case .separator: return 0
        case .panel(let image): return image.size.width
        }
    }

    var size: NSSize {
        NSSize(width: ceil(items.map(width).max() ?? 0),
               height: items.map(height).reduce(0, +) + menuPadding * 2)
    }

    /// Distance from the top of the menu to the row whose submenu is shown open.
    var openRowOffset: CGFloat {
        var y = menuPadding
        for item in items {
            if case .drive(_, true) = item { return y }
            y += height(item)
        }
        return y
    }

    func draw(at origin: NSPoint, dark: Bool) {
        let frame = NSRect(origin: origin, size: size)
        let shape = NSBezierPath(roundedRect: frame, xRadius: 9, yRadius: 9)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.5 : 0.25)
        shadow.shadowBlurRadius = 22
        shadow.shadowOffset = NSSize(width: 0, height: -10)
        shadow.set()
        (dark ? NSColor(white: 0.17, alpha: 1) : NSColor(white: 0.96, alpha: 1)).setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.labelColor.withAlphaComponent(0.18).setStroke()
        shape.lineWidth = 0.5
        shape.stroke()

        var y = frame.minY + menuPadding
        let textX = frame.minX + textInset
        func line(_ string: NSAttributedString) {
            string.draw(at: NSPoint(x: textX, y: y + (rowHeight - string.size().height) / 2))
        }
        func chevron() {
            SMARTBar.draw(symbol("chevron.right", .secondaryLabelColor, size: 9),
                          centeredAt: NSPoint(x: frame.maxX - rightInset, y: y + rowHeight / 2))
        }
        for item in items {
            switch item {
            case .drive(let row, let open):
                if open {
                    NSColor.labelColor.withAlphaComponent(0.1).setFill()
                    NSBezierPath(roundedRect: NSRect(x: frame.minX + 5, y: y, width: frame.width - 10, height: rowHeight),
                                 xRadius: 5, yRadius: 5).fill()
                }
                line(driveTitle(row, columns))
                chevron()
            case .command(let title, let key, let checked, let submenu):
                if checked {
                    SMARTBar.draw(symbol("checkmark", .labelColor, size: 10),
                                  centeredAt: NSPoint(x: frame.minX + 13, y: y + rowHeight / 2))
                }
                line(text(title, .labelColor))
                if !key.isEmpty {
                    let shortcut = text(key, .secondaryLabelColor)
                    shortcut.draw(at: NSPoint(x: frame.maxX - rightInset - shortcut.size().width,
                                              y: y + (rowHeight - shortcut.size().height) / 2))
                }
                if submenu { chevron() }
            case .note(let string):
                line(text(string, .tertiaryLabelColor))
            case .separator:
                NSColor.labelColor.withAlphaComponent(0.14).setFill()
                NSRect(x: frame.minX + 12, y: y + separatorHeight / 2, width: frame.width - 24, height: 1).fill()
            case .panel(let image):
                image.draw(in: NSRect(x: frame.minX, y: y, width: image.size.width, height: image.size.height),
                           from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
            y += height(item)
        }
    }
}

private func render(_ rows: [Row], open: Int, _ appearance: NSAppearance, dark: Bool, to url: URL) {
    let raid = RaidSet(name: "Media", level: "Mirror", status: "Online", memberStatuses: ["Online", "Online", "Online"])
    let snapshot = Snapshot(rows: rows, raids: [raid], updated: sampleDate)
    let columns = columnStops(rows)

    var items: [Item] = rows.enumerated().map { .drive($0.element, open: $0.offset == open) }
    items += [.separator,
              .note("\(raid.name) \(raid.level.lowercased()): \(raid.status), 3/3 members online"),
              .separator,
              .note("Checked \(timeText(sampleDate))"),
              .command("Refresh Now (wakes idle drives)", key: "⌘R"),
              .command("Check Every", submenu: true),
              .command("Leave Idle Drives Asleep", checked: true),
              .command("Launch at Login", checked: true),
              .separator,
              .command("Quit SMARTBar", key: "⌘Q")]
    let menu = MockMenu(items: items, columns: columns, textInset: 24)
    let submenu = MockMenu(items: [.panel(image(of: detailPanel(rows[open]), appearance)), .separator,
                                   .command("Copy Serial Number")],
                           columns: columns, textInset: 14)

    let margin: CGFloat = 40
    let barHeight: CGFloat = 26
    let menuOrigin = NSPoint(x: margin, y: barHeight + 5)
    let submenuOrigin = NSPoint(x: menuOrigin.x + menu.size.width - 3,
                                y: menuOrigin.y + menu.openRowOffset - menuPadding)
    let size = NSSize(width: ceil(submenuOrigin.x + submenu.size.width + margin),
                      height: ceil(max(menuOrigin.y + menu.size.height, submenuOrigin.y + submenu.size.height) + margin))

    guard let rep = bitmap(size), let base = NSGraphicsContext(bitmapImageRep: rep) else { return }
    base.cgContext.translateBy(x: 0, y: size.height)
    base.cgContext.scaleBy(x: 1, y: -1)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: base.cgContext, flipped: true)

    // Desktop and menu bar
    let wallpaper = dark
        ? [NSColor(red: 0.07, green: 0.11, blue: 0.24, alpha: 1), NSColor(red: 0.24, green: 0.14, blue: 0.36, alpha: 1)]
        : [NSColor(red: 0.55, green: 0.73, blue: 0.98, alpha: 1), NSColor(red: 0.80, green: 0.72, blue: 0.97, alpha: 1)]
    NSGradient(colors: wallpaper)?.draw(in: NSRect(origin: .zero, size: size), angle: 55)
    (dark ? NSColor.black.withAlphaComponent(0.3) : NSColor.white.withAlphaComponent(0.45)).setFill()
    NSRect(x: 0, y: 0, width: size.width, height: barHeight).fill()

    // Status item, shown pressed because its menu is open
    let hottest = rows.compactMap { $0.reading.temperature }.max() ?? 0
    let tint = snapshot.severity == .ok ? NSColor.labelColor : severityColor(snapshot.severity)
    let title = NSAttributedString(string: "\(hottest)°", attributes: [
        .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular), .foregroundColor: tint])
    let pill = NSRect(x: menuOrigin.x, y: 2, width: 34 + title.size().width, height: barHeight - 4)
    NSColor.labelColor.withAlphaComponent(0.14).setFill()
    NSBezierPath(roundedRect: pill, xRadius: 5, yRadius: 5).fill()
    draw(symbol("internaldrive", .labelColor, size: 13), centeredAt: NSPoint(x: pill.minX + 16, y: pill.midY))
    title.draw(at: NSPoint(x: pill.minX + 28, y: pill.midY - title.size().height / 2))

    menu.draw(at: menuOrigin, dark: dark)
    submenu.draw(at: submenuOrigin, dark: dark)
    NSGraphicsContext.restoreGraphicsState()
    try? rep.representation(using: .png, properties: [:])?.write(to: url)
}

func writeScreenshots(to folder: String) {
    let folder = URL(fileURLWithPath: folder, isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for (name, appearanceName) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
        guard let appearance = NSAppearance(named: appearanceName) else { continue }
        appearance.performAsCurrentDrawingAppearance {
            render(sampleRows(problems: false), open: 0, appearance, dark: name == "dark",
                   to: folder.appendingPathComponent("menu-\(name).png"))
            render(sampleRows(problems: true), open: 4, appearance, dark: name == "dark",
                   to: folder.appendingPathComponent("warning-\(name).png"))
        }
    }
}
