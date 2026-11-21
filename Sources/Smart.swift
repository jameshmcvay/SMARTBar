import Foundation

let warnTemperature = 45  // °C
let critTemperature = 55  // °C

enum Severity: Int, Comparable {
    case ok, warn, crit
    static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }
}

struct DriveReading {
    let model: String
    let serial: String
    let firmware: String
    let capacityBytes: Int64?
    let passed: Bool?
    let temperature: Int?
    let hottestRecorded: Int?
    let powerOnHours: Int?
    let powerCycles: Int?
    let startStops: Int?
    let loadCycles: Int?
    let reallocated: Int?
    let pending: Int?
    let uncorrectable: Int?
    let crcErrors: Int?
    let readAt: Date

    /// Why this drive isn't OK, most serious first. Empty when healthy.
    var problems: [(Severity, String)] {
        var p: [(Severity, String)] = []
        if passed == false { p.append((.crit, "SMART health check FAILED")) }
        if let n = pending, n > 0 { p.append((.crit, "\(n) sectors pending reallocation")) }
        if let n = uncorrectable, n > 0 { p.append((.crit, "\(n) uncorrectable sectors")) }
        if let t = temperature, t >= critTemperature { p.append((.crit, "Running at \(t)°C")) }
        if let n = reallocated, n > 0 { p.append((.warn, "\(n) reallocated sectors")) }
        if let n = crcErrors, n > 0 { p.append((.warn, "\(n) interface CRC errors")) }
        if let t = temperature, t >= warnTemperature, t < critTemperature { p.append((.warn, "Running at \(t)°C")) }
        return p
    }

    var severity: Severity { problems.map { $0.0 }.max() ?? .ok }
}

let smartctlPath: String? = ["/opt/homebrew/bin/smartctl", "/usr/local/bin/smartctl",
                             "/opt/local/sbin/smartctl", "/usr/local/sbin/smartctl"]
    .first { FileManager.default.isExecutableFile(atPath: $0) }

/// Reads identity, health and attributes (read-only). Returns nil if the device has no
/// SMART, or is asleep on an enclosure that can report that.
func readSmart(_ device: String) -> DriveReading? {
    guard let smartctl = smartctlPath else { return nil }
    let out = run(smartctl, ["-n", "standby", "-j", "-i", "-H", "-A", "/dev/\(device)"]).out
    guard let j = (try? JSONSerialization.jsonObject(with: out)) as? [String: Any],
          let model = j["model_name"] as? String else { return nil }

    func sub(_ key: String) -> [String: Any] { j[key] as? [String: Any] ?? [:] }
    var attrs: [Int: [String: Any]] = [:]
    for a in sub("ata_smart_attributes")["table"] as? [[String: Any]] ?? [] {
        if let id = a["id"] as? Int { attrs[id] = a }
    }
    func raw(_ id: Int) -> Int? { (attrs[id]?["raw"] as? [String: Any])?["value"] as? Int }

    let temperature = sub("temperature")["current"] as? Int
    // Seagate keeps the lifetime maximum in attribute 194's "worst" field; ignore implausible values.
    var hottest = attrs[194]?["worst"] as? Int
    if let h = hottest, let t = temperature, h < t || h > 90 { hottest = nil }

    return DriveReading(
        model: model,
        serial: j["serial_number"] as? String ?? "?",
        firmware: j["firmware_version"] as? String ?? "?",
        capacityBytes: (sub("user_capacity")["bytes"] as? NSNumber)?.int64Value,
        passed: sub("smart_status")["passed"] as? Bool,
        temperature: temperature,
        hottestRecorded: hottest,
        powerOnHours: sub("power_on_time")["hours"] as? Int,
        powerCycles: j["power_cycle_count"] as? Int,
        startStops: raw(4),
        loadCycles: raw(193),
        reallocated: raw(5),
        pending: raw(197),
        uncorrectable: raw(198),
        crcErrors: raw(199),
        readAt: Date())
}

struct Row {
    let disk: Disk
    let reading: DriveReading
    let idle: Bool  // not re-read this round because nothing has touched the disk
}

struct Snapshot {
    var rows: [Row] = []
    var raids: [RaidSet] = []
    var updated: Date?

    var severity: Severity {
        let drives = rows.map { $0.reading.severity }.max() ?? .ok
        return raids.contains { !$0.healthy } ? .crit : drives
    }
}

/// Holds the last reading per disk between polls. Call from one queue only.
final class Monitor {
    private var readings: [String: DriveReading] = [:]
    private var lastOps: [String: UInt64] = [:]

    /// `skipIdle` leaves a disk alone when it has had no I/O since its last reading, so
    /// polling never spins up a drive that has gone to sleep. `force` reads everything.
    func refresh(force: Bool, skipIdle: Bool) -> Snapshot {
        let (disks, raids) = discoverDisks()
        let present = Set(disks.map { $0.device })
        readings = readings.filter { present.contains($0.key) }
        lastOps = lastOps.filter { present.contains($0.key) }

        var rows: [Row] = []
        for disk in disks {
            let ops = ioOperations(disk.device)
            let untouched = ops != nil && ops == lastOps[disk.device] && readings[disk.device] != nil
            let skip = untouched && skipIdle && !force
            if !skip, let r = readSmart(disk.device) {
                readings[disk.device] = r
                lastOps[disk.device] = ops
            }
            if let r = readings[disk.device] { rows.append(Row(disk: disk, reading: r, idle: skip)) }
        }
        rows.sort { ($0.disk.role, $0.reading.serial) < ($1.disk.role, $1.reading.serial) }
        return Snapshot(rows: rows, raids: raids, updated: Date())
    }
}
