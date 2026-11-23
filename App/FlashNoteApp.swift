import SwiftUI

#if os(macOS)
@main
struct FlashNoteMacApp: App {
    @State private var environment = AppEnvironment.makeLive()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.appEnvironment, environment)
                .preferredColorScheme(AppTheme.preferredColorScheme)
                .task {
                    environment.startUSBSync()
                    await AppNotificationService.shared.requestAuthorization()
                }
        }
    }
}
#else
@main
struct FlashNoteApp: App {
    @State private var environment = AppEnvironment.makeLive()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.appEnvironment, environment)
                .preferredColorScheme(AppTheme.preferredColorScheme)
        }
    }
}
#endif
