import SwiftUI

#if os(macOS)
@main
struct FlashNoteMacApp: App {
    @State private var environment = AppEnvironment.makeLive()
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system.rawValue

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.appEnvironment, environment)
                .preferredColorScheme(preferredScheme)
        }
    }
    private var preferredScheme: ColorScheme? { AppearanceMode(rawValue: appearanceMode) == .light ? .light : AppearanceMode(rawValue: appearanceMode) == .dark ? .dark : nil }
}
#else
@main
struct FlashNoteApp: App {
    @State private var environment = AppEnvironment.makeLive()
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system.rawValue

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.appEnvironment, environment)
                .preferredColorScheme(preferredScheme)
        }
    }
    private var preferredScheme: ColorScheme? { AppearanceMode(rawValue: appearanceMode) == .light ? .light : AppearanceMode(rawValue: appearanceMode) == .dark ? .dark : nil }
}
#endif
