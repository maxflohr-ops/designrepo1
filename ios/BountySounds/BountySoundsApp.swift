import SwiftUI

@main
struct BountySoundsApp: App {
    @StateObject private var state = AppState()
    @StateObject private var entitlements = EntitlementStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .environmentObject(entitlements)
                .preferredColorScheme(.light)
        }
    }
}
