import SwiftUI

@main
struct HKBusETAApp: App {
    @State private var app = AppState()

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--ui-snapshot"),
               ProcessInfo.processInfo.arguments.indices.contains(index + 1) {
                TransitPreviewGallery(screen: ProcessInfo.processInfo.arguments[index + 1])
            } else { mainContent }
            #else
            mainContent
            #endif
        }
    }

    private var mainContent: some View {
            RootView()
                .environment(app)
                .environment(\.locale, app.settings.language.locale)
                .environment(\.timeZone, app.region.timeZone)
                .task {
                    await app.data.load()
                }
    }
}
