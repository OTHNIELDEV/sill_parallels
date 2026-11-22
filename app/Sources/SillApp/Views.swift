#if canImport(SwiftUI) && os(macOS)
import AppKit
import SillCore
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 본 창

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selection) {
                Section("가상 머신") {
                    ForEach(model.vms) { vm in
                        VMRow(vm: vm).tag(vm.id)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
            .overlay {
                if model.vms.isEmpty {
                    Text("VM 이 없습니다")
                        .foregroundColor(.secondary)
                }
            }
            .toolbar {
                ToolbarItem {
                    Button {
                        model.showNewVM = true
                    } label: {
                        Label("새 VM", systemImage: "plus")
                    }
                    .help("새 Windows VM 만들기 (⌘N)")
                }
            }
        } detail: {
            if let vm = model.selected {
                VMDetailView(vm: vm)
            } else {
                WelcomeView()
            }
        }
        .sheet(isPresented: $model.showNewVM) {
            NewVMSheet().environmentObject(model)
        }
        .sheet(isPresented: $model.showSetup) {
            SetupSheet().environmentObject(model)
        }
    }
}

struct VMRow: View {
    let vm: VM

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "macwindow")
                .font(.title2)
                .foregroundColor(vm.isRunning ? .accentColor : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.config.name).font(.headline)
                HStack(spacing: 4) {
                    Circle()
                        .fill(vm.isRunning ? Color.green : Color.secondary.opacity(0.5))
                        .frame(width: 7, height: 7)
                    Text(vm.isRunning ? "실행 중" : "꺼짐")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 3)
    }
}

/// 첫 화면 — VM 이 없거나 고른 것이 없을 때
struct WelcomeView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "macwindow.on.rectangle")
                .font(.system(size: 64, weight: .thin))
                .foregroundColor(.accentColor)
            Text("Sill").font(.largeTitle.bold())
            Text("Mac 위의 Windows 창턱")
                .font(.title3)
                .foregroundColor(.secondary)
            if model.engineMissing {
                Label("엔진(sill)을 찾지 못했습니다. 앱을 다시 빌드하세요.", systemImage: "exclamationmark.triangle")
                    .foregroundColor(.orange)
            }
            HStack(spacing: 12) {
                Button {
                    model.showNewVM = true
                } label: {
                    Label("새 Windows VM 만들기", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Button {
                    model.showSetup = true
                } label: {
                    Label("준비 상태 점검", systemImage: "stethoscope")
                }
                .controlSize(.large)
            }
            .disabled(model.engineMissing)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - VM 상세

struct VMDetailView: View {
    @EnvironmentObject var model: AppModel
    let vm: VM
    @State private var confirmDelete = false
    @State private var snapshotTag = ""

    private var name: String { vm.config.name }
    private var busy: Bool { model.isBusy(name) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            actions
            HStack(alignment: .top, spacing: 16) {
                GroupBox("구성") { configGrid }
                GroupBox("스냅숏") { snapshotBox }
            }
            GroupBox("기록") { LogView() }
        }
        .padding(20)
        .confirmationDialog("\(name) 를 삭제할까요?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("디스크까지 영구 삭제", role: .destructive) {
                model.run(.delete(name: name), vm: name)
            }
        } message: {
            Text("Windows 와 그 안의 파일이 모두 지워지며 되돌릴 수 없습니다.")
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "macwindow")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(vm.isRunning ? .accentColor : .secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.title.bold())
                Text("\(vm.config.guestLabel) · \(vm.isRunning ? "실행 중" : "꺼짐")")
                    .foregroundColor(.secondary)
            }
            Spacer()
            if busy { ProgressView().controlSize(.small) }
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 10) {
            if vm.isRunning {
                Button {
                    model.run(.rdp(name: name), vm: name)
                } label: {
                    Label("Windows App 으로 연결", systemImage: "rectangle.connected.to.line.below")
                }
                .buttonStyle(.borderedProminent)
                .help("해상도 자동 · 클립보드 · Mac 폴더 공유 (Windows Pro · 암호 필요)")
                Button {
                    model.run(.stop(name: name, force: false), vm: name)
                } label: {
                    Label("종료", systemImage: "power")
                }
                Button(role: .destructive) {
                    model.run(.stop(name: name, force: true), vm: name)
                } label: {
                    Label("강제 종료", systemImage: "bolt.slash")
                }
            } else {
                Button {
                    model.startInWindow(name)
                } label: {
                    Label("시작", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isWindowed(name))
                Button {
                    model.run(.start(name: name, background: true), vm: name)
                } label: {
                    Label("창 없이 시작", systemImage: "play.rectangle")
                }
                .help("백그라운드로 켜고 Windows App 으로 연결합니다")
                Spacer()
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("삭제", systemImage: "trash")
                }
            }
        }
        .disabled(busy)
    }

    private var configGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            row("CPU", "\(vm.config.cpus)개")
            row("메모리", "\(vm.config.ramGB) GB")
            row("디스크", "\(ByteCountFormatter.string(fromByteCount: vm.diskUsedBytes, countStyle: .file)) 사용 / \(vm.config.diskGB) GB")
            row("RDP", "127.0.0.1:\(vm.config.rdpPort)")
            row("설치 ISO", (vm.config.installISO as NSString).lastPathComponent)
            row("드라이버", vm.config.virtioISO.isEmpty ? "없음" : (vm.config.virtioISO as NSString).lastPathComponent)
            row("만든 날", vm.config.created)
            GridRow {
                Text("폴더").foregroundColor(.secondary)
                Button("Finder 에서 보기") {
                    NSWorkspace.shared.activateFileViewerSelecting([vm.bundleURL])
                }
                .buttonStyle(.link)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(6)
    }

    private func row(_ key: String, _ value: String) -> some View {
        GridRow {
            Text(key).foregroundColor(.secondary)
            Text(value).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
        }
    }

    private var snapshotBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("이름 (비우면 날짜)", text: $snapshotTag)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("저장") {
                    model.run(.snapshot(name: name, action: .save, tag: snapshotTag), vm: name)
                }
                Button("되돌리기") {
                    model.run(.snapshot(name: name, action: .restore, tag: snapshotTag), vm: name)
                }
                .disabled(snapshotTag.isEmpty)
                Button("목록") {
                    model.run(.snapshot(name: name, action: .list, tag: ""), vm: name)
                }
            }
            Text(vm.isRunning ? "VM 을 끈 뒤에 쓸 수 있습니다" : "디스크와 UEFI 상태를 함께 저장합니다")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .disabled(vm.isRunning || busy)
        .frame(width: 260, alignment: .leading)
        .padding(6)
    }
}

/// 엔진이 남긴 출력
struct LogView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(model.log.enumerated()), id: \.offset) { item in
                            Text(item.element)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(item.element.hasPrefix("$ ") ? .accentColor : .primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(item.offset)
                        }
                    }
                    .padding(6)
                }
                .onChange(of: model.log.count) { count in
                    if count > 0 { proxy.scrollTo(count - 1, anchor: .bottom) }
                }
            }
            .frame(minHeight: 120)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            Button("기록 지우기") { model.clearLog() }
                .buttonStyle(.link)
                .font(.caption)
        }
    }
}

// MARK: - 새 VM

struct NewVMSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var req = CreateRequest()
    @State private var autoCPU = true
    @State private var cpus = 4
    @State private var showPicker = false
    @State private var pickTarget = PickTarget.iso
    @State private var creating = false
    @State private var failed = false

    enum PickTarget { case iso, virtio }

    private var request: CreateRequest {
        var r = req
        r.cpus = autoCPU ? nil : cpus
        return r
    }

    private var problems: [String] { request.problems() }

    private static let isoType = UTType(filenameExtension: "iso") ?? .diskImage

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("이름", text: $req.name, prompt: Text("win11 (영문 · 숫자)"))
                    fileRow("Windows 설치 ISO", path: req.isoPath) { pick(.iso) }
                    fileRow("virtio 드라이버 ISO", path: req.virtioPath, optional: true) { pick(.virtio) }
                } header: {
                    Text("설치 매체")
                } footer: {
                    Text("Apple Silicon 은 Windows 11 ARM64 ISO 를 쓰세요. virtio 드라이버가 없으면 설치 뒤 인터넷이 안 됩니다(준비 상태 점검 → 드라이버 받기).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Section("자원") {
                    Toggle("CPU 자동 (성능 코어 수, 최대 8)", isOn: $autoCPU)
                    if !autoCPU {
                        Stepper("CPU \(cpus)개", value: $cpus, in: 1...32)
                    }
                    Stepper("메모리 \(req.ramGB) GB", value: $req.ramGB, in: CreateRequest.minRAMGB...128, step: 2)
                    Stepper("디스크 \(req.diskGB) GB (쓴 만큼만 차지)", value: $req.diskGB, in: CreateRequest.minDiskGB...2048, step: 16)
                }
                Section("자동 설치") {
                    Toggle("요건 검사 우회 · 드라이버 · RDP 자동 설정", isOn: $req.unattend)
                    TextField("로컬 계정 이름 (선택)", text: $req.user, prompt: Text("me"))
                        .disabled(!req.unattend)
                }
                if creating || failed {
                    Section("기록") { LogView().frame(height: 140) }
                }
            }
            .formStyle(.grouped)

            HStack {
                if let first = problems.first {
                    Label(first, systemImage: "info.circle")
                        .font(.callout)
                        .foregroundColor(.secondary)
                } else if failed {
                    Label("만들지 못했습니다 — 기록을 확인하세요", systemImage: "xmark.octagon")
                        .foregroundColor(.red)
                }
                Spacer()
                Button("취소") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(creating ? "만드는 중…" : "만들기") { create() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(creating || !problems.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 560, height: creating || failed ? 680 : 560)
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [Self.isoType]) { result in
            guard case .success(let url) = result else { return }
            switch pickTarget {
            case .iso: req.isoPath = url.path
            case .virtio: req.virtioPath = url.path
            }
        }
        .onAppear {
            let virtio = model.store.home.appendingPathComponent("virtio-win.iso").path
            if req.virtioPath.isEmpty, FileManager.default.fileExists(atPath: virtio) { req.virtioPath = virtio }
        }
    }

    private func fileRow(_ title: String, path: String, optional: Bool = false, choose: @escaping () -> Void) -> some View {
        LabeledContent(title) {
            HStack {
                Text(path.isEmpty ? (optional ? "선택 안 함" : "고르지 않음") : (path as NSString).lastPathComponent)
                    .foregroundColor(path.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("고르기…", action: choose)
            }
        }
    }

    private func pick(_ target: PickTarget) {
        pickTarget = target
        showPicker = true
    }

    private func create() {
        let r = request
        creating = true
        failed = false
        Task {
            let code = await model.perform(.create(r))
            creating = false
            if code == 0 {
                model.selection = r.name
                dismiss()
            } else {
                failed = true
            }
        }
    }
}

// MARK: - 준비 상태

struct SetupSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("준비 상태 점검").font(.title2.bold())
            Text("Windows VM 을 돌리려면 QEMU 와 swtpm(가상 TPM)이 필요합니다. Homebrew 로 설치합니다.")
                .foregroundColor(.secondary)
            HStack {
                Button("다시 점검") { model.run(.doctor) }
                Button("필요한 도구 설치 (brew)") { model.run(.deps) }
                    .help("brew install qemu swtpm — Homebrew 가 먼저 있어야 합니다")
                Button("virtio 드라이버 받기") { model.run(.drivers) }
                    .help("Apple Silicon 에서 설치 뒤 인터넷이 되게 하는 드라이버 ISO")
                Spacer()
                if model.globalBusy { ProgressView().controlSize(.small) }
            }
            .disabled(model.globalBusy)
            LogView()
            HStack {
                Spacer()
                Button("닫기") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 640, height: 480)
        .onAppear { model.run(.doctor) }
    }
}

// MARK: - 메뉴 막대

struct MenuBarContent: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if model.vms.isEmpty {
            Text("VM 이 없습니다")
        }
        ForEach(model.vms) { vm in
            Menu("\(vm.isRunning ? "●" : "○") \(vm.config.name)") {
                if vm.isRunning {
                    Button("Windows App 으로 연결") { model.run(.rdp(name: vm.config.name), vm: vm.config.name) }
                    Button("종료") { model.run(.stop(name: vm.config.name, force: false), vm: vm.config.name) }
                } else {
                    Button("시작") { model.startInWindow(vm.config.name) }
                    Button("창 없이 시작") { model.run(.start(name: vm.config.name, background: true), vm: vm.config.name) }
                }
            }
        }
        Divider()
        Button("Sill 열기") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("새 Windows VM…") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
            model.showNewVM = true
        }
        Divider()
        Button("Sill 끝내기") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
#endif
