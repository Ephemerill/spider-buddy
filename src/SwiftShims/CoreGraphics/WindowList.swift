// CoreGraphics stand-in for Windows: the window list.
//
// The Mac's WindowTracker reads CGWindowListCopyWindowInfo and filters it. Keeping that function here means
// the tracker's rules stay the Mac's own: the Windows host only has to report its windows in this form.
import Foundation

public typealias CGWindowID = UInt32
public let kCGNullWindowID: CGWindowID = 0

public struct CGWindowListOption: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let optionAll = CGWindowListOption([])
    public static let optionOnScreenOnly = CGWindowListOption(rawValue: 1)
    public static let optionOnScreenAboveWindow = CGWindowListOption(rawValue: 2)
    public static let optionOnScreenBelowWindow = CGWindowListOption(rawValue: 4)
    public static let optionIncludingWindow = CGWindowListOption(rawValue: 8)
    public static let excludeDesktopElements = CGWindowListOption(rawValue: 16)
}

public let kCGWindowLayer: CFString = "kCGWindowLayer"
public let kCGWindowNumber: CFString = "kCGWindowNumber"
public let kCGWindowOwnerPID: CFString = "kCGWindowOwnerPID"
public let kCGWindowOwnerName: CFString = "kCGWindowOwnerName"
public let kCGWindowName: CFString = "kCGWindowName"
public let kCGWindowBounds: CFString = "kCGWindowBounds"
public let kCGWindowAlpha: CFString = "kCGWindowAlpha"

public enum CGWindowLevelKey: Int32, Sendable {
    case baseWindow, minimumWindow, desktopWindow, backstopMenu, normalWindow, floatingWindow, tornOffMenuWindow,
         dockWindow, mainMenuWindow, statusWindow, modalPanelWindow, popUpMenuWindow, draggingWindow,
         screenSaverWindow, maximumWindow, overlayWindow, helpWindow, utilityWindow, desktopIconWindow,
         cursorWindow, assistiveTechHighWindow
}

public func CGWindowLevelForKey(_ key: CGWindowLevelKey) -> Int32 {
    switch key {
    case .desktopWindow: return -2147483623
    case .desktopIconWindow: return -2147483603
    case .floatingWindow: return 3
    case .mainMenuWindow: return 24
    case .statusWindow: return 25
    case .popUpMenuWindow: return 101
    case .screenSaverWindow: return 1000
    case .dockWindow: return 20
    default: return 0
    }
}

/// Set by the host: one dictionary per window, front to back, with the keys above.
nonisolated(unsafe) public var CGWindowListProvider: () -> [[String: Any]] = { [] }

public func CGWindowListCopyWindowInfo(_ option: CGWindowListOption, _ relativeToWindow: CGWindowID) -> CFArray? {
    CGWindowListProvider()
}

extension CGRect {
    public init?(dictionaryRepresentation dict: CFDictionary) {
        func v(_ k: String) -> CGFloat? {
            if let c = dict[k] as? CGFloat { return c }
            if let d = dict[k] as? Double { return CGFloat(d) }
            if let i = dict[k] as? Int { return CGFloat(i) }
            return nil
        }
        guard let x = v("X"), let y = v("Y"), let w = v("Width"), let h = v("Height") else { return nil }
        self.init(x: x, y: y, width: w, height: h)
    }
}

/// The Mac asks for permission before measuring a window's corners from its pixels. There is no such permission here:
/// the host turns this on and supplies the corners through WindowTracker.measureCorner.
nonisolated(unsafe) public var CGCornersAvailable = false
public func CGPreflightScreenCaptureAccess() -> Bool { CGCornersAvailable }

#if os(Windows)
import WinSDK

/// Test tools only. On the Mac, SWIFT_DETERMINISTIC_HASHING=1 fixes Set and Dictionary order across runs. The Windows
/// runtime does not read that variable, so comparison runs set the runtime's own parameters to what it means: seed zero,
/// deterministic. Call it first thing, before anything hashes. Returns false if the symbol is not there.
@discardableResult
public func CGPinHashingForTests() -> Bool {
    let module = "swiftCore.dll".withCString(encodedAs: UTF16.self) { GetModuleHandleW($0) }
    guard let module, let sym = GetProcAddress(module, "_swift_stdlib_Hashing_parameters") else { return false }
    let raw = unsafeBitCast(sym, to: UnsafeMutableRawPointer.self)
    raw.storeBytes(of: UInt64(0), toByteOffset: 0, as: UInt64.self)
    raw.storeBytes(of: UInt64(0), toByteOffset: 8, as: UInt64.self)
    raw.storeBytes(of: true, toByteOffset: 16, as: Bool.self)
    return true
}
#endif
