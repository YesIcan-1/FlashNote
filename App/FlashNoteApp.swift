import SwiftUI

#if os(macOS)
@main
struct FlashNoteMacApp: App {
    @State private var environment = AppEnvironment.makeLive()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.appEnvironment, environment)
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
        }
    }
}
#endif
