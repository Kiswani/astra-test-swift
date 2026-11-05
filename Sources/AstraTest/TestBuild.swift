import Foundation
#if canImport(StoreKit)
import StoreKit
#endif

/// Works out whether this copy of the app is a test build (Xcode, Simulator, development or ad hoc, TestFlight)
/// or an App Store build, for `AstraTest.start(key:enabledIn: .testBuilds)`.
enum TestBuild {
    /// App extensions (widgets, share, notification service) never run Astra Test.
    static var isAppExtension: Bool { Bundle.main.bundleURL.pathExtension == "appex" }

    static func detect(hint: Bool?, done: @escaping (_ isTest: Bool, _ why: String) -> Void) {
        let finish: (Bool, String) -> Void = { t, w in DispatchQueue.main.async { done(t, w) } }
        if let hint { finish(hint, hint ? "the app marked this as a test build" : "the app marked this as a release build"); return }
        #if targetEnvironment(simulator)
        finish(true, "Simulator")
        #else
        #if os(iOS)
        // Development and ad hoc builds carry a provisioning profile; App Store and TestFlight builds don't.
        if Bundle.main.path(forResource: "embedded", ofType: "mobileprovision") != nil { finish(true, "development or ad hoc build"); return }
        // TestFlight installs get a sandbox receipt. Checked before AppTransaction, which doesn't always say sandbox on TestFlight.
        if Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" { finish(true, "TestFlight build"); return }
        #elseif os(macOS)
        // Copies from the Mac App Store and TestFlight have a receipt; Xcode and directly distributed builds don't.
        if !(Bundle.main.appStoreReceiptURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false) {
            finish(true, "Xcode or direct build, not from the App Store or TestFlight"); return
        }
        #endif
        appTransaction(finish)
        #endif
    }

    private static func appTransaction(_ finish: @escaping (Bool, String) -> Void) {
        #if canImport(StoreKit)
        if #available(iOS 16.0, macOS 13.0, *) {
            Task.detached {
                do {
                    let result = try await AppTransaction.shared
                    let env: AppStore.Environment
                    switch result {
                    case .verified(let t): env = t.environment
                    case .unverified(let t, _): env = t.environment
                    }
                    if env == .production { finish(false, "App Store build") }
                    else if env == .sandbox { finish(true, "TestFlight build") }
                    else { finish(true, "Xcode build") }
                } catch {
                    finish(false, "couldn't tell whether this is a test build (\(error.localizedDescription)); pass testBuild: in Options to decide")
                }
            }
            return
        }
        #endif
        finish(false, "App Store build")
    }
}
