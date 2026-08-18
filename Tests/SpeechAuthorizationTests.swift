import Testing
import Speech
import FlashNoteCore
#if os(macOS)
@testable import FlashNoteMac
#else
@testable import FlashNote
#endif

struct SpeechAuthorizationTests {
    @Test func authorizedMapsToNil() {
        #expect(SpeechAuthorization.error(for: .authorized) == nil)
    }

    @Test func deniedMapsToPermissionDenied() {
        #expect(SpeechAuthorization.error(for: .denied) == .permissionDenied)
        #expect(SpeechAuthorization.error(for: .restricted) == .permissionDenied)
        #expect(SpeechAuthorization.error(for: .notDetermined) == .permissionDenied)
    }
}
