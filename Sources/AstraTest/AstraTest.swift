import Foundation

/// Astra Test for iOS and macOS.
///
/// ```swift
/// AstraTest.start(key: "pk_test_…")
/// AstraTest.identify(id: user.id, email: user.email, name: user.name)
/// ```
///
/// Testers press the Report button (or shake the device, or ⇧⌥R on the Mac), point at what's wrong and say it
/// in their own words. The SDK attaches a screenshot, recent network requests, log lines and device details.
public enum AstraTest {
    public struct Options {
        /// Your app's version. Defaults to `CFBundleShortVersionString`.
        public var appVersion: String?
        /// Your app's build number. Defaults to `CFBundleVersion`.
        public var build: String?
        /// Show the floating Report button. Defaults to `true` for `pk_test_` keys and `false` for `pk_live_`.
        public var showButton: Bool?
        /// Open the report sheet when the device is shaken (iOS) or on ⇧⌥R (macOS). Defaults to `true`.
        public var shakeToReport: Bool = true
        /// Record HTTP requests made through URLSession (method, URL without query, status, timing). Defaults to `true`.
        public var captureNetwork: Bool = true
        /// Copy what the app prints to stdout and stderr (print, NSLog) into reports. Defaults to `true`.
        public var captureLogs: Bool = true
        /// Where reports are sent. Defaults to `https://astratest.dev`.
        public var host: URL = URL(string: "https://astratest.dev")!

        public init(appVersion: String? = nil, build: String? = nil, showButton: Bool? = nil, shakeToReport: Bool = true,
                    captureNetwork: Bool = true, captureLogs: Bool = true, host: URL = URL(string: "https://astratest.dev")!) {
            self.appVersion = appVersion; self.build = build; self.showButton = showButton; self.shakeToReport = shakeToReport
            self.captureNetwork = captureNetwork; self.captureLogs = captureLogs; self.host = host
        }
    }

    /// A report that was sent: its reference (`AT-123`) and a link to it in Astra Test.
    public struct SentReport: Equatable {
        public let ref: String
        public let url: URL?
        public let title: String?
    }

    static var key: String?
    static var options = Options()
    static var reporter: [String: String] = [:]
    static var testCase: String?
    static var screenName: String?
    static var started = false

    /// Starts Astra Test. Call once, early, for example in `application(_:didFinishLaunchingWithOptions:)` or your `App`'s `init`.
    public static func start(key: String, options: Options = Options()) {
        guard !started else { return }
        guard key.range(of: #"^pk_(test|live)_[0-9a-f]{24}$"#, options: .regularExpression) != nil else {
            print("[AstraTest] That isn't a project key. Copy it from SDK setup in Astra Test (pk_test_… or pk_live_…).")
            return
        }
        started = true
        self.key = key
        self.options = options
        if options.captureLogs { LogCapture.shared.start() }
        if options.captureNetwork { NetworkCapture.install() }
        Sender.announceBuild()
        DispatchQueue.main.async { Presenter.install(showButton: options.showButton ?? key.hasPrefix("pk_test_"), shake: options.shakeToReport) }
    }

    /// Says who is testing, so reports show their name and they can be asked if a fix works.
    public static func identify(id: String? = nil, email: String? = nil, name: String? = nil) {
        var r: [String: String] = [:]
        if let id { r["id"] = id }
        if let email { r["email"] = email }
        if let name { r["name"] = name }
        reporter = r
    }

    /// The test case being run, such as `"UAT-02"`. Reports are linked to it.
    public static func setTestCase(_ ref: String?) { testCase = ref }

    /// The screen the user is on, such as `"Checkout"`. Detected automatically on iOS; set it to be precise.
    public static func setScreen(_ name: String?) { screenName = name }

    /// Opens the report sheet, for example from your own "Report a problem" menu item.
    public static func showReport() { DispatchQueue.main.async { Presenter.showReport() } }

    /// Adds a line to the log attached to reports.
    public static func log(_ message: String, level: String = "log") { LogCapture.shared.append(level: level, message: message) }

    /// Records requests made by a URLSession you created with your own configuration. Call before creating the session.
    /// (Sessions using `.default`, `.ephemeral` and `URLSession.shared` are recorded automatically.)
    public static func instrument(_ configuration: URLSessionConfiguration) { NetworkCapture.instrument(configuration) }

    /// Sends a report without showing the sheet, for example from a custom feedback form.
    public static func send(description: String, severity: String? = nil, completion: @escaping (Result<SentReport, Error>) -> Void) {
        let shot = Screenshot.capture()
        Sender.send(description: description, severity: severity, element: nil, screenshot: shot, completion: completion)
    }
}
