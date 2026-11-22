import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// VM 한 대 — 설정 + 지금 상태
public struct VM: Identifiable, Equatable, Sendable {
    public var id: String { config.name }
    public let config: VMConfig
    public let bundleURL: URL
    public let isRunning: Bool
    /// 디스크 이미지(qcow2)가 Mac 에서 실제로 차지하는 크기
    public let diskUsedBytes: Int64

    public init(config: VMConfig, bundleURL: URL, isRunning: Bool, diskUsedBytes: Int64) {
        self.config = config
        self.bundleURL = bundleURL
        self.isRunning = isRunning
        self.diskUsedBytes = diskUsedBytes
    }
}

/// `~/Sill/<이름>.sill/` 폴더들을 읽어 VM 목록을 만든다. 쓰기는 하지 않는다(엔진의 일).
public struct VMStore: Sendable {
    public let home: URL

    public init(home: URL = VMStore.defaultHome) {
        self.home = home
    }

    /// 엔진과 같은 규칙: SILL_HOME 이 있으면 그것, 없으면 ~/Sill
    public static var defaultHome: URL {
        if let h = ProcessInfo.processInfo.environment["SILL_HOME"], !h.isEmpty {
            return URL(fileURLWithPath: h, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Sill", isDirectory: true)
    }

    public func list() -> [VM] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: home, includingPropertiesForKeys: nil) else { return [] }
        return items
            .filter { $0.pathExtension == "sill" }
            .compactMap(load(bundle:))
            .sorted { $0.config.name.localizedStandardCompare($1.config.name) == .orderedAscending }
    }

    public func load(bundle: URL) -> VM? {
        let configURL = bundle.appendingPathComponent("config.env")
        guard let text = try? String(contentsOf: configURL, encoding: .utf8),
              let config = VMConfig(env: ConfigEnv.parse(text)) else { return nil }
        let disk = bundle.appendingPathComponent("disk.qcow2")
        let size = (try? FileManager.default.attributesOfItem(atPath: disk.path)[.size] as? NSNumber)?.int64Value ?? 0
        return VM(config: config, bundleURL: bundle, isRunning: VMStore.isRunning(bundle: bundle), diskUsedBytes: size)
    }

    /// qemu.pid 의 프로세스가 살아 있으면 실행 중
    public static func isRunning(bundle: URL) -> Bool {
        let pidURL = bundle.appendingPathComponent("qemu.pid")
        guard let text = try? String(contentsOf: pidURL, encoding: .utf8),
              let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }
}
