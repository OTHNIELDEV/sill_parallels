#if canImport(SwiftUI) && os(macOS)
import AppKit
import SwiftUI

@main
struct SillApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Sill", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 860, minHeight: 600)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("새 Windows VM…") { model.showNewVM = true }
                    .keyboardShortcut("n")
            }
            CommandGroup(after: .newItem) {
                Button("준비 상태 점검") { model.showSetup = true }
            }
        }

        MenuBarExtra("Sill", systemImage: "macwindow.on.rectangle") {
            MenuBarContent()
                .environmentObject(model)
        }
    }
}

/// `swift run` 처럼 .app 묶음 없이 띄워도 Dock · 메뉴가 보이게
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 창을 닫아도 메뉴 막대에서 계속 VM 을 다룰 수 있게 앱은 남겨 둔다
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

#else
// Linux 등에서 패키지를 빌드 · 시험할 수 있게 하는 자리표시 — 앱 화면은 macOS 전용이다.
@main
enum SillApp {
    static func main() {
        print("Sill 앱은 macOS 전용입니다. 명령행 엔진은 레포 루트의 ./sill 을 쓰세요.")
    }
}
#endif
