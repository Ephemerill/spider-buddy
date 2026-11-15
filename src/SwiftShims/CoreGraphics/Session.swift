// CoreGraphics stand-in for Windows: window pictures, the input idle clock and the session's lock state.
//
// Pictures of windows need to know the screens and our own windows, which AppKit owns, so AppKit installs the
// provider. The Mac asks for screen-recording permission first; Windows has no such permission.
import Foundation
#if os(Windows)
import WinSDK
#endif

public struct CGWindowImageOption: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let boundsIgnoreFraming = CGWindowImageOption(rawValue: 1 << 0)
    public static let shouldBeOpaque = CGWindowImageOption(rawValue: 1 << 1)
    public static let onlyShadows = CGWindowImageOption(rawValue: 1 << 2)
    public static let bestResolution = CGWindowImageOption(rawValue: 1 << 3)
    public static let nominalResolution = CGWindowImageOption(rawValue: 1 << 4)
}

/// Set by AppKit: a picture of `rect` (window-list space: points, origin at the top left of the primary screen; `.null`
/// for the windows' own bounds) made of the windows `option` picks relative to `window`.
nonisolated(unsafe) public var CGWindowImageProvider: (CGRect, CGWindowListOption, CGWindowID, CGWindowImageOption) -> CGImage? = { _, _, _, _ in nil }
/// Set by AppKit: the given windows, front to back, composited into one picture.
nonisolated(unsafe) public var CGWindowArrayImageProvider: (CGRect, [CGWindowID], CGWindowImageOption) -> CGImage? = { _, _, _ in nil }

public func CGWindowListCreateImage(_ rect: CGRect, _ option: CGWindowListOption, _ window: CGWindowID, _ image: CGWindowImageOption) -> CGImage? {
    CGWindowImageProvider(rect, option, window, image)
}

extension CGImage {
    public convenience init?(windowListFromArrayScreenBounds rect: CGRect, windowArray: CFArray, imageOption: CGWindowImageOption) {
        let ids: [CGWindowID] = windowArray.compactMap { v in
            if let p = v as? UnsafeRawPointer { return CGWindowID(truncatingIfNeeded: UInt(bitPattern: p)) }
            if let n = v as? Int { return CGWindowID(truncatingIfNeeded: n) }
            if let n = v as? CGWindowID { return n }
            return nil
        }
        guard let img = CGWindowArrayImageProvider(rect, ids, imageOption) else { return nil }
        self.init(pixels: img.pixels, width: img.width, height: img.height, bytesPerRow: img.bytesPerRow)
    }
}

/// `CFArrayCreate(nil, &pointers, n, nil)`, as the Mac's window-array pictures build their list.
public func CFArrayCreate(_ allocator: Any?, _ values: UnsafeMutablePointer<UnsafeRawPointer?>?, _ count: Int, _ callbacks: Any?) -> CFArray? {
    guard let values else { return count == 0 ? [] : nil }
    return (0..<count).compactMap { values[$0] }
}

/// No permission is needed to see the screen on Windows.
@discardableResult public func CGRequestScreenCaptureAccess() -> Bool { true }

// MARK: Input idle time

public enum CGEventSourceStateID: Int32, Sendable { case privateState = -1, combinedSessionState = 0, hidSystemState = 1 }

public enum CGEventType: UInt32, Sendable {
    case null = 0, leftMouseDown = 1, leftMouseUp = 2, rightMouseDown = 3, rightMouseUp = 4, mouseMoved = 5,
         leftMouseDragged = 6, rightMouseDragged = 7, keyDown = 10, keyUp = 11, flagsChanged = 12, scrollWheel = 22,
         tabletPointer = 23, tabletProximity = 24, otherMouseDown = 25, otherMouseUp = 26, otherMouseDragged = 27,
         tapDisabledByTimeout = 0xFFFFFFFE, tapDisabledByUserInput = 0xFFFFFFFF
}

public final class CGEventSource {
    /// Seconds since the user last touched the mouse or keyboard. Windows keeps one clock for all input, which is what
    /// the Mac's callers ask for (`kCGAnyInputEventType`, the combined session).
    public static func secondsSinceLastEventType(_ state: CGEventSourceStateID, eventType: CGEventType) -> CFTimeInterval {
        #if os(Windows)
        var info = LASTINPUTINFO()
        info.cbSize = UINT(MemoryLayout<LASTINPUTINFO>.size)
        guard GetLastInputInfo(&info) else { return 0 }
        let now = GetTickCount()
        return CFTimeInterval(now &- info.dwTime) / 1000
        #else
        return 0
        #endif
    }
}

// MARK: The session

/// Kept by AppKit from the session's lock and unlock notices.
nonisolated(unsafe) public var CGSessionScreenIsLocked = false

public func CGSessionCopyCurrentDictionary() -> CFDictionary? {
    ["CGSSessionScreenIsLocked": CGSessionScreenIsLocked, "kCGSSessionOnConsoleKey": true]
}
