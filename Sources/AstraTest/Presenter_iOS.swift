#if os(iOS)
import UIKit
import SwiftUI
import ObjectiveC

private var privateKey: UInt8 = 0
public extension UIView {
    /// Blacked out in report screenshots. Password fields are always hidden.
    var astraPrivate: Bool {
        get { (objc_getAssociatedObject(self, &privateKey) as? Bool) ?? false }
        set { objc_setAssociatedObject(self, &privateKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}

/// Our own window above the app: lets touches through everywhere except on the Report button and the sheet.
final class OverlayWindow: UIWindow {
    var takesAllTouches = false
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let v = super.hitTest(point, with: event)
        if takesAllTouches { return v }
        return v === rootViewController?.view ? nil : v
    }
}

final class OverlayController: UIViewController {
    let button = UIButton(type: .system)
    override func loadView() { view = UIView(); view.backgroundColor = .clear }
    override func viewDidLoad() {
        super.viewDidLoad()
        var c = UIButton.Configuration.filled()
        c.title = "Report"; c.image = UIImage(systemName: "sparkle"); c.imagePadding = 6; c.cornerStyle = .capsule
        c.baseBackgroundColor = UIColor(red: 0.055, green: 0.102, blue: 0.239, alpha: 1); c.baseForegroundColor = .white
        c.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
        button.configuration = c
        button.layer.shadowColor = UIColor.black.cgColor; button.layer.shadowOpacity = 0.25; button.layer.shadowRadius = 8; button.layer.shadowOffset = CGSize(width: 0, height: 3)
        button.addTarget(self, action: #selector(tap), for: .touchUpInside)
        button.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(drag(_:))))
        button.accessibilityLabel = "Report an issue"
        button.isHidden = !Presenter.buttonVisible
        view.addSubview(button)
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if button.frame == .zero {
            button.sizeToFit()
            let g = view.safeAreaLayoutGuide.layoutFrame
            button.frame.origin = CGPoint(x: g.maxX - button.bounds.width - 16, y: g.maxY - button.bounds.height - 16)
        }
    }
    @objc private func tap() { Presenter.showReport() }
    @objc private func drag(_ g: UIPanGestureRecognizer) {
        let t = g.translation(in: view)
        button.center = CGPoint(x: button.center.x + t.x, y: button.center.y + t.y)
        g.setTranslation(.zero, in: view)
        if g.state == .ended {
            let f = view.safeAreaLayoutGuide.layoutFrame.insetBy(dx: 8, dy: 8)
            button.frame.origin.x = min(max(button.frame.minX, f.minX), f.maxX - button.bounds.width)
            button.frame.origin.y = min(max(button.frame.minY, f.minY), f.maxY - button.bounds.height)
        }
    }
    override var preferredStatusBarStyle: UIStatusBarStyle { Presenter.appWindow()?.rootViewController?.preferredStatusBarStyle ?? .default }
}

enum Presenter {
    static var overlay: OverlayWindow?
    static var buttonVisible = true
    static var model: ReportModel?
    static var installTries = 0

    static func install(showButton: Bool, shake: Bool) {
        buttonVisible = showButton
        if shake { swizzleShake() }
        attach()
    }

    private static func attach() {
        guard overlay == nil else { return }
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            installTries += 1
            if installTries < 40 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { attach() } }
            return
        }
        let w = OverlayWindow(windowScene: scene)
        w.windowLevel = .alert + 1
        w.backgroundColor = .clear
        w.rootViewController = OverlayController()
        w.isHidden = false
        overlay = w
    }

    static func appWindow() -> UIWindow? {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }.filter { !($0 is OverlayWindow) && !$0.isHidden }
        return windows.first(where: { $0.isKeyWindow }) ?? windows.first
    }

    static func currentScreen() -> String? {
        var vc = appWindow()?.rootViewController
        while true {
            if let p = vc?.presentedViewController, !(p is UIAlertController) { vc = p; continue }
            if let n = vc as? UINavigationController { vc = n.visibleViewController ?? n.topViewController; if vc is UINavigationController { continue } }
            if let t = vc as? UITabBarController, let s = t.selectedViewController { vc = s; continue }
            break
        }
        guard let v = vc else { return nil }
        if let t = v.navigationItem.title ?? v.title, !t.isEmpty { return t }
        let name = String(describing: type(of: v)).components(separatedBy: "<").first ?? ""
        if name.hasPrefix("UIHosting") || name.hasPrefix("_") { return nil }
        return name.replacingOccurrences(of: "ViewController", with: "").replacingOccurrences(of: "Controller", with: "")
    }

    static func showReport() {
        guard AstraTest.started else { return }
        if overlay == nil { attach() }
        guard let overlay, let root = overlay.rootViewController, root.presentedViewController == nil else { return }
        let m = model ?? ReportModel(screenshot: Screenshot.capture())
        model = m
        m.onClose = { close() }
        m.onPick = { pick() }
        let host = UIHostingController(rootView: ReportView(model: m))
        if let sheet = host.sheetPresentationController { sheet.detents = [.medium(), .large()]; sheet.prefersGrabberVisible = true }
        host.presentationController?.delegate = Dismissal.shared
        overlay.takesAllTouches = true
        overlay.makeKey()
        (root as? OverlayController)?.button.isHidden = true
        root.present(host, animated: true)
    }

    static func close() {
        overlay?.rootViewController?.dismiss(animated: true) { finish() }
    }

    static func finish() {
        model = nil
        overlay?.takesAllTouches = false
        (overlay?.rootViewController as? OverlayController)?.button.isHidden = !buttonVisible
        appWindow()?.makeKey()
    }

    /// Hide the sheet, let the user tap the thing that's wrong, then bring the sheet back with it selected.
    static func pick() {
        guard let root = overlay?.rootViewController else { return }
        root.dismiss(animated: true) {
            let layer = PickView(frame: root.view.bounds)
            layer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            layer.onPick = { point in
                if let win = appWindow(), let hit = win.hitTest(root.view.convert(point, to: win), with: nil) {
                    model?.element = Element.describe(hit, in: win)
                    layer.highlight(hit.convert(hit.bounds, to: root.view))
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { layer.removeFromSuperview(); showReport() }
            }
            layer.onCancel = { layer.removeFromSuperview(); showReport() }
            root.view.addSubview(layer)
        }
    }

    private static func swizzleShake() {
        let cls: AnyClass = UIWindow.self
        let orig = #selector(UIResponder.motionEnded(_:with:))
        let repl = #selector(UIWindow.astra_motionEnded(_:with:))
        guard let mine = class_getInstanceMethod(cls, repl) else { return }
        if class_addMethod(cls, orig, method_getImplementation(mine), method_getTypeEncoding(mine)) {
            if let base = class_getInstanceMethod(UIResponder.self, orig) { class_replaceMethod(cls, repl, method_getImplementation(base), method_getTypeEncoding(base)) }
        } else if let existing = class_getInstanceMethod(cls, orig) {
            method_exchangeImplementations(existing, mine)
        }
    }
}

final class Dismissal: NSObject, UIAdaptivePresentationControllerDelegate {
    static let shared = Dismissal()
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { Presenter.finish() }
}

extension UIWindow {
    @objc func astra_motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake && !(self is OverlayWindow) { AstraTest.showReport() }
        astra_motionEnded(motion, with: event)
    }
}

final class PickView: UIView {
    var onPick: ((CGPoint) -> Void)?
    var onCancel: (() -> Void)?
    private let box = UIView()
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.12)
        let tip = UILabel()
        tip.text = "  Tap what's wrong  "
        tip.font = .systemFont(ofSize: 15, weight: .semibold); tip.textColor = .white
        tip.backgroundColor = UIColor(red: 0.184, green: 0.333, blue: 0.831, alpha: 1)
        tip.layer.cornerRadius = 16; tip.clipsToBounds = true; tip.textAlignment = .center
        tip.translatesAutoresizingMaskIntoConstraints = false
        let cancel = UIButton(type: .system)
        cancel.setTitle("Cancel", for: .normal); cancel.setTitleColor(.white, for: .normal)
        cancel.backgroundColor = UIColor.black.withAlphaComponent(0.55); cancel.layer.cornerRadius = 16
        cancel.contentEdgeInsets = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
        cancel.translatesAutoresizingMaskIntoConstraints = false
        cancel.addTarget(self, action: #selector(cancelTap), for: .touchUpInside)
        addSubview(tip); addSubview(cancel)
        NSLayoutConstraint.activate([
            tip.centerXAnchor.constraint(equalTo: centerXAnchor), tip.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 12), tip.heightAnchor.constraint(equalToConstant: 32),
            cancel.centerXAnchor.constraint(equalTo: centerXAnchor), cancel.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])
        box.layer.borderColor = UIColor(red: 0.184, green: 0.333, blue: 0.831, alpha: 1).cgColor; box.layer.borderWidth = 2; box.layer.cornerRadius = 6
        box.isHidden = true; box.isUserInteractionEnabled = false
        addSubview(box)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func tapped(_ g: UITapGestureRecognizer) { isUserInteractionEnabled = false; onPick?(g.location(in: self)) }
    @objc private func cancelTap() { onCancel?() }
    func highlight(_ r: CGRect) { box.frame = r.insetBy(dx: -3, dy: -3); box.isHidden = false }
}

enum Element {
    static func describe(_ v: UIView, in w: UIWindow) -> PickedElement {
        var name = String(describing: type(of: v)).components(separatedBy: "<").first ?? "View"
        if let id = v.accessibilityIdentifier, !id.isEmpty { name += "#\(id)" }
        return PickedElement(selector: name, text: text(of: v, depth: 0), frame: v.convert(v.bounds, to: w))
    }
    static func text(of v: UIView, depth: Int) -> String? {
        if let l = v as? UILabel, let t = l.text, !t.isEmpty { return t }
        if let b = v as? UIButton, let t = b.currentTitle, !t.isEmpty { return t }
        if let f = v as? UITextField { return f.isSecureTextEntry ? nil : (f.text?.isEmpty == false ? f.text : f.placeholder) }
        if let a = v.accessibilityLabel, !a.isEmpty { return a }
        guard depth < 3 else { return nil }
        for s in v.subviews { if let t = text(of: s, depth: depth + 1) { return t } }
        return nil
    }
}

enum Screenshot {
    static func capture() -> Data? {
        guard let w = Presenter.appWindow(), w.bounds.width > 0 else { return nil }
        let f = UIGraphicsImageRendererFormat(); f.scale = min(w.screen.scale, 2)
        let img = UIGraphicsImageRenderer(bounds: w.bounds, format: f).image { ctx in
            w.drawHierarchy(in: w.bounds, afterScreenUpdates: false)
            UIColor.black.setFill()
            for v in privateViews(in: w) { ctx.fill(v.convert(v.bounds, to: w)) }
        }
        return img.jpegData(compressionQuality: 0.7)
    }
    static func privateViews(in v: UIView) -> [UIView] {
        if v.isHidden || v.alpha < 0.01 { return [] }
        if v.astraPrivate || (v as? UITextField)?.isSecureTextEntry == true { return [v] }
        return v.subviews.flatMap { privateViews(in: $0) }
    }
}
#endif
