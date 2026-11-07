// Windows replacement for the Mac's PageBridge.swift. Page climbing is off in the Mac app for now
// (AppDelegate.pagesReady); this keeps its shape until it comes back.
import AppKit

final class PageBridge {
    struct Scroller { var id: Int; var carrier: Int; var rect: CGRect; var offset: CGPoint }
    struct Page {
        var tab: Int
        var window: CGRect
        var viewport: CGSize
        var dpr: CGFloat
        var scrollers: [Int: Scroller] = [:]
        var fixed: [CGRect] = []
        var offsets: [Int: CGPoint] = [:]
        var laidOutAt: CFTimeInterval = 0
    }
    private(set) var pages: [Int: Page] = [:]
    private(set) var connected = false
    var onScroll: ((Int) -> Void)?
    var onChange: ((Int) -> Void)?
    static let ports: [UInt16] = [47219, 47220, 47221]
    var running: Bool { false }
    func start() {}
    func stop() {}
    func want(_ frames: [CGRect]) {}
    func page(in frame: CGRect) -> Page? { nil }
}
