// Windows replacement for the Mac's Ears.swift: same names. Stub for now; WASAPI loopback fills this in with the
// sensors phase, feeding the Mac's own Beat.swift tracker.
import AppKit

final class Ears {
    enum Status: Equatable {
        case unsupported, off, quiet, listening, hearing(Double), deaf
    }
    var onChange: (() -> Void)?
    static var supported: Bool { false }
    var status: Status = .unsupported
    var playingApps: [String] = []
    var debugHeard: ((UnsafeBufferPointer<Float>, Double) -> Void)?
    func start() {}
    func stop() {}
    func music(at now: CFTimeInterval) -> MusicBeat? { nil }
}
