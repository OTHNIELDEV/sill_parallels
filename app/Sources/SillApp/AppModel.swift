#if canImport(SwiftUI) && os(macOS)
import Foundation
import SillCore
import SwiftUI

/// 앱 상태 — VM 목록은 2초마다 디스크에서 다시 읽는다(엔진 · 명령행에서 바꾼 것도 바로 보인다).
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var vms: [VM] = []
    @Published var selection: VM.ID?
    @Published private(set) var log: [String] = []
    /// 명령이 도는 중인 VM 이름(버튼을 잠근다)
    @Published private(set) var busy: Set<String> = []
    @Published private(set) var globalBusy = false
    @Published var showNewVM = false
    @Published var showSetup = false

    let store = VMStore()
    let runner: SillRunner?
    /// 창으로 띄운 VM — 창을 닫으면 프로세스가 끝나고 여기서 빠진다
    private var windowed: [String: Process] = [:]
    private var timer: Timer?

    static let logLimit = 800

    init() {
        if let engine = EngineLocator.locate() {
            runner = SillRunner(engine: engine, home: store.home)
        } else {
            runner = nil
        }
        refresh()
        if runner == nil { appendLog("엔진(sill)을 찾지 못했습니다 — 앱 묶음이 깨졌거나 SILL_ENGINE 이 필요합니다") }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    var engineMissing: Bool { runner == nil }
    var selected: VM? { vms.first { $0.id == selection } }
    var runningCount: Int { vms.filter(\.isRunning).count }

    func refresh() {
        let list = store.list()
        if list != vms { vms = list }
        if let sel = selection, !vms.contains(where: { $0.id == sel }) { selection = nil }
        if selection == nil { selection = vms.first?.id }
    }

    func appendLog(_ line: String) {
        log.append(line)
        if log.count > Self.logLimit { log.removeFirst(log.count - Self.logLimit) }
    }

    func clearLog() { log.removeAll() }

    func isBusy(_ name: String) -> Bool { busy.contains(name) }

    /// 엔진 명령을 돌리고 끝날 때까지 기다린다
    @discardableResult
    func perform(_ command: SillCommand, vm: String? = nil) async -> Int32 {
        guard let runner else {
            appendLog("엔진(sill)을 찾지 못했습니다")
            return -1
        }
        if let vm { busy.insert(vm) } else { globalBusy = true }
        appendLog(command.displayLine)
        let code = await runner.run(command) { [weak self] line in
            Task { @MainActor in self?.appendLog(line) }
        }
        if let vm { busy.remove(vm) } else { globalBusy = false }
        if code != 0 { appendLog("✗ 종료 코드 \(code)") }
        refresh()
        return code
    }

    func run(_ command: SillCommand, vm: String? = nil) {
        Task { await perform(command, vm: vm) }
    }

    /// 창으로 시작 — QEMU 창이 따로 뜨고, 창을 닫으면 VM 이 꺼진다
    func startInWindow(_ name: String) {
        guard let runner else { return }
        guard windowed[name] == nil else { return }
        let command = SillCommand.start(name: name, background: false)
        appendLog(command.displayLine)
        do {
            let process = try runner.launch(command, onLine: { [weak self] line in
                Task { @MainActor in self?.appendLog(line) }
            }, onExit: { [weak self] code in
                Task { @MainActor in
                    self?.windowed[name] = nil
                    self?.appendLog("■ \(name) 창이 닫혔습니다 (코드 \(code))")
                    self?.refresh()
                }
            })
            windowed[name] = process
        } catch {
            appendLog("시작하지 못했습니다: \(error.localizedDescription)")
        }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            refresh()
        }
    }

    func isWindowed(_ name: String) -> Bool { windowed[name] != nil }
}
#endif
