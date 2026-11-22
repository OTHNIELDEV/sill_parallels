import Foundation
import XCTest
@testable import SillCore

final class ConfigTests: XCTestCase {
    func testParseConfigEnv() {
        let env = ConfigEnv.parse("""
        # 주석
        NAME='win11'
        CPUS='4'
        RDP_PORT=33891
        INSTALL_ISO='/Users/me/Win 11.iso'
        bad line
        lower='x'
        """)
        XCTAssertEqual(env["NAME"], "win11")
        XCTAssertEqual(env["CPUS"], "4")
        XCTAssertEqual(env["RDP_PORT"], "33891")
        XCTAssertEqual(env["INSTALL_ISO"], "/Users/me/Win 11.iso")
        XCTAssertNil(env["lower"])
    }

    func testVMConfig() throws {
        let c = try XCTUnwrap(VMConfig(env: ["NAME": "w", "ARCH": "aarch64", "CPUS": "6", "RAM_GB": "8",
                                            "DISK_GB": "80", "RDP_PORT": "33890", "UNATTEND": "1"]))
        XCTAssertEqual(c.cpus, 6)
        XCTAssertEqual(c.guestLabel, "Windows 11 ARM64")
        XCTAssertTrue(c.unattend)
        XCTAssertTrue(c.audio, "AUDIO 가 없으면 켜짐")
        XCTAssertNil(VMConfig(env: ["NAME": "../x"]), "이상한 이름은 버린다")
    }
}

final class CommandTests: XCTestCase {
    func testNameRules() {
        XCTAssertTrue(CreateRequest.isValidName("Win11_ARM-2.0"))
        XCTAssertFalse(CreateRequest.isValidName(""))
        XCTAssertFalse(CreateRequest.isValidName(".hidden"))
        XCTAssertFalse(CreateRequest.isValidName("윈도우"))
        XCTAssertFalse(CreateRequest.isValidName("a b"))
    }

    func testCreateProblemsAndArguments() {
        var r = CreateRequest()
        XCTAssertEqual(r.problems(fileExists: { _ in true }).count, 2, "이름 · ISO")
        r.name = "win11"; r.isoPath = "/x/win.iso"; r.ramGB = 2; r.diskGB = 32
        let p = r.problems(fileExists: { _ in true })
        XCTAssertTrue(p.contains { $0.contains("RAM") })
        XCTAssertTrue(p.contains { $0.contains("디스크") })
        r.ramGB = 8; r.diskGB = 80; r.user = "me"; r.virtioPath = "/x/virtio.iso"; r.cpus = 4
        XCTAssertEqual(r.problems(fileExists: { _ in true }), [])
        XCTAssertEqual(r.problems(fileExists: { $0 != "/x/virtio.iso" }), ["virtio 드라이버 ISO 파일이 없습니다"])
        XCTAssertEqual(r.arguments, ["create", "win11", "--iso", "/x/win.iso", "--ram", "8", "--disk", "80",
                                     "--cpus", "4", "--virtio", "/x/virtio.iso", "--user", "me"])
        r.unattend = false
        XCTAssertEqual(r.arguments.last, "--no-unattend")
        XCTAssertFalse(r.arguments.contains("--user"), "자동 설치를 끄면 계정도 넘기지 않는다")
    }

    func testCommandArguments() {
        XCTAssertEqual(SillCommand.start(name: "w", background: true).arguments, ["start", "w", "--background"])
        XCTAssertEqual(SillCommand.stop(name: "w", force: true).arguments, ["stop", "w", "--force"])
        XCTAssertEqual(SillCommand.snapshot(name: "w", action: .save, tag: "").arguments, ["snapshot", "w", "save"])
        XCTAssertEqual(SillCommand.snapshot(name: "w", action: .list, tag: "x").arguments, ["snapshot", "w", "list"])
        XCTAssertEqual(SillCommand.delete(name: "w").stdinText, "w\n")
        XCTAssertNil(SillCommand.stop(name: "w", force: false).stdinText)
    }

    func testANSIStrip() {
        XCTAssertEqual(ANSI.strip("\u{1B}[32m✓\u{1B}[0m 준비 완료"), "✓ 준비 완료")
        XCTAssertEqual(ANSI.strip("plain"), "plain")
    }

    func testGuiPathPutsHomebrewFirst() {
        let env = SillRunner.guiEnvironment(base: ["PATH": "/usr/bin:/custom"])
        XCTAssertTrue(env["PATH"]!.hasPrefix("/opt/homebrew/bin:"))
        XCTAssertTrue(env["PATH"]!.hasSuffix(":/custom"))
        XCTAssertEqual(env["PATH"]!.components(separatedBy: "/usr/bin").count, 2, "중복 없음")
    }
}

/// 실제 엔진(레포 루트의 sill)을 돌리는 시험
final class EngineIntegrationTests: XCTestCase {
    var home: URL!
    var runner: SillRunner!
    let lines = Lines()

    final class Lines: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func add(_ s: String) { lock.lock(); items.append(s); lock.unlock() }
        var all: [String] { lock.lock(); defer { lock.unlock() }; return items }
        var text: String { all.joined(separator: "\n") }
    }

    static var engineURL: URL {
        // Tests/SillCoreTests/이 파일 → app → 레포 루트
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("sill")
    }

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("sill-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        var base = ProcessInfo.processInfo.environment
        base["SILL_ACCEL"] = base["SILL_ACCEL"] ?? "tcg"
        runner = SillRunner(engine: Self.engineURL, home: home, base: base)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private func run(_ c: SillCommand) async -> Int32 {
        let sink = lines
        return await runner.run(c) { sink.add($0) }
    }

    /// 시험 준비용 명령 — waitUntilExit 는 Linux 의 async 시험에서 멈출 수 있어 종료 콜백으로 기다린다
    private func exec(_ args: [String]) async throws -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = args
        p.environment = runner.environment
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        return try await withCheckedThrowingContinuation { cont in
            p.terminationHandler = { cont.resume(returning: $0.terminationStatus) }
            do { try p.run() } catch { cont.resume(throwing: error) }
        }
    }

    private func needTools(_ tools: [String]) throws {
        for t in tools {
            let ok = runner.environment["PATH"]!.split(separator: ":").contains {
                FileManager.default.isExecutableFile(atPath: "\($0)/\(t)")
            }
            if !ok { throw XCTSkip("\(t) 없음") }
        }
    }

    func testLocatorFindsEngine() {
        let url = EngineLocator.locate(bundle: Bundle(for: Self.self), environment: [:],
                                       currentDirectory: Self.engineURL.deletingLastPathComponent().appendingPathComponent("app").path)
        XCTAssertEqual(url?.standardizedFileURL, Self.engineURL.standardizedFileURL)
        XCTAssertNil(EngineLocator.locate(bundle: Bundle(for: Self.self), environment: [:], currentDirectory: "/"))
    }

    func testVersionAndEmptyList() async {
        let code = await run(.version)
        XCTAssertEqual(code, 0)
        XCTAssertTrue(lines.text.contains("sill "), lines.text)
        let listed = await run(.list)
        XCTAssertEqual(listed, 0)
        XCTAssertTrue(lines.text.contains("VM 이 없습니다"))
        XCTAssertEqual(VMStore(home: home).list(), [])
    }

    func testEngineRejectsBadInput() async {
        let code = await run(.create(CreateRequest()))
        XCTAssertNotEqual(code, 0)
    }

    /// 만들기 → 목록 → (가능하면) 백그라운드 시작 · 종료 → 삭제 를 앱과 같은 길로
    func testCreateStartStopDelete() async throws {
        try needTools(["qemu-img"])
        let isoTool: [String]
        if (try? needTools(["hdiutil"])) != nil { isoTool = ["hdiutil", "makehybrid", "-quiet", "-iso", "-joliet", "-o"] }
        else if (try? needTools(["xorriso"])) != nil { isoTool = ["xorriso", "-as", "mkisofs", "-quiet", "-J", "-o"] }
        else { throw XCTSkip("ISO 생성기 없음") }
        let iso = home.appendingPathComponent("fake.iso")
        let src = home.appendingPathComponent("isosrc")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try "x".write(to: src.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let made = try await exec(isoTool + [iso.path, src.path])
        XCTAssertEqual(made, 0, "가짜 ISO 만들기")

        var req = CreateRequest()
        req.name = "itest"; req.isoPath = iso.path; req.ramGB = 4; req.diskGB = 64; req.user = "tester"
        XCTAssertEqual(req.problems(), [])
        let created = await run(.create(req))
        XCTAssertEqual(created, 0, lines.text)

        let store = VMStore(home: home)
        let vm = try XCTUnwrap(store.list().first)
        XCTAssertEqual(vm.config.name, "itest")
        XCTAssertEqual(vm.config.ramGB, 4)
        XCTAssertEqual(vm.config.installISO, iso.path)
        XCTAssertFalse(vm.isRunning)
        XCTAssertGreaterThan(vm.diskUsedBytes, 0)

        let canBoot = (try? needTools(["swtpm", "qemu-system-\(vm.config.arch)"])) != nil
        if canBoot {
            // 백그라운드 시작은 엔진이 QEMU 를 떼어 놓고 끝나야 한다 — 출력 관이 열린 채면 여기서 영원히 기다린다.
            let started = await run(.start(name: "itest", background: true))
            XCTAssertEqual(started, 0, lines.text)
            XCTAssertTrue(store.list().first?.isRunning ?? false, "실행 중으로 보여야 한다")
            let stopped = await run(.stop(name: "itest", force: true))
            XCTAssertEqual(stopped, 0, lines.text)
            try await Task.sleep(nanoseconds: 1_000_000_000)
            XCTAssertFalse(store.list().first?.isRunning ?? true)
        }

        let deleted = await run(.delete(name: "itest"))
        XCTAssertEqual(deleted, 0, lines.text)
        XCTAssertEqual(store.list(), [])
    }
}
