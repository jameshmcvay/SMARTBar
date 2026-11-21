import Foundation
import IOKit

struct Disk {
    let device: String  // e.g. "disk10"
    let role: String    // e.g. "RAID1 mirror · Big Store, Scratch"
}

struct RaidSet {
    let name: String
    let level: String
    let status: String
    let memberStatuses: [String]

    var healthy: Bool {
        status == "Online" && memberStatuses.allSatisfy { $0 == "Online" }
    }
}

/// Runs a tool and returns its exit status and stdout. Stdout is drained before
/// waiting so large outputs can't fill the pipe and deadlock.
func run(_ path: String, _ args: [String]) -> (status: Int32, out: Data) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return (-1, Data()) }
    let out = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, out)
}

private func diskutil(_ args: [String]) -> [String: Any] {
    let out = run("/usr/sbin/diskutil", args).out
    let obj = try? PropertyListSerialization.propertyList(from: out, options: [], format: nil)
    return obj as? [String: Any] ?? [:]
}

/// External physical disks, each labelled with the RAID set and/or APFS volumes it backs.
func discoverDisks() -> (disks: [Disk], raids: [RaidSet]) {
    let list = diskutil(["list", "-plist", "external", "physical"])
    let whole = list["WholeDisks"] as? [String] ?? []
    var slices: [String: [String]] = [:]
    for d in list["AllDisksAndPartitions"] as? [[String: Any]] ?? [] {
        guard let dev = d["DeviceIdentifier"] as? String else { continue }
        let parts = (d["Partitions"] as? [[String: Any]] ?? []).compactMap { $0["DeviceIdentifier"] as? String }
        slices[dev] = [dev] + parts
    }

    // APFS physical store -> names of the user-facing volumes in its container
    let hidden: Set<String> = ["Preboot", "Recovery", "VM", "Update", "xART", "Hardware"]
    var volumes: [String: [String]] = [:]
    for c in diskutil(["apfs", "list", "-plist"])["Containers"] as? [[String: Any]] ?? [] {
        let names = (c["Volumes"] as? [[String: Any]] ?? []).compactMap { v -> String? in
            let roles = v["Roles"] as? [String] ?? []
            return roles.contains(where: hidden.contains) ? nil : v["Name"] as? String
        }
        for s in c["PhysicalStores"] as? [[String: Any]] ?? [] {
            if let dev = s["DeviceIdentifier"] as? String { volumes[dev] = names }
        }
    }

    // RAID member slice -> label for its set
    var raids: [RaidSet] = []
    var raidLabel: [String: String] = [:]
    for s in diskutil(["appleRAID", "list", "-plist"])["AppleRAIDSets"] as? [[String: Any]] ?? [] {
        let name = s["Name"] as? String ?? "RAID"
        let level = s["Level"] as? String ?? ""
        let members = s["Members"] as? [[String: Any]] ?? []
        raids.append(RaidSet(name: name, level: level, status: s["Status"] as? String ?? "Unknown",
                             memberStatuses: members.map { $0["MemberStatus"] as? String ?? "Unknown" }))
        var label = level.isEmpty ? name : "\(name) \(level.lowercased())"
        if let bsd = s["BSD Name"] as? String, let vols = volumes[bsd], !vols.isEmpty {
            label += " · " + vols.joined(separator: ", ")
        }
        for m in members {
            if let bsd = m["BSD Name"] as? String { raidLabel[bsd] = label }
        }
    }

    let disks = whole.map { dev -> Disk in
        let parts = slices[dev] ?? [dev]
        if let label = parts.compactMap({ raidLabel[$0] }).first { return Disk(device: dev, role: label) }
        let vols = parts.flatMap { volumes[$0] ?? [] }
        return Disk(device: dev, role: vols.isEmpty ? "—" : vols.joined(separator: ", "))
    }
    return (disks, raids)
}

/// Total read + write operations the kernel has issued to a disk since it attached.
/// SMART queries don't count, so an unchanged value means nothing has touched the disk.
func ioOperations(_ device: String) -> UInt64? {
    guard let match = IOBSDNameMatching(kIOMainPortDefault, 0, device) else { return nil }
    var entry = IOServiceGetMatchingService(kIOMainPortDefault, match)
    // The counters live on the IOBlockStorageDriver a couple of levels above the IOMedia.
    for _ in 0..<4 where entry != 0 {
        let prop = IORegistryEntryCreateCFProperty(entry, "Statistics" as CFString, kCFAllocatorDefault, 0)
        if let stats = prop?.takeRetainedValue() as? [String: Any] {
            IOObjectRelease(entry)
            let reads = (stats["Operations (Read)"] as? NSNumber)?.uint64Value ?? 0
            let writes = (stats["Operations (Write)"] as? NSNumber)?.uint64Value ?? 0
            return reads + writes
        }
        var parent: io_registry_entry_t = 0
        let kr = IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent)
        IOObjectRelease(entry)
        entry = kr == KERN_SUCCESS ? parent : 0
    }
    if entry != 0 { IOObjectRelease(entry) }
    return nil
}
