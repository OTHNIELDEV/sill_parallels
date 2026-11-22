import Foundation

/// 「새 VM」 입력 — 검사 규칙은 엔진(`sill create`)과 같다. 엔진도 다시 검사하므로 여기는 화면 안내용이다.
public struct CreateRequest: Equatable, Sendable {
    public var name = ""
    public var isoPath = ""
    public var virtioPath = ""
    /// nil = 엔진이 성능 코어 수로 정한다
    public var cpus: Int? = nil
    public var ramGB = 8
    public var diskGB = 80
    public var user = ""
    public var unattend = true

    public init() {}

    public static let minRAMGB = 4
    public static let minDiskGB = 64

    /// 영문 · 숫자 · . _ - 만, 점으로 시작하지 않음
    public static func isValidName(_ s: String) -> Bool {
        guard !s.isEmpty, !s.hasPrefix(".") else { return false }
        return s.unicodeScalars.allSatisfy { c in
            ("a"..."z").contains(c) || ("A"..."Z").contains(c) || ("0"..."9").contains(c) || c == "." || c == "_" || c == "-"
        }
    }

    /// 지금 입력의 문제 목록(비면 만들 수 있다)
    public func problems(fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> [String] {
        var out: [String] = []
        if name.isEmpty { out.append("이름을 입력하세요") }
        else if !Self.isValidName(name) { out.append("이름은 영문 · 숫자 · . _ - 만 쓸 수 있습니다") }
        if isoPath.isEmpty { out.append("Windows 설치 ISO 를 고르세요") }
        else if !fileExists(isoPath) { out.append("설치 ISO 파일이 없습니다") }
        if !virtioPath.isEmpty && !fileExists(virtioPath) { out.append("virtio 드라이버 ISO 파일이 없습니다") }
        if let cpus, cpus < 1 { out.append("CPU 는 1개 이상") }
        if ramGB < Self.minRAMGB { out.append("Windows 11 은 RAM \(Self.minRAMGB)GB 이상이 필요합니다") }
        if diskGB < Self.minDiskGB { out.append("Windows 11 은 디스크 \(Self.minDiskGB)GB 이상이 필요합니다") }
        if !user.isEmpty && !Self.isValidName(user) { out.append("계정 이름은 영문 · 숫자 · . _ - 만") }
        return out
    }

    public var arguments: [String] {
        var a = ["create", name, "--iso", isoPath, "--ram", String(ramGB), "--disk", String(diskGB)]
        if let cpus { a += ["--cpus", String(cpus)] }
        if !virtioPath.isEmpty { a += ["--virtio", virtioPath] }
        if unattend {
            if !user.isEmpty { a += ["--user", user] }
        } else {
            a.append("--no-unattend")
        }
        return a
    }
}

/// 앱이 엔진에 시키는 일 — 엔진 명령 한 줄과 1:1
public enum SillCommand: Equatable, Sendable {
    case version
    case doctor
    case deps
    case drivers
    case list
    case create(CreateRequest)
    case start(name: String, background: Bool)
    case stop(name: String, force: Bool)
    case rdp(name: String)
    case snapshot(name: String, action: SnapshotAction, tag: String)
    case set(name: String, key: String, value: String)
    case delete(name: String)

    public enum SnapshotAction: String, Sendable { case list, save, restore, delete }

    public var arguments: [String] {
        switch self {
        case .version: return ["--version"]
        case .doctor: return ["doctor"]
        case .deps: return ["deps"]
        case .drivers: return ["drivers"]
        case .list: return ["list"]
        case .create(let r): return r.arguments
        case .start(let n, let bg): return bg ? ["start", n, "--background"] : ["start", n]
        case .stop(let n, let force): return force ? ["stop", n, "--force"] : ["stop", n]
        case .rdp(let n): return ["rdp", n]
        case .snapshot(let n, let action, let tag):
            return tag.isEmpty || action == .list ? ["snapshot", n, action.rawValue] : ["snapshot", n, action.rawValue, tag]
        case .set(let n, let k, let v): return ["set", n, k, v]
        case .delete(let n): return ["delete", n]
        }
    }

    /// 엔진이 표준 입력으로 묻는 확인 — 삭제는 이름을 다시 입력해야 한다(화면에서 이미 확인받았다).
    public var stdinText: String? {
        if case .delete(let n) = self { return n + "\n" }
        return nil
    }

    /// 화면에 보일 명령 줄
    public var displayLine: String {
        "$ sill " + arguments.map { $0.contains(" ") ? "'\($0)'" : $0 }.joined(separator: " ")
    }
}
