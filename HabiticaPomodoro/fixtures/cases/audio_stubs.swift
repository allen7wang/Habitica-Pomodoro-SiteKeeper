import Foundation
import AVFoundation

// Test-only media transports. The production AudioManager/engine stay unmodified;
// these module-local names shadow AVFoundation players, so fixtures make no HTTP
// requests and produce no sound. Real device playback is a separate acceptance gate.
final class AVPlayer {
    static var instances: [AVPlayer] = []
    var currentItem: NSObject?
    var volume: Float = 1
    private(set) var rate: Float = 0
    private(set) var playCalls = 0
    private(set) var seekCalls = 0
    private(set) var hasReachedEnd = false
    let url: URL

    init(url: URL) {
        self.url = url
        currentItem = NSObject()
        Self.instances.append(self)
    }

    // A real ended item cannot resume from EOF with play() alone.
    func reachEnd() { hasReachedEnd = true; rate = 0 }
    func play() { rate = hasReachedEnd ? 0 : 1; playCalls += 1 }
    func pause() { rate = 0 }
    func seek(to time: CMTime) {
        seekCalls += 1
        if CMTimeCompare(time, .zero) == 0 { hasReachedEnd = false }
    }
    func replaceCurrentItem(with item: NSObject?) { currentItem = item }
}

final class AVAudioPlayer {
    static var instances: [AVAudioPlayer] = []
    var volume: Float = 1
    var numberOfLoops = 0
    var currentTime: TimeInterval = 0
    private(set) var isPlaying = false

    init(contentsOf url: URL) throws { Self.instances.append(self) }
    @discardableResult func play() -> Bool { isPlaying = true; return true }
    func pause() { isPlaying = false }
    func stop() { isPlaying = false; currentTime = 0 }
}
