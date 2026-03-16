import SwiftUI

@main
struct ButlerApp: App {

    // AppDelegate owns the Glass Chamber window and VisualizationEngine.
    // SwiftUI's @NSApplicationDelegateAdaptor bridges them into the App lifecycle.
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Settings scene keeps the app alive without creating a default window.
        // All window management is handled manually in AppDelegate.
        Settings {
            EmptyView()
        }
    }
}
