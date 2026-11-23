import Testing
import AVFoundation
#if os(macOS)
@testable import FlashNoteMac
#else
@testable import FlashNote
#endif

struct AudioServiceTests {
    @Test func rmsOfSilenceIsZero() {
        #expect(AudioService.rms([Float](repeating: 0, count: 64)) == 0)
    }

    @Test func rmsOfFullScaleIsNearOne() {
        let samples = [Float](repeating: 1.0, count: 64)
        #expect(AudioService.rms(samples) > 0.95)
    }

    @Test func rmsOfMixedSamplesIsPositiveAndBounded() {
        let samples: [Float] = (0..<64).map { Float($0 % 7) / 7.0 }
        let rms = AudioService.rms(samples)
        #expect(rms > 0)
        #expect(rms <= 1)
    }
}
