// Carbon's global hot keys, as the app's Esc-to-put-away uses them, on top of Win32 RegisterHotKey.
//
// RegisterHotKey with no window posts WM_HOTKEY to the main thread; AppKit's message pump hands those to
// `NSThreadMessageHook`, which calls the handlers installed here the way Carbon calls them.
@_exported import Foundation
import AppKit
import WinSDK

public typealias OSStatus = Int32
public typealias OSType = UInt32
public typealias OptionBits = UInt32
public let noErr: OSStatus = 0
public let eventNotHandledErr: OSStatus = -9874

public typealias EventTargetRef = OpaquePointer
public typealias EventHandlerRef = OpaquePointer
public typealias EventHandlerCallRef = OpaquePointer
public typealias EventRef = OpaquePointer
public typealias EventHotKeyRef = OpaquePointer
public typealias EventHandlerUPP = @convention(c) (EventHandlerCallRef?, EventRef?, UnsafeMutableRawPointer?) -> OSStatus

public struct EventTypeSpec: Sendable {
    public var eventClass: OSType
    public var eventKind: UInt32
    public init() { eventClass = 0; eventKind = 0 }
    public init(eventClass: OSType, eventKind: UInt32) { self.eventClass = eventClass; self.eventKind = eventKind }
}
public struct EventHotKeyID: Sendable {
    public var signature: OSType
    public var id: UInt32
    public init() { signature = 0; id = 0 }
    public init(signature: OSType, id: UInt32) { self.signature = signature; self.id = id }
}

public let kEventClassKeyboard: Int = 0x6B65_7962   // 'keyb'
public let kEventHotKeyPressed: Int = 5
public let kEventHotKeyReleased: Int = 6
public let cmdKey: Int = 0x100, shiftKey: Int = 0x200, optionKey: Int = 0x800, controlKey: Int = 0x1000

// The Mac's virtual key codes (Carbon.HIToolbox), for the keys the app uses.
public let kVK_Return: Int = 0x24, kVK_Tab: Int = 0x30, kVK_Space: Int = 0x31, kVK_Delete: Int = 0x33,
           kVK_Escape: Int = 0x35, kVK_LeftArrow: Int = 0x7B, kVK_RightArrow: Int = 0x7C, kVK_DownArrow: Int = 0x7D,
           kVK_UpArrow: Int = 0x7E, kVK_ForwardDelete: Int = 0x75, kVK_ANSI_Z: Int = 0x06

private func virtualKey(forMac code: UInt32) -> UINT? {
    switch Int(code) {
    case kVK_Escape: return UINT(VK_ESCAPE)
    case kVK_Return: return UINT(VK_RETURN)
    case kVK_Tab: return UINT(VK_TAB)
    case kVK_Space: return UINT(VK_SPACE)
    case kVK_Delete: return UINT(VK_BACK)
    case kVK_ForwardDelete: return UINT(VK_DELETE)
    case kVK_LeftArrow: return UINT(VK_LEFT)
    case kVK_RightArrow: return UINT(VK_RIGHT)
    case kVK_DownArrow: return UINT(VK_DOWN)
    case kVK_UpArrow: return UINT(VK_UP)
    case kVK_ANSI_Z: return 0x5A
    default: return nil
    }
}

private struct Handler { let upp: EventHandlerUPP; let data: UnsafeMutableRawPointer? }
private enum HotKeys {
    nonisolated(unsafe) static var handlers: [Int: Handler] = [:]
    nonisolated(unsafe) static var nextHandler = 1
    nonisolated(unsafe) static var nextKey: Int32 = 0x5350   // RegisterHotKey wants ids below 0xC000
    nonisolated(unsafe) static var hooked = false
    static let WM_HOTKEY_: UINT = 0x0312

    static func hook() {
        guard !hooked else { return }
        hooked = true
        let previous = NSThreadMessageHook
        NSThreadMessageHook = { m, w, l in
            if m == WM_HOTKEY_ {
                for h in HotKeys.handlers.values { _ = h.upp(nil, nil, h.data) }
                return
            }
            previous?(m, w, l)
        }
    }
}

private let applicationTarget = OpaquePointer(bitPattern: 0x4150_5054)!   // 'APPT'

public func GetApplicationEventTarget() -> EventTargetRef { applicationTarget }

@discardableResult
public func InstallEventHandler(_ target: EventTargetRef?, _ handler: EventHandlerUPP?, _ count: Int,
                                _ list: UnsafePointer<EventTypeSpec>?, _ userData: UnsafeMutableRawPointer?,
                                _ out: UnsafeMutablePointer<EventHandlerRef?>?) -> OSStatus {
    guard let handler else { return -50 }
    // Only hot-key presses reach handlers here; that is the only kind the app installs.
    let n = HotKeys.nextHandler
    HotKeys.nextHandler += 1
    HotKeys.handlers[n] = Handler(upp: handler, data: userData)
    HotKeys.hook()
    out?.pointee = OpaquePointer(bitPattern: n)
    return noErr
}

@discardableResult
public func RemoveEventHandler(_ h: EventHandlerRef) -> OSStatus {
    HotKeys.handlers[Int(bitPattern: UnsafeRawPointer(h))] = nil
    return noErr
}

@discardableResult
public func RegisterEventHotKey(_ code: UInt32, _ modifiers: UInt32, _ id: EventHotKeyID, _ target: EventTargetRef?,
                                _ options: OptionBits, _ out: UnsafeMutablePointer<EventHotKeyRef?>?) -> OSStatus {
    guard let vk = virtualKey(forMac: code) else { return -50 }
    var mods: UINT = 0x4000   // MOD_NOREPEAT
    if Int(modifiers) & cmdKey != 0 { mods |= 0x8 }
    if Int(modifiers) & shiftKey != 0 { mods |= 0x4 }
    if Int(modifiers) & optionKey != 0 { mods |= 0x1 }
    if Int(modifiers) & controlKey != 0 { mods |= 0x2 }
    let key = HotKeys.nextKey
    HotKeys.nextKey += 1
    guard RegisterHotKey(nil, key, mods, vk) else { return -9878 }   // eventHotKeyExistsErr: another program has it
    out?.pointee = OpaquePointer(bitPattern: Int(key))
    return noErr
}

@discardableResult
public func UnregisterEventHotKey(_ k: EventHotKeyRef) -> OSStatus {
    _ = UnregisterHotKey(nil, Int32(Int(bitPattern: UnsafeRawPointer(k))))
    return noErr
}
