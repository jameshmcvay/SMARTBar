import AppKit

// Every column uses the menu font at one size so the row sits on a single baseline;
// serial and temperature get tabular digits so they don't shift between readings.
private let rowFont = NSFont.menuFont(ofSize: 0)
private let digitFont = NSFont.monospacedDigitSystemFont(ofSize: rowFont.pointSize, weight: .regular)
private let dotSize: CGFloat = 9
private let columnGap: CGFloat = 16

func severityColor(_ s: Severity) -> NSColor {
    switch s {
    case .ok: return .systemGreen
    case .warn: return .systemOrange
    case .crit: return .systemRed
    }
}

func temperatureText(_ r: DriveReading) -> String { r.temperature.map { "\($0)°C" } ?? "–" }

/// Status indicator drawn as an image so it's the same size and height on every row.
/// Filled when the drive was just read, a ring when it was left asleep.
private func statusDot(_ color: NSColor, filled: Bool) -> NSAttributedString {
    let image = NSImage(size: NSSize(width: dotSize, height: dotSize), flipped: false) { rect in
        if filled {
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
        } else {
            color.setStroke()
            let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 1.25, dy: 1.25))
            ring.lineWidth = 1.5
            ring.stroke()
        }
        return true
    }
    let attachment = NSTextAttachment()
    attachment.image = image
    attachment.bounds = CGRect(x: 0, y: (rowFont.capHeight - dotSize) / 2, width: dotSize, height: dotSize)
    return NSAttributedString(attachment: attachment)
}

private func width(_ text: String, _ font: NSFont) -> CGFloat {
    ceil((text as NSString).size(withAttributes: [.font: font]).width)
}

private let dotColumn = dotSize + width("  ", rowFont)

/// Tab stops shared by every drive row so the columns line up:
/// "● serial ⇥ temperature ⇥ kind ⇥ volumes", with the temperature right-aligned.
func columnStops(_ rows: [Row]) -> NSParagraphStyle {
    func widest(_ texts: [String], _ font: NSFont) -> CGFloat { texts.map { width($0, font) }.max() ?? 0 }
    let temp = dotColumn + widest(rows.map { $0.reading.serial }, digitFont) + columnGap
        + widest(rows.map { temperatureText($0.reading) }, digitFont)
    let kind = temp + columnGap
    let volumes = kind + widest(rows.map { $0.disk.kind }, rowFont) + columnGap
    let style = NSMutableParagraphStyle()
    style.tabStops = [NSTextTab(textAlignment: .right, location: temp),
                      NSTextTab(textAlignment: .left, location: kind),
                      NSTextTab(textAlignment: .left, location: volumes)]
    style.lineBreakMode = .byClipping
    return style
}

func driveTitle(_ row: Row, _ columns: NSParagraphStyle) -> NSAttributedString {
    let r = row.reading
    let title = NSMutableAttributedString(attributedString: statusDot(severityColor(r.severity), filled: !row.idle))
    func add(_ text: String, _ font: NSFont, _ color: NSColor) {
        title.append(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color]))
    }
    add("  \(r.serial)\t", digitFont, .labelColor)
    add("\(temperatureText(r))\t", digitFont, .labelColor)
    add("\(row.disk.kind)\t", rowFont, .secondaryLabelColor)
    add(row.disk.label, rowFont, .labelColor)
    title.addAttribute(.paragraphStyle, value: columns, range: NSRange(location: 0, length: title.length))
    return title
}

func timeText(_ date: Date) -> String {
    DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
}

func numberText(_ n: Int) -> String {
    NumberFormatter.localizedString(from: NSNumber(value: n), number: .decimal)
}

private func writePNG(_ image: NSImage, to url: URL) {
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: url)
}

/// Draws the drive rows (rows.png) and the first drive's detail panel (detail.png) into a
/// folder, for checking the layout without opening the menu.
func writePreview(_ rows: [Row], to folder: String) {
    let folder = URL(fileURLWithPath: folder, isDirectory: true)
    let columns = columnStops(rows)
    let titles = rows.map { driveTitle($0, columns) }
    let lineHeight: CGFloat = 22
    let size = NSSize(width: (titles.map { $0.size().width }.max() ?? 0) + 40,
                      height: lineHeight * CGFloat(titles.count) + 16)
    writePNG(NSImage(size: size, flipped: true) { rect in
        NSColor.windowBackgroundColor.setFill()
        rect.fill()
        for (i, title) in titles.enumerated() {
            title.draw(at: NSPoint(x: 20, y: 8 + lineHeight * CGFloat(i) + 3))
        }
        return true
    }, to: folder.appendingPathComponent("rows.png"))

    guard let first = rows.first else { return }
    let panel = detailPanel(first)
    panel.layoutSubtreeIfNeeded()
    guard let rep = panel.bitmapImageRepForCachingDisplay(in: panel.bounds),
          let context = NSGraphicsContext(bitmapImageRep: rep) else { return }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    NSColor.windowBackgroundColor.setFill()
    panel.bounds.fill()
    NSGraphicsContext.restoreGraphicsState()
    panel.displayIgnoringOpacity(panel.bounds, in: context)
    writePNG(NSImage(size: panel.bounds.size, flipped: false) { rect in
        rep.draw(in: rect)
        return true
    }, to: folder.appendingPathComponent("detail.png"))
}
