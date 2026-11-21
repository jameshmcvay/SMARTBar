import AppKit

private let baseFont = NSFont.menuFont(ofSize: 0)
private let valueFont = NSFont.monospacedDigitSystemFont(ofSize: baseFont.pointSize, weight: .regular)

private func text(_ string: String, _ font: NSFont, _ color: NSColor) -> NSTextField {
    let field = NSTextField(labelWithString: string)
    field.font = font
    field.textColor = color
    return field
}

/// The drive's submenu content: model heading, then grouped "name  value" rows with the
/// names right-aligned against the values, like an inspector panel.
func detailPanel(_ row: Row) -> NSView {
    let r = row.reading
    let flagged = severityColor(.crit)
    func count(_ n: Int, bad: NSColor? = nil) -> (String, NSColor) {
        (numberText(n), n > 0 && bad != nil ? bad! : .labelColor)
    }

    // Each inner array is one visually separated group.
    var groups: [[(name: String, value: String, color: NSColor)]] = [[], [], [], []]
    if let p = r.passed { groups[0].append(("Health", p ? "Passed" : "Failed", p ? .labelColor : flagged)) }
    if let t = r.temperature {
        let color = t >= critTemperature ? flagged : t >= warnTemperature ? severityColor(.warn) : .labelColor
        groups[0].append(("Temperature", "\(t)°C" + (r.hottestRecorded.map { "  ·  peak \($0)°C" } ?? ""), color))
    }
    if let h = r.powerOnHours {
        groups[0].append(("Powered on", "\(numberText(h)) h  ·  \(String(format: "%.1f", Double(h) / 8766)) years", .labelColor))
    }
    for (name, n, bad) in [("Reallocated", r.reallocated, severityColor(.warn)), ("Pending", r.pending, flagged),
                           ("Uncorrectable", r.uncorrectable, flagged), ("CRC errors", r.crcErrors, severityColor(.warn))] {
        if let n = n { let c = count(n, bad: bad); groups[1].append((name, c.0, c.1)) }
    }
    for (name, n) in [("Spin-ups", r.startStops), ("Head parks", r.loadCycles), ("Power cycles", r.powerCycles)] {
        if let n = n { groups[2].append((name, numberText(n), .labelColor)) }
    }
    groups[3].append(("Last read", timeText(r.readAt) + (row.idle ? "  ·  idle, left asleep" : ""), .labelColor))

    let grid = NSGridView()
    grid.rowSpacing = 3
    grid.columnSpacing = 10
    grid.rowAlignment = .firstBaseline
    for group in groups where !group.isEmpty {
        for (i, item) in group.enumerated() {
            let added = grid.addRow(with: [text(item.name, baseFont, .secondaryLabelColor),
                                           text(item.value, valueFont, item.color)])
            if i == 0 && grid.numberOfRows > 1 { added.topPadding = 7 }
        }
    }
    grid.column(at: 0).xPlacement = .trailing

    var facts = ["Firmware \(r.firmware)", row.disk.device]
    if let b = r.capacityBytes { facts.insert(ByteCountFormatter.string(fromByteCount: b, countStyle: .decimal), at: 0) }
    let heading = text(r.model, .boldSystemFont(ofSize: baseFont.pointSize), .labelColor)
    let subheading = text(facts.joined(separator: "  ·  "), .systemFont(ofSize: NSFont.smallSystemFontSize), .secondaryLabelColor)

    let stack = NSStackView(views: [heading, subheading, grid])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 2
    stack.setCustomSpacing(10, after: subheading)
    stack.edgeInsets = NSEdgeInsets(top: 6, left: 14, bottom: 8, right: 20)
    // A little extra width: the fitting size comes out a few points tight for the longest value.
    let fit = stack.fittingSize
    stack.frame = NSRect(x: 0, y: 0, width: fit.width + 12, height: fit.height)
    return stack
}
