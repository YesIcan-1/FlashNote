// XCTest is unavailable on machines with only Command Line Tools (no Xcode);
// Swift Testing ships with the Swift toolchain itself.
import Testing
@testable import FlashNoteCore

struct FlashNoteCoreTests {
    @Test func version() {
        #expect(FlashNoteCore.version == "0.1.0")
    }
}
