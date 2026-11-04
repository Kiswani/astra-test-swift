#if os(macOS)
import AppKit
import SwiftUI
import ObjectiveC

private var privateKey: UInt8 = 0
public extension NSView {
    /// Blacked out in report screenshots. Secure text fields are always hidden.
    var astraPrivate: Bool {
        get { (objc_getAssociatedObject(self, &privateKey) as? Bool) ?? false }
        set { objc_setAssociatedObject(self, &privateKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}

/// Panels Astra Test owns, so they're never mistaken for the app's own window.
final class AstraPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

enum Presenter {
    static var model: ReportModel?
    static var sheet: AstraPanel?
    static var button: AstraPanel?
    static var target: NSWindow?
    static var monitor: Any?

    static func install(showButton: Bool, shake: Bool) {
        if shake {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
                let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if mods == [.shift, .option], e.charactersIgnoringModifiers?.lowercased() == "r" || e.keyCode == 15 { showReport(); return nil }
                return e
            }
        }
        if showButton { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showFloatingButton() } }
    }

    static func appWindow() -> NSWindow? {
        let ok: (NSWindow) -> Bool = { !($0 is AstraPanel) && $0.isVisible && $0.contentView != nil }
        if let k = NSApplication.shared.keyWindow, ok(k) { return k }
        if let m = NSApplication.shared.mainWindow, ok(m) { return m }
        return NSApplication.shared.orderedWindows.first(where: ok)
    }

    static func currentScreen() -> String? {
        guard let t = appWindow()?.title, !t.isEmpty else { return nil }
        return t
    }

    private static func showFloatingButton() {
        guard button == nil else { return }
        let p = AstraPanel(contentRect: NSRect(x: 0, y: 0, width: 104, height: 34), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isFloatingPanel = true; p.level = .floating; p.backgroundColor = .clear; p.isOpaque = false; p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isMovableByWindowBackground = true
        p.contentView = NSHostingView(rootView: FloatingButton())
        if let s = NSScreen.main?.visibleFrame { p.setFrameOrigin(NSPoint(x: s.maxX - 124, y: s.minY + 20)) }
        p.orderFrontRegardless()
        button = p
    }

    static func showReport() {
        guard AstraTest.started else { return }
        if let s = sheet { s.makeKeyAndOrderFront(nil); return }
        target = appWindow()
        let m = model ?? ReportModel(screenshot: Screenshot.capture(target))
        model = m
        m.onClose = { close() }
        m.onPick = { pick() }
        let p = AstraPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 440), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        p.titleVisibility = .hidden; p.titlebarAppearsTransparent = true; p.level = .floating; p.isReleasedWhenClosed = false
        p.contentView = NSHostingView(rootView: ReportView(model: m).frame(width: 420, height: 420))
        if let t = target { let f = t.frame; p.setFrameOrigin(NSPoint(x: f.midX - 210, y: f.midY - 220)) } else { p.center() }
        p.delegate = Closer.shared
        sheet = p
        NSApplication.shared.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
    }

    static func close() { sheet?.close(); sheet = nil; model = nil; target?.makeKeyAndOrderFront(nil) }

    static func pick() {
        guard let t = target ?? appWindow(), let content = t.contentView else { return }
        sheet?.orderOut(nil)
        let o = AstraPanel(contentRect: t.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        o.level = .floating; o.backgroundColor = NSColor.black.withAlphaComponent(0.12); o.isOpaque = false; o.ignoresMouseEvents = false
        let v = PickNSView(frame: NSRect(origin: .zero, size: t.frame.size))
        v.onPick = { pointInOverlay in
            let p = content.superview?.convert(pointInOverlay, from: nil) ?? content.convert(pointInOverlay, from: nil)
            if let hit = content.hitTest(p) {
                model?.element = Element.describe(hit)
            }
            o.orderOut(nil)
            sheet?.makeKeyAndOrderFront(nil)
        }
        v.onCancel = { o.orderOut(nil); sheet?.makeKeyAndOrderFront(nil) }
        o.contentView = v
        o.makeKeyAndOrderFront(nil)
    }
}

final class Closer: NSObject, NSWindowDelegate {
    static let shared = Closer()
    func windowWillClose(_ notification: Notification) {
        if (notification.object as? AstraPanel) === Presenter.sheet { Presenter.sheet = nil; Presenter.model = nil }
    }
}

struct FloatingButton: View {
    var body: some View {
        Button(action: { AstraTest.showReport() }) {
            Label("Report", systemImage: "sparkle").font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(Color(red: 0.055, green: 0.102, blue: 0.239)))
        }
        .buttonStyle(.plain).help("Report an issue (⇧⌥R)")
    }
}

final class PickNSView: NSView {
    var onPick: ((NSPoint) -> Void)?
    var onCancel: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let s = "Click what's wrong · Esc to cancel" as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: NSColor.white]
        let size = s.size(withAttributes: attrs)
        let r = NSRect(x: bounds.midX - size.width / 2 - 14, y: bounds.maxY - 54, width: size.width + 28, height: 30)
        NSColor(red: 0.184, green: 0.333, blue: 0.831, alpha: 1).setFill(); NSBezierPath(roundedRect: r, xRadius: 15, yRadius: 15).fill()
        s.draw(at: NSPoint(x: r.minX + 14, y: r.minY + (30 - size.height) / 2), withAttributes: attrs)
    }
    override func mouseDown(with event: NSEvent) { onPick?(event.locationInWindow) }
    override func keyDown(with event: NSEvent) { if event.keyCode == 53 { onCancel?() } else { super.keyDown(with: event) } }
    override func viewDidMoveToWindow() { window?.makeFirstResponder(self) }
}

enum Element {
    static func describe(_ v: NSView) -> PickedElement {
        var name = String(describing: type(of: v)).components(separatedBy: "<").first ?? "View"
        let id = v.identifier?.rawValue ?? ""
        if !id.isEmpty && !id.hasPrefix("_NS") { name += "#\(id)" }
        return PickedElement(selector: name, text: text(of: v, depth: 0), frame: v.convert(v.bounds, to: nil))
    }
    static func text(of v: NSView, depth: Int) -> String? {
        if v is NSSecureTextField { return nil }
        if let f = v as? NSTextField, !f.stringValue.isEmpty { return f.stringValue }
        if let b = v as? NSButton, !b.title.isEmpty { return b.title }
        if let a = v.accessibilityLabel(), !a.isEmpty { return a }
        guard depth < 3 else { return nil }
        for s in v.subviews { if let t = text(of: s, depth: depth + 1) { return t } }
        return nil
    }
}

enum Screenshot {
    static func capture() -> Data? { capture(Presenter.appWindow()) }
    static func capture(_ window: NSWindow?) -> Data? {
        guard let view = window?.contentView, view.bounds.width > 0, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        let img = NSImage(size: view.bounds.size)
        img.addRepresentation(rep)
        let masked = NSImage(size: view.bounds.size)
        masked.lockFocus()
        img.draw(in: NSRect(origin: .zero, size: view.bounds.size))
        NSColor.black.setFill()
        for p in privateViews(in: view) {
            var r = p.convert(p.bounds, to: view)
            if view.isFlipped { r.origin.y = view.bounds.height - r.maxY }
            r.fill()
        }
        masked.unlockFocus()
        guard let tiff = masked.tiffRepresentation, let bmp = NSBitmapImageRep(data: tiff) else { return nil }
        return bmp.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
    }
    static func privateViews(in v: NSView) -> [NSView] {
        if v.isHidden || v.alphaValue < 0.01 { return [] }
        if v.astraPrivate || v is NSSecureTextField { return [v] }
        return v.subviews.flatMap { privateViews(in: $0) }
    }
}
#endif
