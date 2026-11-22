import Foundation

/// 엔진 스크립트(`sill`) 찾기
public enum EngineLocator {
    /// 순서: SILL_ENGINE → 앱 묶음 Resources/engine/sill → 현재 폴더 · 그 위(개발 중 `swift run`)
    public static func locate(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        currentDirectory: String = FileManager.default.currentDirectoryPath
    ) -> URL? {
        var candidates: [URL] = []
        if let e = environment["SILL_ENGINE"], !e.isEmpty { candidates.append(URL(fileURLWithPath: e)) }
        if let r = bundle.resourceURL { candidates.append(r.appendingPathComponent("engine/sill")) }
        let cwd = URL(fileURLWithPath: currentDirectory, isDirectory: true)
        candidates.append(cwd.appendingPathComponent("sill"))
        candidates.append(cwd.deletingLastPathComponent().appendingPathComponent("sill"))
        return candidates.first(where: isEngineFile)
    }

    static func isEngineFile(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && !isDir.boolValue
    }
}

/// 엔진 출력을 줄 단위로 잘라 넘긴다(색 코드 제거). 여러 스레드에서 들어와도 안전하다.
final class LineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = Data()
    private let onLine: @Sendable (String) -> Void

    init(onLine: @escaping @Sendable (String) -> Void) { self.onLine = onLine }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        pending.append(data)
        var lines: [String] = []
        while let nl = pending.firstIndex(of: 0x0A) {
            let chunk = pending.subdata(in: pending.startIndex..<nl)
            pending.removeSubrange(pending.startIndex...nl)
            lines.append(String(decoding: chunk, as: UTF8.self))
        }
        lock.unlock()
        lines.forEach { onLine(ANSI.strip($0)) }
    }

    func flush() {
        lock.lock()
        let rest = pending
        pending = Data()
        lock.unlock()
        if !rest.isEmpty { onLine(ANSI.strip(String(decoding: rest, as: UTF8.self))) }
    }
}

public enum ANSI {
    /// ESC [ … 문자 꼴의 색 코드를 지운다
    public static func strip(_ s: String) -> String {
        guard s.contains("\u{1B}") else { return s }
        var out = ""
        var it = s.makeIterator()
        while let c = it.next() {
            if c == "\u{1B}" {
                guard let next = it.next() else { break }
                if next == "[" {
                    while let d = it.next(), !(d.isLetter) {}
                }
                continue
            }
            out.append(c)
        }
        return out
    }
}

/// 엔진을 실행한다. 앱은 QEMU 를 직접 다루지 않고 늘 이 길로만 간다(검증된 엔진 하나를 CLI 와 앱이 함께 쓴다).
public final class SillRunner: @unchecked Sendable {
    public let engine: URL
    public let environment: [String: String]
    /// 엔진이 끝난 뒤 남은 출력을 받는 시간
    static let drainDelay: TimeInterval = 0.3

    public init(engine: URL, home: URL? = nil, base: [String: String] = ProcessInfo.processInfo.environment) {
        self.engine = engine
        var env = SillRunner.guiEnvironment(base: base)
        if let home { env["SILL_HOME"] = home.path }
        self.environment = env
    }

    /// Finder 에서 연 앱은 PATH 가 짧다 — Homebrew(qemu · swtpm) 경로를 앞에 붙인다.
    public static func guiEnvironment(base: [String: String]) -> [String: String] {
        var env = base
        let extra = ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        let current = (base["PATH"] ?? "").split(separator: ":").map(String.init)
        var seen = Set<String>()
        env["PATH"] = (extra + current).filter { seen.insert($0).inserted }.joined(separator: ":")
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        return env
    }

    /// 끝날 때까지 기다린다. 반환값 = 종료 코드
    public func run(_ command: SillCommand, onLine: @escaping @Sendable (String) -> Void) async -> Int32 {
        await withCheckedContinuation { (cont: CheckedContinuation<Int32, Never>) in
            do {
                _ = try launch(command, onLine: onLine) { code in cont.resume(returning: code) }
            } catch {
                onLine("엔진을 실행하지 못했습니다: \(error.localizedDescription)")
                cont.resume(returning: -1)
            }
        }
    }

    /// 기다리지 않고 시작한다(창으로 띄운 VM 처럼 오래 도는 명령). onExit 는 한 번 불린다.
    @discardableResult
    public func launch(
        _ command: SillCommand,
        onLine: @escaping @Sendable (String) -> Void,
        onExit: @escaping @Sendable (Int32) -> Void
    ) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [engine.path] + command.arguments
        process.environment = environment

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        let input: Pipe? = command.stdinText == nil ? nil : Pipe()
        process.standardInput = input ?? FileHandle.nullDevice

        let buffer = LineBuffer(onLine: onLine)
        let reader = output.fileHandleForReading
        reader.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil } else { buffer.append(data) }
        }
        process.terminationHandler = { proc in
            // 관이 닫히기를 기다리지 않는다 — 엔진이 띄운 백그라운드 프로세스(QEMU · swtpm)가 관을 물려받으면
            // 영원히 닫히지 않는다. 끝나기 전에 쓴 출력은 이미 관에 있으므로 잠깐만 더 받고 마무리한다.
            let code = proc.terminationStatus
            DispatchQueue.global().asyncAfter(deadline: .now() + SillRunner.drainDelay) {
                reader.readabilityHandler = nil
                buffer.flush()
                onExit(code)
            }
        }
        try process.run()
        if let input, let text = command.stdinText {
            input.fileHandleForWriting.write(Data(text.utf8))
            try? input.fileHandleForWriting.close()
        }
        return process
    }
}
