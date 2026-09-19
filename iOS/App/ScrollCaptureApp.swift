import SwiftUI

@main
struct ScrollCaptureApp: App {
    @StateObject private var library = CaptureLibrary()
    @StateObject private var exportQuota = ExportQuotaStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(library)
                .environmentObject(exportQuota)
                .preferredColorScheme(.light)
                .task {
                    while !Task.isCancelled {
                        if scenePhase == .active { library.refresh() }
                        try? await Task.sleep(for: .seconds(2))
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { library.refresh() }
                }
        }
    }
}
