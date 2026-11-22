import Foundation

/// sill 엔진이 VM 마다 쓰는 `config.env`(`KEY='값'` 한 줄씩)를 읽는다.
public enum ConfigEnv {
    public static func parse(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq])
            guard !key.isEmpty, key.allSatisfy({ $0.isUppercase || $0.isNumber || $0 == "_" }) else { continue }
            var value = String(line[line.index(after: eq)...])
            if value.count >= 2,
               (value.hasPrefix("'") && value.hasSuffix("'")) || (value.hasPrefix("\"") && value.hasSuffix("\"")) {
                value = String(value.dropFirst().dropLast())
            }
            out[key] = value
        }
        return out
    }
}

/// VM 한 대의 설정 — 원본은 엔진의 config.env 다(앱은 읽기만 하고, 바꿀 때는 `sill set` 을 부른다).
public struct VMConfig: Equatable, Sendable {
    public var name: String
    public var arch: String
    public var cpus: Int
    public var ramGB: Int
    public var diskGB: Int
    public var rdpPort: Int
    public var installISO: String
    public var virtioISO: String
    public var unattend: Bool
    public var audio: Bool
    public var created: String

    public init?(env: [String: String]) {
        guard let name = env["NAME"], CreateRequest.isValidName(name) else { return nil }
        self.name = name
        arch = env["ARCH"] ?? ""
        cpus = Int(env["CPUS"] ?? "") ?? 0
        ramGB = Int(env["RAM_GB"] ?? "") ?? 0
        diskGB = Int(env["DISK_GB"] ?? "") ?? 0
        rdpPort = Int(env["RDP_PORT"] ?? "") ?? 0
        installISO = env["INSTALL_ISO"] ?? ""
        virtioISO = env["VIRTIO_ISO"] ?? ""
        unattend = env["UNATTEND"] == "1"
        audio = (env["AUDIO"] ?? "1") == "1"
        created = env["CREATED"] ?? ""
    }

    /// 화면에 보일 게스트 종류
    public var guestLabel: String {
        arch == "aarch64" ? "Windows 11 ARM64" : "Windows 10/11 x64"
    }
}
