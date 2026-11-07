// Menus (native Win32), the tray icon, popovers, alerts, file panels, the clipboard, sounds, toolbars.
import Foundation
import QuartzCore
import WinSDK

// MARK: Menus

public protocol NSMenuDelegate: AnyObject {
    func menuNeedsUpdate(_ m: NSMenu)
    func menuWillOpen(_ m: NSMenu)
    func menuDidClose(_ m: NSMenu)
}
extension NSMenuDelegate {
    public func menuNeedsUpdate(_ m: NSMenu) {}
    public func menuWillOpen(_ m: NSMenu) {}
    public func menuDidClose(_ m: NSMenu) {}
}
open class NSMenuItem: NSObject {
    public var title: String
    public var action: Selector?
    public weak var target: AnyObject?
    public var keyEquivalent: String
    public var keyEquivalentModifierMask = NSEvent.ModifierFlags.command
    public var submenu: NSMenu?
    public var state = NSControl.StateValue.off
    public var isEnabled = true
    public var isHidden = false
    public var tag = 0
    public var representedObject: Any?
    public var image: NSImage?
    public var toolTip: String?
    public var indentationLevel = 0
    public var view: NSView?
    public var attributedTitle: NSAttributedString?
    public var isSeparatorItem: Bool { separator }
    public var hasSubmenu: Bool { submenu != nil }
    public var isAlternate = false
    public weak var menu: NSMenu?
    private var separator = false
    public init(title t: String, action a: Selector?, keyEquivalent k: String) { title = t; action = a; keyEquivalent = k }
    public static func separator() -> NSMenuItem { let i = NSMenuItem(title: "", action: nil, keyEquivalent: ""); i.separator = true; return i }
    public static func sectionHeader(title t: String) -> NSMenuItem { let i = NSMenuItem(title: t, action: nil, keyEquivalent: ""); i.isEnabled = false; return i }
}
open class NSMenu: NSObject {
    public var title: String
    public private(set) var items: [NSMenuItem] = []
    public var autoenablesItems = true
    public var minimumWidth: CGFloat = 0
    public var font: NSFont?
    public var showsStateColumn = true
    public weak var delegate: NSMenuDelegate?
    public var numberOfItems: Int { items.count }
    public weak var supermenu: NSMenu?
    public var highlightedItem: NSMenuItem? { nil }
    var onPick: ((NSMenuItem) -> Void)?
    public init(title t: String = "") { title = t; super.init() }
    public func addItem(_ i: NSMenuItem) { items.append(i); i.menu = self; i.submenu?.supermenu = self }
    @discardableResult public func addItem(withTitle t: String, action a: Selector?, keyEquivalent k: String) -> NSMenuItem {
        let i = NSMenuItem(title: t, action: a, keyEquivalent: k); addItem(i); return i
    }
    public func insertItem(_ i: NSMenuItem, at at: Int) { items.insert(i, at: min(at, items.count)); i.menu = self }
    public func removeItem(_ i: NSMenuItem) { items.removeAll { $0 === i } }
    public func removeItem(at i: Int) { items.remove(at: i) }
    public func removeAllItems() { items.removeAll() }
    public func item(at i: Int) -> NSMenuItem? { items.indices.contains(i) ? items[i] : nil }
    public func item(withTitle t: String) -> NSMenuItem? { items.first { $0.title == t } }
    public func item(withTag t: Int) -> NSMenuItem? { items.first { $0.tag == t } }
    public func setSubmenu(_ m: NSMenu?, for i: NSMenuItem) { i.submenu = m; m?.supermenu = self }
    public func update() {}
    public func cancelTracking() {}
    public func cancelTrackingWithoutAnimation() {}
    public func indexOfItem(withTitle t: String) -> Int { items.firstIndex { $0.title == t } ?? -1 }
    public func index(of i: NSMenuItem) -> Int { items.firstIndex { $0 === i } ?? -1 }

    nonisolated(unsafe) private static var live: [Int: NSMenuItem] = [:]
    nonisolated(unsafe) private static var nextID = 100
    static func performNative(id: Int) {
        guard let i = live[id] else { return }
        if let pick = i.menu?.onPick { pick(i); return }
        if let a = i.action { a.send(to: i.target, from: i) }
    }
    private func build() -> HMENU? {
        let h = CreatePopupMenu()
        delegate?.menuNeedsUpdate(self)
        for i in items where !i.isHidden {
            if i.isSeparatorItem { _ = AppendMenuW(h, UINT(MF_SEPARATOR), 0, nil); continue }
            var flags = UINT(MF_STRING)
            if !i.isEnabled || (autoenablesItems && i.action == nil && i.submenu == nil && onPick == nil) { flags |= UINT(MF_GRAYED) }
            if i.state == .on { flags |= UINT(MF_CHECKED) }
            let text = (i.attributedTitle?.string ?? i.title).replacingOccurrences(of: "&", with: "&&")
            if let sub = i.submenu {
                flags |= UINT(MF_POPUP)
                let hs = sub.build()
                text.withCString(encodedAs: UTF16.self) { _ = AppendMenuW(h, flags, UINT_PTR(UInt(bitPattern: hs)), $0) }
            } else {
                NSMenu.nextID += 1
                let id = NSMenu.nextID
                NSMenu.live[id] = i
                text.withCString(encodedAs: UTF16.self) { _ = AppendMenuW(h, flags, UINT_PTR(id), $0) }
            }
        }
        return h
    }
    @discardableResult public func popUp(positioning i: NSMenuItem?, at p: CGPoint, in v: NSView?) -> Bool {
        NSMenu.live.removeAll(keepingCapacity: true)
        delegate?.menuWillOpen(self)
        let h = build()
        let owner = MessageWindow.shared.hwnd
        let at: CGPoint = v.flatMap { $0.window?.convertPoint(toScreen: $0.convert(p, to: nil)) } ?? p
        let px = worldToPixel(at)
        _ = SetForegroundWindow(owner)
        NSApp.modalDepth += 1
        // The app keeps its beat while a menu is open: only a timer gets through this modal loop.
        _ = SetTimer(owner, 1, 16, nil)
        _ = TrackPopupMenu(h, UINT(TPM_LEFTALIGN | TPM_TOPALIGN), px.x, px.y, 0, owner, nil)
        _ = KillTimer(owner, 1)
        NSApp.modalDepth -= 1
        PostMessageW(owner, UINT(WM_NULL), 0, 0)
        DestroyMenu(h)
        delegate?.menuDidClose(self)
        return true
    }
    public static func popUpContextMenu(_ m: NSMenu, with e: NSEvent, for v: NSView) { m.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil) }
    public func size() -> CGSize { CGSize(width: 200, height: CGFloat(items.count) * 22) }
}

/// A hidden window to own menus, the tray icon and timers.
final class MessageWindow: NSWindow {
    static let shared = MessageWindow(contentRect: CGRect(x: -100, y: -100, width: 1, height: 1), styleMask: [], backing: .buffered, defer: false)
}

// MARK: Tray

public final class NSStatusBar: NSObject, @unchecked Sendable {
    public static let system = NSStatusBar()
    public static let variableLength: CGFloat = -1
    public static let squareLength: CGFloat = -2
    nonisolated(unsafe) static var items: [NSStatusItem] = []
    public var thickness: CGFloat { 22 }
    public func statusItem(withLength l: CGFloat) -> NSStatusItem { let i = NSStatusItem(); NSStatusBar.items.append(i); return i }
    public func removeStatusItem(_ i: NSStatusItem) { i.remove(); NSStatusBar.items.removeAll { $0 === i } }
    static func removeAll() { for i in items { i.remove() } }
    static func handleTray(_ l: LPARAM) {
        guard let i = items.first else { return }
        switch Int32(l & 0xFFFF) {
        case WM_LBUTTONUP:
            if let e = i.button?.action { e.send(to: i.button?.target, from: i.button) }
        case WM_RBUTTONUP:
            if let m = i.menu { m.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil) } else if let e = i.button?.action { e.send(to: i.button?.target, from: i.button) }
        default: break
        }
    }
}
public final class NSStatusBarButton: NSButton {
    weak var item: NSStatusItem?
    public var appearsDisabled = false { didSet { item?.update() } }
    public override var image: NSImage? { didSet { item?.update() } }
    public override var toolTip: String? { didSet { item?.update() } }
    public var sendActionOnMask: NSEvent.EventTypeMask = []
    public func sendAction(on m: NSEvent.EventTypeMask) { sendActionOnMask = m }
    public override func convert(_ r: CGRect, to v: NSView?) -> CGRect { r }
}
public final class NSStatusItem: NSObject, @unchecked Sendable {
    public var button: NSStatusBarButton? = NSStatusBarButton(frame: CGRect(x: 0, y: 0, width: 22, height: 22))
    public var menu: NSMenu?
    public var isVisible = true { didSet { update() } }
    public var length: CGFloat = -1
    public var autosaveName: String?
    public var behavior = 0
    private var added = false
    private var icon: HICON?
    override init() { super.init(); button?.item = self }
    private func notifyData() -> NOTIFYICONDATAW {
        var d = NOTIFYICONDATAW()
        d.cbSize = DWORD(MemoryLayout<NOTIFYICONDATAW>.size)
        d.hWnd = MessageWindow.shared.hwnd
        d.uID = 1
        return d
    }
    func update() {
        guard let b = button else { return }
        if let i = b.image { makeIcon(i, dim: b.appearsDisabled) }
        var d = notifyData()
        d.uFlags = UINT(NIF_ICON | NIF_MESSAGE | NIF_TIP)
        d.uCallbackMessage = UINT(WM_APP_TRAY)
        d.hIcon = icon ?? LoadIconW(GetModuleHandleW(nil), UnsafePointer<WCHAR>(bitPattern: 1)) ?? LoadIconW(nil, UnsafePointer<WCHAR>(bitPattern: 32512))
        let tip = Array((b.toolTip ?? "Spider Buddy").utf16.prefix(120)) + [0]
        withUnsafeMutableBytes(of: &d.szTip) { raw in
            let p = raw.bindMemory(to: WCHAR.self)
            for (k, c) in tip.enumerated() where k < p.count { p[k] = c }
        }
        _ = Shell_NotifyIconW(added ? DWORD(NIM_MODIFY) : DWORD(NIM_ADD), &d)
        added = true
    }
    func remove() {
        guard added else { return }
        var d = notifyData()
        _ = Shell_NotifyIconW(DWORD(NIM_DELETE), &d)
        added = false
    }
    private func makeIcon(_ image: NSImage, dim: Bool) {
        let side = Int((16 * NSScreen.primaryScale).rounded())
        guard let c = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return }
        c.scaleBy(x: CGFloat(side) / max(image.size.width, 1), y: CGFloat(side) / max(image.size.height, 1))
        if dim { c.setAlpha(0.45) }
        // A template image is a shape: on Windows' taskbar it reads as white.
        image.render(in: c, tint: .white)
        guard let bytes = c.data else { return }
        if image.isTemplate {
            let px = bytes.assumingMemoryBound(to: UInt8.self)
            for i in 0..<(side * side) { let a = px[i * 4 + 3]; px[i * 4] = a; px[i * 4 + 1] = a; px[i * 4 + 2] = a }
        }
        let mask = [UInt8](repeating: 0, count: side * side)
        let color = CreateBitmap(Int32(side), Int32(side), 1, 32, bytes)
        let bm = mask.withUnsafeBytes { CreateBitmap(Int32(side), Int32(side), 1, 1, $0.baseAddress) }
        var info = ICONINFO(fIcon: true, xHotspot: 0, yHotspot: 0, hbmMask: bm, hbmColor: color)
        let h = CreateIconIndirect(&info)
        if let old = icon { DestroyIcon(old) }
        icon = h
        DeleteObject(color); DeleteObject(bm)
    }
}

// MARK: Popover: a borderless panel with the Mac's rounded card and arrow-less drop.

public protocol NSPopoverDelegate: AnyObject {
    func popoverDidClose(_ n: Notification)
    func popoverWillShow(_ n: Notification)
    func popoverDidShow(_ n: Notification)
}
extension NSPopoverDelegate {
    public func popoverDidClose(_ n: Notification) {}
    public func popoverWillShow(_ n: Notification) {}
    public func popoverDidShow(_ n: Notification) {}
}
public enum NSRectEdge: UInt, Sendable { case minX, minY, maxX, maxY }
public final class NSPopover: NSResponder {
    public enum Behavior: Int, Sendable { case applicationDefined, transient, semitransient }
    public var behavior = Behavior.applicationDefined
    public var animates = true
    public var contentSize = CGSize(width: 300, height: 300)
    public var contentViewController: NSViewController?
    public weak var delegate: NSPopoverDelegate?
    public var appearance: NSAppearance?
    public var isShown: Bool { panel?.isVisible ?? false }
    private var panel: NSPanel?
    private var outsideMonitor: Any?
    public override init() { super.init() }
    public required init?(coder: NSCoder) { super.init() }
    public func show(relativeTo r: CGRect, of v: NSView, preferredEdge e: NSRectEdge) {
        let content = contentViewController?.view ?? NSView(frame: .zero)
        let size = content.frame.size != .zero ? content.frame.size : contentSize
        let vf = NSScreen.main?.visibleFrame ?? .zero
        // Above the notification area, where the tray icon is.
        let anchor = NSEvent.mouseLocation
        let x = max(vf.minX + 8, min(anchor.x - size.width / 2, vf.maxX - size.width - 8))
        let f = CGRect(x: x, y: vf.minY + 10, width: size.width, height: size.height)
        let p = panel ?? NSPanel(contentRect: f, styleMask: [.nonactivatingPanel], backing: .buffered, defer: false)
        panel = p
        p.setFrame(f, display: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .popUpMenu
        p.appearance = appearance
        let host = p.contentView!
        host.wantsLayer = true
        host.backing.cornerRadius = 12
        host.backing.masksToBounds = true
        host.backing.backgroundColor = (appearance ?? NSApp.effectiveAppearance).isDark ? CGColor(srgbRed: 0.17, green: 0.17, blue: 0.18, alpha: 1) : CGColor(srgbRed: 0.93, green: 0.93, blue: 0.93, alpha: 1)
        if content.superview !== host {
            content.frame = host.bounds
            content.autoresizingMask = [.width, .height]
            host.addSubview(content)
        }
        delegate?.popoverWillShow(Notification(name: Notification.Name("NSPopoverWillShowNotification"), object: self))
        p.makeKeyAndOrderFront(nil)
        delegate?.popoverDidShow(Notification(name: Notification.Name("NSPopoverDidShowNotification"), object: self))
        if behavior != .applicationDefined {
            outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                guard let self, let f = self.panel?.frame, !f.contains(NSEvent.mouseLocation) else { return }
                self.close()
            }
        }
    }
    public func close() {
        guard isShown else { return }
        panel?.orderOut(nil)
        if let m = outsideMonitor { NSEvent.removeMonitor(m); outsideMonitor = nil }
        delegate?.popoverDidClose(Notification(name: Notification.Name("NSPopoverDidCloseNotification"), object: self))
    }
    public func performClose(_ s: Any?) { close() }
}

// MARK: Alerts and file panels

public final class NSAlert: NSObject {
    public enum Style: UInt, Sendable { case warning, informational, critical }
    public var messageText = ""
    public var informativeText = ""
    public var alertStyle = Style.warning
    public var icon: NSImage?
    public private(set) var buttons: [NSButton] = []
    public var showsHelp = false
    public var accessoryView: NSView?
    public var window: NSWindow { NSApp.windows.first ?? MessageWindow.shared }
    public override init() { super.init() }
    @discardableResult public func addButton(withTitle t: String) -> NSButton { let b = NSButton(title: t, target: nil, action: nil); buttons.append(b); return b }
    public func runModal() -> NSApplication.ModalResponse {
        // A native box, with the Mac's words. Up to three buttons map onto Yes/No/Cancel.
        let text = informativeText.isEmpty ? messageText : messageText + "\n\n" + informativeText
        var flags = UINT(alertStyle == .critical ? MB_ICONERROR : alertStyle == .warning ? MB_ICONWARNING : MB_ICONINFORMATION)
        flags |= buttons.count >= 3 ? UINT(MB_YESNOCANCEL) : buttons.count == 2 ? UINT(MB_OKCANCEL) : UINT(MB_OK)
        let r = text.withCString(encodedAs: UTF16.self) { t in "Spider Buddy".withCString(encodedAs: UTF16.self) { c in MessageBoxW(nil, t, c, flags) } }
        switch r {
        case IDOK, IDYES: return .alertFirstButtonReturn
        case IDCANCEL: return buttons.count >= 3 ? .alertThirdButtonReturn : .alertSecondButtonReturn
        case IDNO: return .alertSecondButtonReturn
        default: return .alertFirstButtonReturn
        }
    }
    public func beginSheetModal(for w: NSWindow, completionHandler h: ((NSApplication.ModalResponse) -> Void)? = nil) { let r = runModal(); h?(r) }
}

open class NSSavePanel: NSObject {
    public var title: String?
    public var message: String?
    public var prompt: String?
    public var nameFieldStringValue = ""
    public var nameFieldLabel: String?
    public var directoryURL: URL?
    public var allowedContentTypes: [AnyHashable] = []
    public var allowsOtherFileTypes = false
    public var canCreateDirectories = true
    public var isExtensionHidden = false
    public var treatsFilePackagesAsDirectories = false
    public var url: URL? { chosen.first }
    var chosen: [URL] = []
    var isOpen: Bool { false }
    public override init() { super.init() }
    public func runModal() -> NSApplication.ModalResponse {
        chosen = FileDialogs.run(open: isOpen, multiple: false, suggested: nameFieldStringValue, title: title ?? message)
        return chosen.isEmpty ? .cancel : .OK
    }
    public func begin(completionHandler h: @escaping (NSApplication.ModalResponse) -> Void) { h(runModal()) }
    public func beginSheetModal(for w: NSWindow, completionHandler h: @escaping (NSApplication.ModalResponse) -> Void) { h(runModal()) }
}
public final class NSOpenPanel: NSSavePanel {
    public var allowsMultipleSelection = false
    public var canChooseFiles = true
    public var canChooseDirectories = false
    public var resolvesAliases = true
    public var urls: [URL] { chosen }
    override var isOpen: Bool { true }
    public override func runModal() -> NSApplication.ModalResponse {
        chosen = FileDialogs.run(open: true, multiple: allowsMultipleSelection, suggested: "", title: title ?? message)
        return chosen.isEmpty ? .cancel : .OK
    }
}
enum FileDialogs {
    static func run(open: Bool, multiple: Bool, suggested: String, title: String?) -> [URL] {
        var buf = [WCHAR](repeating: 0, count: 8192)
        for (i, c) in suggested.utf16.prefix(8000).enumerated() { buf[i] = c }
        var o = OPENFILENAMEW()
        o.lStructSize = DWORD(MemoryLayout<OPENFILENAMEW>.size)
        o.nMaxFile = DWORD(buf.count)
        o.Flags = DWORD(OFN_NOCHANGEDIR | OFN_EXPLORER) | (open ? DWORD(OFN_FILEMUSTEXIST | (multiple ? OFN_ALLOWMULTISELECT : 0)) : DWORD(OFN_OVERWRITEPROMPT))
        let t = title.map { Array($0.utf16) + [0] }
        let ok: Bool = buf.withUnsafeMutableBufferPointer { b in
            o.lpstrFile = b.baseAddress
            func call() -> Bool { open ? GetOpenFileNameW(&o) : GetSaveFileNameW(&o) }
            if let t { return t.withUnsafeBufferPointer { p in o.lpstrTitle = p.baseAddress; return call() } }
            return call()
        }
        guard ok else { return [] }
        let parts = buf.split(separator: 0, omittingEmptySubsequences: false).prefix { !$0.isEmpty }.map { String(decoding: $0, as: UTF16.self) }
        if parts.count > 1 { return parts.dropFirst().map { URL(fileURLWithPath: parts[0]).appendingPathComponent($0) } }
        return parts.map { URL(fileURLWithPath: $0) }
    }
}
enum ColorChooser {
    static func choose(from c: NSColor) -> NSColor? {
        var custom = [COLORREF](repeating: 0x00FFFFFF, count: 16)
        let cg = c.cgColor
        var cc = CHOOSECOLORW()
        cc.lStructSize = DWORD(MemoryLayout<CHOOSECOLORW>.size)
        cc.rgbResult = COLORREF(UInt32(cg.sr * 255) | (UInt32(cg.sg * 255) << 8) | (UInt32(cg.sb * 255) << 16))
        cc.Flags = DWORD(CC_RGBINIT | CC_FULLOPEN)
        let ok = custom.withUnsafeMutableBufferPointer { b -> Bool in cc.lpCustColors = b.baseAddress; return ChooseColorW(&cc) }
        guard ok else { return nil }
        let v = cc.rgbResult
        return NSColor(srgbRed: CGFloat(v & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat((v >> 16) & 255) / 255, alpha: 1)
    }
}

// MARK: Clipboard, sounds, drag and drop, animation groups

public final class NSPasteboard: NSObject, @unchecked Sendable {
    public struct PasteboardType: RawRepresentable, Hashable, Sendable { public let rawValue: String; public init(rawValue: String) { self.rawValue = rawValue }; public init(_ s: String) { rawValue = s }
        public static let string = Self(rawValue: "public.utf8-plain-text"), fileURL = Self(rawValue: "public.file-url"), png = Self(rawValue: "public.png"), tiff = Self(rawValue: "public.tiff") }
    public static let general = NSPasteboard()
    public func clearContents() -> Int { if OpenClipboard(nil) { EmptyClipboard(); CloseClipboard() }; return 0 }
    @discardableResult public func setString(_ s: String, forType t: PasteboardType) -> Bool {
        guard OpenClipboard(nil) else { return false }
        defer { CloseClipboard() }
        let u = Array(s.utf16) + [0]
        let bytes = u.count * 2
        guard let h = GlobalAlloc(UINT(GMEM_MOVEABLE), SIZE_T(bytes)), let p = GlobalLock(h) else { return false }
        u.withUnsafeBytes { p.copyMemory(from: $0.baseAddress!, byteCount: bytes) }
        GlobalUnlock(h)
        _ = SetClipboardData(UINT(CF_UNICODETEXT), h)
        return true
    }
    public func string(forType t: PasteboardType) -> String? {
        guard OpenClipboard(nil) else { return nil }
        defer { CloseClipboard() }
        guard let h = GetClipboardData(UINT(CF_UNICODETEXT)), let p = GlobalLock(h) else { return nil }
        defer { GlobalUnlock(h) }
        return String(decodingCString: p.assumingMemoryBound(to: UInt16.self), as: UTF16.self)
    }
    public func readObjects(forClasses c: [AnyClass], options: [String: Any]?) -> [Any]? { nil }
    public func writeObjects(_ o: [Any]) -> Bool { false }
    public var types: [PasteboardType]? { nil }
    public func canReadObject(forClasses c: [AnyClass], options: [String: Any]?) -> Bool { false }
    public func data(forType t: PasteboardType) -> Data? { nil }
}
public protocol NSDraggingInfo: AnyObject {
    var draggingPasteboard: NSPasteboard { get }
    var draggingLocation: CGPoint { get }
}
public struct NSDragOperation: OptionSet, Sendable { public let rawValue: UInt; public init(rawValue: UInt) { self.rawValue = rawValue }; public static let copy = Self(rawValue: 1), link = Self(rawValue: 2), generic = Self(rawValue: 4), move = Self(rawValue: 16) ; public static let none = Self([]) ; public static let every = Self(rawValue: .max) }

public final class NSSound: NSObject, @unchecked Sendable {
    public var volume: Float = 1
    public var name: String?
    public init?(named n: String) { name = n; super.init() }
    public init?(contentsOf u: URL, byReference: Bool) { super.init() }
    public init?(data: Data) { super.init() }
    @discardableResult public func play() -> Bool { _ = MessageBeep(UINT(0xFFFFFFFF)); return true }
    @discardableResult public func stop() -> Bool { true }
    public var isPlaying: Bool { false }
    public static func beep() { _ = MessageBeep(UINT(0xFFFFFFFF)) }
}
public func NSSoundBeep() { NSSound.beep() }

public final class NSAnimationContext: NSObject, @unchecked Sendable {
    nonisolated(unsafe) private static let shared = NSAnimationContext()
    public static var current: NSAnimationContext { shared }
    public var duration: TimeInterval = 0.25
    public var timingFunction: CAMediaTimingFunction?
    public var allowsImplicitAnimation = false
    public var completionHandler: (() -> Void)?
    public static func beginGrouping() {}
    public static func endGrouping() { if let c = shared.completionHandler { shared.completionHandler = nil; c() } }
    /// Runs the changes at once; animator() proxies are the object itself for now, so they land immediately, and the
    /// completion follows on the next turn of the run loop.
    public static func runAnimationGroup(_ f: (NSAnimationContext) -> Void, completionHandler c: (() -> Void)? = nil) {
        f(shared)
        if let c { DispatchQueue.main.async(execute: c) }
    }
    public static func runAnimationGroup(_ f: (NSAnimationContext) -> Void) { f(shared) }
}
extension NSWindow { public func animator() -> Self { self } }
extension NSView { public func animator() -> Self { self } }
extension NSLayoutConstraint { public func animator() -> Self { self } }

// MARK: Toolbar

public protocol NSToolbarDelegate: AnyObject {
    func toolbar(_ t: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem?
    func toolbarDefaultItemIdentifiers(_ t: NSToolbar) -> [NSToolbarItem.Identifier]
    func toolbarAllowedItemIdentifiers(_ t: NSToolbar) -> [NSToolbarItem.Identifier]
}
extension NSToolbarDelegate {
    public func toolbarAllowedItemIdentifiers(_ t: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(t) }
}
open class NSToolbarItem: NSObject {
    public struct Identifier: RawRepresentable, Hashable, Sendable { public let rawValue: String; public init(rawValue: String) { self.rawValue = rawValue }; public init(_ s: String) { rawValue = s }
        public static let flexibleSpace = Self("NSToolbarFlexibleSpaceItem"), space = Self("NSToolbarSpaceItem") }
    public let itemIdentifier: Identifier
    public var label = ""
    public var paletteLabel = ""
    public var toolTip: String?
    public var image: NSImage?
    public var view: NSView?
    public weak var target: AnyObject?
    public var action: Selector?
    public var isEnabled = true
    public var isBordered = false
    public var isNavigational = false
    public var visibilityPriority = 0
    public var menuFormRepresentation: NSMenuItem?
    public init(itemIdentifier i: Identifier) { itemIdentifier = i }
}
open class NSToolbarItemGroup: NSToolbarItem { public var subitems: [NSToolbarItem] = [] }
/// A toolbar is a strip of the window's content here: the host window lays its items out along the top.
open class NSToolbar: NSObject {
    public struct DisplayMode: Sendable { public let rawValue: Int; public init(rawValue: Int) { self.rawValue = rawValue }; public static let `default` = Self(rawValue: 0), iconAndLabel = Self(rawValue: 1), iconOnly = Self(rawValue: 2), labelOnly = Self(rawValue: 3) }
    public let identifier: String
    public weak var delegate: NSToolbarDelegate?
    public var displayMode = DisplayMode.default
    public var allowsUserCustomization = false
    public var autosavesConfiguration = false
    public var showsBaselineSeparator = true
    public var isVisible = true
    public var sizeMode = 0
    public var centeredItemIdentifiers: Set<NSToolbarItem.Identifier> = []
    public var items: [NSToolbarItem] { [] }
    public weak var window: NSWindow?
    public init(identifier i: String) { identifier = i; super.init() }
    public func validateVisibleItems() {}
}
public protocol NSWindowRestoration {}
