import AppKit

// `SMARTBar --dump` prints one reading of every drive to the terminal and exits.
if CommandLine.arguments.contains("--dump") {
    let snap = Monitor().refresh(force: true, skipIdle: false)
    for row in snap.rows {
        let r = row.reading
        func n(_ v: Int?) -> String { v.map(String.init) ?? "–" }
        print("\(row.disk.device)\t\(r.serial)\t\(n(r.temperature))°C\t\(n(r.powerOnHours)) h\t"
            + "realloc \(n(r.reallocated)) pending \(n(r.pending)) uncorr \(n(r.uncorrectable)) crc \(n(r.crcErrors))\t"
            + "io-ops \(ioOperations(row.disk.device).map(String.init) ?? "–")\t\(r.severity)\t\(row.disk.role)")
        for (_, problem) in r.problems { print("\t! \(problem)") }
    }
    for raid in snap.raids {
        print("\(raid.name) \(raid.level): \(raid.status), members \(raid.memberStatuses.joined(separator: "/"))")
    }
    if smartctlPath == nil { print("smartctl not found") }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
