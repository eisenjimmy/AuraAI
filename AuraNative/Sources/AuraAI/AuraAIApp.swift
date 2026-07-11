import SwiftUI

@main
struct AuraAIApp: App {
    @StateObject private var store = AuraStore()

    var body: some Scene {
        WindowGroup(AuraEdition.current.appName) {
            Group {
                if store.settings.onboarded {
                    AuraWorkspaceView()
                } else {
                    OnboardingView()
                }
            }
            .environmentObject(store)
            .frame(minWidth: 940, minHeight: 640)
            .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsView()
                .environmentObject(store)
                .frame(width: 720, height: 600)
        }
    }
}
